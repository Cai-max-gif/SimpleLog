import 'dart:async';

import 'package:flutter_cloud_sync_supabase/flutter_cloud_sync_supabase.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

import '../../db.dart';
import '../transaction_repository.dart';
import '../../../services/system/logger_service.dart';

/// 云端交易Repository实现
/// 基于 Supabase 实现
class CloudTransactionRepository implements TransactionRepository {
  final SupabaseProvider supabase;

  // 缓存 Stream 以避免重复订阅
  final Map<String, Stream<List<({Transaction t, Category? category})>>> _streamCache = {};

  CloudTransactionRepository(this.supabase);

  @override
  Stream<List<Transaction>> watchRecentTransactions({
    required int ledgerId,
    int limit = 20,
  }) {
    final controller = StreamController<List<Transaction>>();

    // 立即获取初始数据
    _fetchRecentTransactions(ledgerId: ledgerId, limit: limit).then((txs) {
      if (!controller.isClosed) {
        controller.add(txs);
      }
    });

    // 创建 Realtime 频道
    final channel = supabase.realtimeService!.channel('transactions:$ledgerId');

    // 监听交易变化
    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'transactions',
      filter: 'ledger_id=eq.$ledgerId',  // 只监听指定账本的变化
      callback: (payload) async {
        try {
          final txs = await _fetchRecentTransactions(
            ledgerId: ledgerId,
            limit: limit,
          );
          if (!controller.isClosed) {
            controller.add(txs);
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      },
    );

    channel.subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  Future<List<Transaction>> _fetchRecentTransactions({
    required int ledgerId,
    int limit = 20,
  }) async {
    final results = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
      ],
      orderBy: 'happened_at',
      descending: true,
      limit: limit,
    );

    return results.map((data) => _transactionFromJson(data)).toList();
  }

  @override
  Stream<List<Transaction>> watchTransactionsInMonth({
    required int ledgerId,
    required DateTime month,
  }) {
    final controller = StreamController<List<Transaction>>();

    // 计算月份的开始和结束
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    // 立即获取初始数据
    _fetchTransactionsInRange(
      ledgerId: ledgerId,
      start: start,
      end: end,
    ).then((txs) {
      if (!controller.isClosed) {
        controller.add(txs);
      }
    });

    // 创建 Realtime 频道
    final channel = supabase.realtimeService!
        .channel('transactions:$ledgerId:${month.year}-${month.month}');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'transactions',
      filter: 'ledger_id=eq.$ledgerId',  // 只监听指定账本的变化
      callback: (payload) async {
        try {
          final txs = await _fetchTransactionsInRange(
            ledgerId: ledgerId,
            start: start,
            end: end,
          );
          if (!controller.isClosed) {
            controller.add(txs);
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      },
    );

    channel.subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  Future<List<Transaction>> _fetchTransactionsInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    final results = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
        QueryFilter(
          column: 'happened_at',
          operator: 'gte',
          value: start.toIso8601String(),
        ),
        QueryFilter(
          column: 'happened_at',
          operator: 'lt',
          value: end.toIso8601String(),
        ),
      ],
      orderBy: 'happened_at',
      descending: true,
    );

    return results.map((data) => _transactionFromJson(data)).toList();
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryAll({
    int? ledgerId,
  }) {
    final cacheKey = 'all:${ledgerId ?? 'global'}';

    // 如果已缓存，直接返回
    if (_streamCache.containsKey(cacheKey)) {
      logger.info('CloudTransactionRepo', '返回缓存的stream: ledgerId=$ledgerId');
      return _streamCache[cacheKey]!;
    }

    logger.info('CloudTransactionRepo', '创建新的watchTransactionsWithCategoryAll stream: ledgerId=$ledgerId');

    final controller = StreamController<List<({Transaction t, Category? category})>>.broadcast(
      onCancel: () {
        // 当所有监听器都取消时，清除缓存
        logger.info('CloudTransactionRepo', 'stream被取消，清除缓存: ledgerId=$ledgerId');
        _streamCache.remove(cacheKey);
      },
    );

    // 构建过滤条件
    final filters = <QueryFilter>[];
    if (ledgerId != null) {
      filters.add(QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId));
    }

    // 立即获取初始数据
    logger.info('CloudTransactionRepo', '开始获取初始数据: ledgerId=$ledgerId');
    _fetchTransactionsWithCategory(
      filters: filters,
    ).then((data) {
      logger.info('CloudTransactionRepo', '初始数据获取成功: ledgerId=$ledgerId, count=${data.length}');
      if (!controller.isClosed) {
        controller.add(data);
      }
    }).catchError((e, stackTrace) {
      logger.error('CloudTransactionRepo', '初始数据获取失败: ledgerId=$ledgerId', e, stackTrace);
      if (!controller.isClosed) {
        controller.addError(e);
      }
    });

    // 创建 Realtime 频道监听 transactions 表变化
    final channelName = ledgerId != null
        ? 'transactions_with_category:all:$ledgerId'
        : 'transactions_with_category:all:global';
    final channel = supabase.realtimeService!.channel(channelName);

    logger.info('CloudTransactionRepo', '设置Realtime订阅: ledgerId=$ledgerId');

    if (ledgerId != null) {
      // 指定账本：监听特定账本的变化
      channel.onPostgresChanges(
        event: '*',
        schema: 'public',
        table: 'transactions',
        filter: 'ledger_id=eq.$ledgerId',
        callback: (payload) async {
          logger.info('CloudTransactionRepo', 'Realtime回调触发: ledgerId=$ledgerId');
          try {
            final data = await _fetchTransactionsWithCategory(filters: filters);
            logger.info('CloudTransactionRepo', 'Realtime数据刷新成功: ledgerId=$ledgerId, count=${data.length}');
            if (!controller.isClosed) {
              controller.add(data);
            }
          } catch (e, stackTrace) {
            logger.error('CloudTransactionRepo', 'Realtime数据刷新失败: ledgerId=$ledgerId', e, stackTrace);
            if (!controller.isClosed) {
              controller.addError(e);
            }
          }
        },
      );
    } else {
      // 全局：监听所有交易变化
      channel.onPostgresChanges(
        event: '*',
        schema: 'public',
        table: 'transactions',
        callback: (payload) async {
          logger.info('CloudTransactionRepo', 'Realtime回调触发: global');
          try {
            final data = await _fetchTransactionsWithCategory(filters: filters);
            logger.info('CloudTransactionRepo', 'Realtime数据刷新成功: global, count=${data.length}');
            if (!controller.isClosed) {
              controller.add(data);
            }
          } catch (e, stackTrace) {
            logger.error('CloudTransactionRepo', 'Realtime数据刷新失败: global', e, stackTrace);
            if (!controller.isClosed) {
              controller.addError(e);
            }
          }
        },
      );
    }

    channel.subscribe();
    logger.info('CloudTransactionRepo', 'Realtime订阅已启动: ledgerId=$ledgerId');

    // 当 controller 关闭时取消订阅
    controller.onCancel = () {
      channel.unsubscribe();
    };

    final stream = controller.stream;
    _streamCache[cacheKey] = stream;

    return stream;
  }

  /// 兼容旧方法名
  @override
  Stream<List<({Transaction t, Category? category})>> transactionsWithCategoryAll({
    int? ledgerId,
  }) =>
      watchTransactionsWithCategoryAll(ledgerId: ledgerId);

  @override
  Future<List<({Transaction t, Category? category})>> getRecentTransactionsWithCategory({
    required int ledgerId,
    required int limit,
  }) async {
    // 直接从 watchTransactionsWithCategoryAll 获取第一个值并截取
    final all = await watchTransactionsWithCategoryAll(ledgerId: ledgerId).first;
    return all.take(limit).toList();
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryInMonth({
    required int ledgerId,
    required DateTime month,
  }) {
    final controller = StreamController<List<({Transaction t, Category? category})>>();

    // 计算月份的开始和结束
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    // 立即获取初始数据
    _fetchTransactionsWithCategory(
      filters: [
        QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
        QueryFilter(column: 'happened_at', operator: 'gte', value: start.toIso8601String()),
        QueryFilter(column: 'happened_at', operator: 'lt', value: end.toIso8601String()),
      ],
    ).then((data) {
      if (!controller.isClosed) {
        controller.add(data);
      }
    });

    // 创建 Realtime 频道监听 transactions 表变化
    final channel = supabase.realtimeService!
        .channel('transactions_with_category:month:$ledgerId:${month.year}-${month.month}');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'transactions',
      filter: 'ledger_id=eq.$ledgerId',  // 只监听指定账本的变化
      callback: (payload) async {
        try {
          final data = await _fetchTransactionsWithCategory(
            filters: [
              QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
              QueryFilter(column: 'happened_at', operator: 'gte', value: start.toIso8601String()),
              QueryFilter(column: 'happened_at', operator: 'lt', value: end.toIso8601String()),
            ],
          );
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      },
    );

    channel.subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryInYear({
    required int ledgerId,
    required int year,
  }) {
    final controller = StreamController<List<({Transaction t, Category? category})>>();

    // 计算年份的开始和结束
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);

    // 立即获取初始数据
    _fetchTransactionsWithCategory(
      filters: [
        QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
        QueryFilter(column: 'happened_at', operator: 'gte', value: start.toIso8601String()),
        QueryFilter(column: 'happened_at', operator: 'lt', value: end.toIso8601String()),
      ],
    ).then((data) {
      if (!controller.isClosed) {
        controller.add(data);
      }
    });

    // 创建 Realtime 频道监听 transactions 表变化
    final channel = supabase.realtimeService!
        .channel('transactions_with_category:year:$ledgerId:$year');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'transactions',
      filter: 'ledger_id=eq.$ledgerId',  // 只监听指定账本的变化
      callback: (payload) async {
        try {
          final data = await _fetchTransactionsWithCategory(
            filters: [
              QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
              QueryFilter(column: 'happened_at', operator: 'gte', value: start.toIso8601String()),
              QueryFilter(column: 'happened_at', operator: 'lt', value: end.toIso8601String()),
            ],
          );
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      },
    );

    channel.subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsForCategoryInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
    int? categoryId,
    required String type,
  }) {
    final controller = StreamController<List<({Transaction t, Category? category})>>();

    // 构建过滤条件
    final filters = <QueryFilter>[
      QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
      QueryFilter(column: 'happened_at', operator: 'gte', value: start.toIso8601String()),
      QueryFilter(column: 'happened_at', operator: 'lt', value: end.toIso8601String()),
      QueryFilter(column: 'type', operator: 'eq', value: type),
    ];

    if (categoryId != null) {
      filters.add(QueryFilter(column: 'category_id', operator: 'eq', value: categoryId));
    }

    // 立即获取初始数据
    _fetchTransactionsWithCategory(filters: filters).then((data) {
      if (!controller.isClosed) {
        controller.add(data);
      }
    });

    // 创建 Realtime 频道监听 transactions 表变化
    final channel = supabase.realtimeService!
        .channel('transactions_with_category:range:$ledgerId:$categoryId:$type');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'transactions',
      filter: 'ledger_id=eq.$ledgerId',  // 只监听指定账本的变化
      callback: (payload) async {
        try {
          final data = await _fetchTransactionsWithCategory(filters: filters);
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      },
    );

    channel.subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  @override
  Future<int> addTransaction({
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    required DateTime happenedAt,
    String? note,
    String? syncId,
  }) async {
    final result = await supabase.databaseService!.insert(
      table: 'transactions',
      data: {
        'user_id': supabase.client?.auth.currentUser?.id, // 数据所有者
        'ledger_id': ledgerId,
        'type': type,
        'amount': amount,
        'category_id': categoryId,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'happened_at': happenedAt.toIso8601String(),
        'note': note,
        'created_by': supabase.client?.auth.currentUser?.id, // 创建者（用于审计）
      },
    );

    return result['id'] as int;
  }

  @override
  Future<int> insertTransactionsBatch(List<TransactionsCompanion> items) async {
    // 云端不支持 Companion 对象，需要转换为 Map
    throw UnimplementedError('批量插入暂不支持云端模式');
  }

  @override
  Future<int> insertTransactionCompanion(TransactionsCompanion item) async {
    // 云端不支持 Companion 对象
    throw UnimplementedError('Companion 插入暂不支持云端模式');
  }

  @override
  Future<void> updateTransaction({
    required int id,
    required String type,
    required double amount,
    int? categoryId,
    String? note,
    DateTime? happenedAt,
    dynamic accountId,
  }) async {
    logger.info('CloudTransactionRepo', '更新交易: id=$id, type=$type, amount=$amount, categoryId=$categoryId, note=$note, happenedAt=$happenedAt, accountId=$accountId');

    final data = <String, dynamic>{
      'type': type,
      'amount': amount,
      'category_id': categoryId,
      'note': note,
    };

    if (happenedAt != null) {
      data['happened_at'] = happenedAt.toIso8601String();
    }

    if (accountId != null) {
      data['account_id'] = accountId;
    }

    logger.info('CloudTransactionRepo', '更新数据: $data');

    await supabase.databaseService!.update(
      table: 'transactions',
      id: id.toString(),
      data: data,
    );

    logger.info('CloudTransactionRepo', '更新完成');
  }

  @override
  Future<void> deleteTransaction(int id) async {
    await supabase.databaseService!.delete(
      table: 'transactions',
      id: id.toString(),
    );
  }

  @override
  Future<Transaction?> getTransactionById(int id) async {
    final results = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'id', operator: 'eq', value: id),
      ],
    );
    if (results.isEmpty) return null;
    return _transactionFromJson(results.first);
  }

  @override
  Future<int> countByTypeInRange({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final results = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
        QueryFilter(column: 'type', operator: 'eq', value: type),
        QueryFilter(
          column: 'happened_at',
          operator: 'gte',
          value: start.toIso8601String(),
        ),
        QueryFilter(
          column: 'happened_at',
          operator: 'lt',
          value: end.toIso8601String(),
        ),
      ],
    );

    return results.length;
  }

  // ============================================
  // 辅助方法：数据转换
  // ============================================

  /// 从 JSON 转换为 Transaction 对象
  Transaction _transactionFromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as int,
      ledgerId: json['ledger_id'] as int,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      categoryId: json['category_id'] as int?,
      accountId: json['account_id'] as int?,
      toAccountId: json['to_account_id'] as int?,
      happenedAt: DateTime.parse(json['happened_at'] as String),
      note: json['note'] as String?,
      recurringId: json['recurring_id'] as int?,
    );
  }

  /// 从 JSON 转换为 Category 对象
  Category _categoryFromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      name: json['name'] as String,
      kind: json['kind'] as String,
      icon: json['icon'] as String?,
      parentId: json['parent_id'] as int?,
      sortOrder: json['sort_order'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      iconType: json['icon_type'] as String? ?? 'material',
      customIconPath: json['custom_icon_path'] as String?,
      communityIconId: json['community_icon_id'] as String?,
    );
  }

  /// 获取带分类信息的交易列表
  /// 通过两次查询实现：先查 transactions，再批量查 categories
  Future<List<({Transaction t, Category? category})>> _fetchTransactionsWithCategory({
    required List<QueryFilter> filters,
    String orderBy = 'happened_at',
    bool descending = true,
    int? limit,
  }) async {
    logger.info('CloudTransactionRepo', '查询交易: filters=$filters, orderBy=$orderBy, descending=$descending, limit=$limit');

    // 1. 查询交易
    final txResults = await supabase.databaseService!.query(
      table: 'transactions',
      filters: filters,
      orderBy: orderBy,
      descending: descending,
      limit: limit,
    );

    logger.info('CloudTransactionRepo', '查询结果: ${txResults.length} 条交易');

    if (txResults.isEmpty) {
      return [];
    }

    // 2. 提取所有 categoryId
    final categoryIds = txResults
        .map((tx) => tx['category_id'] as int?)
        .where((id) => id != null)
        .toSet()
        .toList();

    // 3. 批量查询分类
    final Map<int, Category> categoryMap = {};
    if (categoryIds.isNotEmpty) {
      final catResults = await supabase.databaseService!.query(
        table: 'categories',
        filters: [
          QueryFilter(column: 'id', operator: 'in', value: categoryIds),
        ],
      );

      for (final catData in catResults) {
        final category = _categoryFromJson(catData);
        categoryMap[category.id] = category;
      }
    }

    // 4. 组合交易和分类
    return txResults.map((txData) {
      final tx = _transactionFromJson(txData);
      final category = tx.categoryId != null ? categoryMap[tx.categoryId] : null;
      return (t: tx, category: category);
    }).toList();
  }

  @override
  Future<List<Transaction>> getTransactionsByLedger(int ledgerId) async {
    throw UnimplementedError('云端获取账本交易列表暂不支持');
  }

  @override
  Future<List<Transaction>> getTransactionsByLedgerInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    throw UnimplementedError('云端获取时间范围交易列表暂不支持');
  }

  @override
  Future<void> updateTransactionFields({
    required int id,
    int? accountId,
    int? toAccountId,
  }) async {
    throw UnimplementedError('云端更新交易字段暂不支持');
  }

  @override
  Future<Transaction?> getFirstTransactionByLedger(int ledgerId) async {
    throw UnimplementedError('云端获取首笔交易暂不支持');
  }

  @override
  Future<Transaction?> getLastTransactionByLedger(int ledgerId) async {
    throw UnimplementedError('云端获取末笔交易暂不支持');
  }

  @override
  Future<void> updateTransactionLedger({
    required int id,
    required int ledgerId,
  }) async {
    throw UnimplementedError('云端更新交易账本暂不支持');
  }

  // ==================== 日历功能相关 ====================

  @override
  Future<Map<String, (double income, double expense)>> getDailyTotalsByMonth({
    required int ledgerId,
    required DateTime month,
  }) async {
    throw UnimplementedError('云端日历功能暂不支持');
  }

  @override
  Future<List<({
    Transaction t,
    Category? category,
    List<Tag> tags,
    List<TransactionAttachment> attachments,
    Account? account,
  })>> getTransactionsByDate({
    required int ledgerId,
    required DateTime date,
  }) async {
    throw UnimplementedError('云端日历功能暂不支持');
  }

  @override
  Future<List<({
    Transaction t,
    Category? category,
    List<Tag> tags,
    List<TransactionAttachment> attachments,
    Account? account,
  })>> getTransactionsByDateRange({
    required int ledgerId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    throw UnimplementedError('云端日历功能暂不支持');
  }

  @override
  Future<List<String>> getTransactionDatesByMonth({
    required int ledgerId,
    required DateTime month,
  }) async {
    throw UnimplementedError('云端日历功能暂不支持');
  }

  @override
  Future<Transaction?> getTransactionBySyncId(String syncId) async {
    throw UnimplementedError('云端 syncId 查询暂不支持');
  }

  @override
  Future<void> updateTransactionBySyncId({
    required String syncId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    required DateTime happenedAt,
    String? note,
  }) async {
    throw UnimplementedError('云端 syncId 更新暂不支持');
  }

  @override
  Future<void> deleteTransactionBySyncId(String syncId) async {
    throw UnimplementedError('云端 syncId 删除暂不支持');
  }
}
