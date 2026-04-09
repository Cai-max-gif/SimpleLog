import 'dart:async';
import 'package:flutter_cloud_sync_supabase/flutter_cloud_sync_supabase.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

import '../recurring_transaction_repository.dart';
import '../../db.dart';
import '../../../services/system/logger_service.dart';

/// 云端周期记账 Repository 实现
class CloudRecurringTransactionRepository
    implements RecurringTransactionRepository {
  final SupabaseProvider supabase;
  final Map<String, Stream<List<RecurringTransaction>>> _streamCache = {};
  final Map<String, StreamController<List<RecurringTransaction>>>
      _controllerCache = {};

  CloudRecurringTransactionRepository(this.supabase);

  @override
  Future<List<RecurringTransaction>> getAllRecurringTransactions() async {
    logger.info('CloudRecurringTransactionRepo', '查询所有周期记账');

    final results = await supabase.databaseService!.query(
      table: 'recurring_transactions',
      orderBy: 'created_at',
      descending: true,
    );

    logger.info('CloudRecurringTransactionRepo', '查询结果: ${results.length} 条');

    return results.map((data) => _recurringTransactionFromJson(data)).toList();
  }

  @override
  Future<List<RecurringTransaction>> getRecurringTransactionsByLedger(
      int ledgerId) async {
    logger.info('CloudRecurringTransactionRepo', '查询账本的周期记账: ledgerId=$ledgerId');

    final results = await supabase.databaseService!.query(
      table: 'recurring_transactions',
      filters: [
        QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
      ],
      orderBy: 'created_at',
      descending: true,
    );

    logger.info('CloudRecurringTransactionRepo',
        '查询结果: ledgerId=$ledgerId, count=${results.length}');

    return results.map((data) => _recurringTransactionFromJson(data)).toList();
  }

  @override
  Future<List<RecurringTransaction>> getEnabledRecurringTransactions(
      int ledgerId) async {
    logger.info('CloudRecurringTransactionRepo',
        '查询启用的周期记账: ledgerId=$ledgerId');

    final results = await supabase.databaseService!.query(
      table: 'recurring_transactions',
      filters: [
        QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
        QueryFilter(column: 'enabled', operator: 'eq', value: true),
      ],
      orderBy: 'created_at',
      descending: true,
    );

    logger.info('CloudRecurringTransactionRepo',
        '查询结果: ledgerId=$ledgerId, enabled=true, count=${results.length}');

    return results.map((data) => _recurringTransactionFromJson(data)).toList();
  }

  @override
  Future<int> addRecurringTransaction({
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    String? note,
    required String frequency,
    required int interval,
    int? dayOfMonth,
    int? dayOfWeek,
    int? monthOfYear,
    required DateTime startDate,
    DateTime? endDate,
    bool enabled = true,
  }) async {
    logger.info('CloudRecurringTransactionRepo',
        '添加周期记账: ledgerId=$ledgerId, type=$type, amount=$amount');

    final userId = supabase.client?.auth.currentUser?.id;

    final data = {
      'user_id': userId,
      'ledger_id': ledgerId,
      'type': type,
      'amount': amount,
      'category_id': categoryId,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'note': note,
      'frequency': frequency,
      'interval': interval,
      'day_of_month': dayOfMonth,
      'day_of_week': dayOfWeek,
      'month_of_year': monthOfYear,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'enabled': enabled,
      'created_by': userId,
    };

    final result = await supabase.databaseService!.insert(
      table: 'recurring_transactions',
      data: data,
    );

    final id = result['id'] as int;
    logger.info('CloudRecurringTransactionRepo', '添加成功: id=$id');

    return id;
  }

  @override
  Future<void> updateRecurringTransaction({
    required int id,
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    String? note,
    required String frequency,
    required int interval,
    int? dayOfMonth,
    int? dayOfWeek,
    int? monthOfYear,
    required DateTime startDate,
    DateTime? endDate,
    bool? enabled,
  }) async {
    logger.info('CloudRecurringTransactionRepo', '更新周期记账: id=$id');

    final data = <String, dynamic>{
      'ledger_id': ledgerId,
      'type': type,
      'amount': amount,
      'category_id': categoryId,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'note': note,
      'frequency': frequency,
      'interval': interval,
      'day_of_month': dayOfMonth,
      'day_of_week': dayOfWeek,
      'month_of_year': monthOfYear,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
    };

    if (enabled != null) {
      data['enabled'] = enabled;
    }

    await supabase.databaseService!.update(
      table: 'recurring_transactions',
      id: id.toString(),
      data: data,
    );

    logger.info('CloudRecurringTransactionRepo', '更新成功: id=$id');
  }

  @override
  Future<void> deleteRecurringTransaction(int id) async {
    logger.info('CloudRecurringTransactionRepo', '删除周期记账: id=$id');

    await supabase.databaseService!.delete(
      table: 'recurring_transactions',
      id: id.toString(),
    );

    logger.info('CloudRecurringTransactionRepo', '删除成功: id=$id');
  }

  @override
  Future<void> toggleRecurringTransaction(int id, bool enabled) async {
    logger.info(
        'CloudRecurringTransactionRepo', '切换周期记账状态: id=$id, enabled=$enabled');

    // 更新数据
    final result = await supabase.databaseService!.update(
      table: 'recurring_transactions',
      id: id.toString(),
      data: {'enabled': enabled},
    );

    logger.info('CloudRecurringTransactionRepo', '切换成功: id=$id, enabled=$enabled, result=$result');

    // 验证更新是否成功：重新查询数据
    final verifyResult = await supabase.databaseService!.query(
      table: 'recurring_transactions',
      filters: [QueryFilter(column: 'id', operator: 'eq', value: id)],
    );

    if (verifyResult.isNotEmpty) {
      final actualEnabled = verifyResult.first['enabled'];
      logger.info('CloudRecurringTransactionRepo',
          '验证结果: id=$id, 数据库中的enabled=$actualEnabled');
    } else {
      logger.warning('CloudRecurringTransactionRepo', '验证失败: 未找到 id=$id 的记录');
    }

    // 手动刷新 stream，确保 UI 立即更新
    await _refreshAllRecurringTransactionsStream();
  }

  @override
  Future<void> updateLastGeneratedDate(int id, DateTime date) async {
    logger.info('CloudRecurringTransactionRepo',
        '更新最后生成日期: id=$id, date=${date.toIso8601String()}');

    await supabase.databaseService!.update(
      table: 'recurring_transactions',
      id: id.toString(),
      data: {'last_generated_date': date.toIso8601String()},
    );

    logger.info('CloudRecurringTransactionRepo', '更新最后生成日期成功: id=$id');
  }

  @override
  Stream<List<RecurringTransaction>> watchAllRecurringTransactions() {
    final cacheKey = 'all';

    // 如果已缓存，直接返回
    if (_streamCache.containsKey(cacheKey)) {
      logger.info('CloudRecurringTransactionRepo', '返回缓存的stream');
      return _streamCache[cacheKey]!;
    }

    logger.info('CloudRecurringTransactionRepo', '创建新的watchAllRecurringTransactions stream');

    final controller =
        StreamController<List<RecurringTransaction>>.broadcast(
      onCancel: () {
        logger.info('CloudRecurringTransactionRepo', 'stream被取消，清除缓存');
        _streamCache.remove(cacheKey);
        _controllerCache.remove(cacheKey);
      },
    );

    // 立即获取初始数据
    logger.info('CloudRecurringTransactionRepo', '开始获取初始数据');
    getAllRecurringTransactions().then((data) {
      logger.info('CloudRecurringTransactionRepo', '初始数据获取成功: count=${data.length}');
      if (!controller.isClosed) {
        controller.add(data);
      }
    }).catchError((e, stackTrace) {
      logger.error(
          'CloudRecurringTransactionRepo', '初始数据获取失败', e, stackTrace);
      if (!controller.isClosed) {
        controller.addError(e);
      }
    });

    // 创建 Realtime 频道监听变化
    final channel = supabase.realtimeService!
        .channel('recurring_transactions:all');

    logger.info('CloudRecurringTransactionRepo', '设置Realtime订阅');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'recurring_transactions',
      callback: (payload) async {
        logger.info('CloudRecurringTransactionRepo', 'Realtime回调触发');
        try {
          final data = await getAllRecurringTransactions();
          logger.info('CloudRecurringTransactionRepo',
              'Realtime数据刷新成功: count=${data.length}');
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (e, stackTrace) {
          logger.error(
              'CloudRecurringTransactionRepo', 'Realtime数据刷新失败', e, stackTrace);
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      },
    );

    channel.subscribe();
    logger.info('CloudRecurringTransactionRepo', 'Realtime订阅已启动');

    controller.onCancel = () {
      channel.unsubscribe();
    };

    final stream = controller.stream;
    _streamCache[cacheKey] = stream;
    _controllerCache[cacheKey] = controller; // 缓存 controller 以便后续手动触发更新

    return stream;
  }

  /// 手动刷新所有周期记账的 stream（用于手动更新后强制刷新 UI）
  Future<void> _refreshAllRecurringTransactionsStream() async {
    final cacheKey = 'all';
    final controller = _controllerCache[cacheKey];

    if (controller != null && !controller.isClosed) {
      logger.info('CloudRecurringTransactionRepo', '手动刷新stream');
      try {
        final data = await getAllRecurringTransactions();
        controller.add(data);
        logger.info('CloudRecurringTransactionRepo', '手动刷新成功: count=${data.length}');
      } catch (e, stackTrace) {
        logger.error(
            'CloudRecurringTransactionRepo', '手动刷新失败', e, stackTrace);
      }
    } else {
      logger.info('CloudRecurringTransactionRepo', '无需刷新（controller不存在或已关闭）');
    }
  }

  @override
  Stream<List<RecurringTransaction>> watchRecurringTransactionsByLedger(
      int ledgerId) {
    final cacheKey = 'ledger:$ledgerId';

    // 如果已缓存，直接返回
    if (_streamCache.containsKey(cacheKey)) {
      logger.info(
          'CloudRecurringTransactionRepo', '返回缓存的stream: ledgerId=$ledgerId');
      return _streamCache[cacheKey]!;
    }

    logger.info('CloudRecurringTransactionRepo',
        '创建新的watchRecurringTransactionsByLedger stream: ledgerId=$ledgerId');

    final controller =
        StreamController<List<RecurringTransaction>>.broadcast(
      onCancel: () {
        logger.info('CloudRecurringTransactionRepo',
            'stream被取消，清除缓存: ledgerId=$ledgerId');
        _streamCache.remove(cacheKey);
      },
    );

    // 立即获取初始数据
    logger.info('CloudRecurringTransactionRepo', '开始获取初始数据: ledgerId=$ledgerId');
    getRecurringTransactionsByLedger(ledgerId).then((data) {
      logger.info('CloudRecurringTransactionRepo',
          '初始数据获取成功: ledgerId=$ledgerId, count=${data.length}');
      if (!controller.isClosed) {
        controller.add(data);
      }
    }).catchError((e, stackTrace) {
      logger.error('CloudRecurringTransactionRepo',
          '初始数据获取失败: ledgerId=$ledgerId', e, stackTrace);
      if (!controller.isClosed) {
        controller.addError(e);
      }
    });

    // 创建 Realtime 频道监听变化（过滤指定账本）
    final channel = supabase.realtimeService!
        .channel('recurring_transactions:ledger:$ledgerId');

    logger.info('CloudRecurringTransactionRepo',
        '设置Realtime订阅: ledgerId=$ledgerId, filter=ledger_id=eq.$ledgerId');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'recurring_transactions',
      filter: 'ledger_id=eq.$ledgerId',
      callback: (payload) async {
        logger.info('CloudRecurringTransactionRepo',
            'Realtime回调触发: ledgerId=$ledgerId');
        try {
          final data = await getRecurringTransactionsByLedger(ledgerId);
          logger.info('CloudRecurringTransactionRepo',
              'Realtime数据刷新成功: ledgerId=$ledgerId, count=${data.length}');
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (e, stackTrace) {
          logger.error('CloudRecurringTransactionRepo',
              'Realtime数据刷新失败: ledgerId=$ledgerId', e, stackTrace);
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      },
    );

    channel.subscribe();
    logger.info(
        'CloudRecurringTransactionRepo', 'Realtime订阅已启动: ledgerId=$ledgerId');

    controller.onCancel = () {
      channel.unsubscribe();
    };

    final stream = controller.stream;
    _streamCache[cacheKey] = stream;

    return stream;
  }

  /// 将 JSON 数据转换为 RecurringTransaction 对象
  RecurringTransaction _recurringTransactionFromJson(
      Map<String, dynamic> json) {
    return RecurringTransaction(
      id: json['id'] as int,
      ledgerId: json['ledger_id'] as int,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      categoryId: json['category_id'] as int?,
      accountId: json['account_id'] as int?,
      toAccountId: json['to_account_id'] as int?,
      note: json['note'] as String?,
      frequency: json['frequency'] as String,
      interval: json['interval'] as int,
      dayOfMonth: json['day_of_month'] as int?,
      dayOfWeek: json['day_of_week'] as int?,
      monthOfYear: json['month_of_year'] as int?,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      lastGeneratedDate: json['last_generated_date'] != null
          ? DateTime.parse(json['last_generated_date'] as String)
          : null,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  @override
  Future<void> batchInsertRecurringTransactions(
      List<RecurringTransactionsCompanion> items) async {
    throw UnimplementedError('云端批量插入周期记账暂不支持');
  }
}
