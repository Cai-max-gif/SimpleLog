import 'dart:async';

import 'package:flutter_cloud_sync_supabase/flutter_cloud_sync_supabase.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

import '../../db.dart';
import '../category_repository.dart';
import '../../../services/system/logger_service.dart';

/// 云端分类Repository实现
/// 基于 Supabase 实现
class CloudCategoryRepository implements CategoryRepository {
  final SupabaseProvider supabase;

  CloudCategoryRepository(this.supabase);

  @override
  Future<int> createCategory({
    required String name,
    required String kind,
    String? icon,
    int? sortOrder,
  }) async {
    logger.info('CloudCategoryRepository', '📝 创建分类: name=$name, kind=$kind, icon=$icon, sortOrder=$sortOrder');

    final result = await supabase.databaseService!.insert(
      table: 'categories',
      data: {
        'name': name,
        'kind': kind,
        'icon': icon,
        'level': 1,
        'sort_order': sortOrder ?? 0,
      },
    );

    final categoryId = result['id'] as int;
    logger.info('CloudCategoryRepository', '✅ 分类创建成功: id=$categoryId');

    // 手动触发刷新
    _refreshCategoriesWithCount();

    return categoryId;
  }

  /// 手动刷新分类列表
  void _refreshCategoriesWithCount() {
    if (_categoriesController != null && !_categoriesController!.isClosed) {
      logger.info('CloudCategoryRepository', '🔄 手动刷新分类列表');
      _fetchCategoriesWithCount().then((data) {
        if (_categoriesController != null && !_categoriesController!.isClosed) {
          _categoriesController!.add(data);
        }
      }).catchError((e) {
        if (_categoriesController != null && !_categoriesController!.isClosed) {
          _categoriesController!.addError(e);
        }
      });
    }
  }

  @override
  Future<int> createSubCategory({
    required int parentId,
    required String name,
    required String kind,
    String? icon,
    int? sortOrder,
  }) async {
    logger.info('CloudCategoryRepository', '📝 创建子分类: name=$name, parentId=$parentId');

    final result = await supabase.databaseService!.insert(
      table: 'categories',
      data: {
        'name': name,
        'kind': kind,
        'icon': icon,
        'parent_id': parentId,
        'level': 2,
        'sort_order': sortOrder ?? 0,
      },
    );

    final categoryId = result['id'] as int;
    logger.info('CloudCategoryRepository', '✅ 子分类创建成功: id=$categoryId');

    // 手动触发刷新
    _refreshCategoriesWithCount();

    return categoryId;
  }

  @override
  Future<void> updateCategory(
    int id, {
    String? name,
    String? icon,
    int? parentId,
    int? level,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (icon != null) data['icon'] = icon;
    // parentId: -1 表示清空父分类，其他值表示设置父分类
    if (parentId != null) {
      data['parent_id'] = parentId == -1 ? null : parentId;
    }
    if (level != null) data['level'] = level;

    if (data.isNotEmpty) {
      await supabase.databaseService!.update(
        table: 'categories',
        id: id.toString(),
        data: data,
      );
    }
  }

  @override
  Future<void> deleteCategory(int id) async {
    // 先查询并删除该分类下的所有子分类
    final subCategories = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'parent_id', operator: 'eq', value: id),
      ],
    );
    for (final sub in subCategories) {
      await supabase.databaseService!.delete(
        table: 'categories',
        id: sub['id'].toString(),
      );
    }
    // 再删除该分类本身
    await supabase.databaseService!.delete(
      table: 'categories',
      id: id.toString(),
    );
  }

  @override
  Future<void> deleteCategoriesByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    // 云端暂时使用循环删除
    for (final id in ids) {
      await deleteCategory(id);
    }
  }

  @override
  Future<int> upsertCategory({
    required String name,
    required String kind,
  }) async {
    // 先查询是否存在
    final existing = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'name', operator: 'eq', value: name),
        QueryFilter(column: 'kind', operator: 'eq', value: kind),
      ],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }

    // 不存在则创建
    return createCategory(name: name, kind: kind);
  }

  @override
  Future<Category?> getCategoryById(int categoryId) async {
    final results = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'id', operator: 'eq', value: categoryId),
      ],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _categoryFromJson(results.first);
  }

  @override
  Future<List<Category>> getTopLevelCategories(String kind) async {
    final results = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'kind', operator: 'eq', value: kind),
        QueryFilter(column: 'level', operator: 'eq', value: 1),
      ],
      orderBy: 'sort_order',
    );

    return results.map((data) => _categoryFromJson(data)).toList();
  }

  @override
  Future<List<Category>> getSubCategories(int parentId) async {
    final results = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'parent_id', operator: 'eq', value: parentId),
      ],
      orderBy: 'sort_order',
    );

    return results.map((data) => _categoryFromJson(data)).toList();
  }

  @override
  Future<List<Category>> getUsableCategories(String kind) async {
    final results = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'kind', operator: 'eq', value: kind),
      ],
      orderBy: 'sort_order',
    );

    return results.map((data) => _categoryFromJson(data)).toList();
  }

  @override
  Future<bool> isCategoryNameDuplicate({
    required String name,
    int? excludeId,
  }) async {
    final filters = [
      QueryFilter(column: 'name', operator: 'eq', value: name),
    ];

    if (excludeId != null) {
      filters.add(
        QueryFilter(column: 'id', operator: 'neq', value: excludeId),
      );
    }

    final results = await supabase.databaseService!.query(
      table: 'categories',
      filters: filters,
      limit: 1,
    );

    return results.isNotEmpty;
  }

  @override
  Future<bool> hasSubCategories(int categoryId) async {
    final results = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'parent_id', operator: 'eq', value: categoryId),
      ],
      limit: 1,
    );

    return results.isNotEmpty;
  }

  @override
  Future<int> getSubCategoryCount(int categoryId) async {
    final results = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'parent_id', operator: 'eq', value: categoryId),
      ],
    );

    return results.length;
  }

  @override
  Future<int> getTransactionCountByCategory(int categoryId) async {
    final results = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'category_id', operator: 'eq', value: categoryId),
      ],
    );

    return results.length;
  }

  @override
  Future<Map<int, int>> getAllCategoryTransactionCounts() async {
    // 获取所有交易
    final transactions = await supabase.databaseService!.query(
      table: 'transactions',
    );

    // 统计每个分类的交易数量
    final counts = <int, int>{};
    for (final tx in transactions) {
      final categoryId = tx['category_id'] as int?;
      if (categoryId != null) {
        counts[categoryId] = (counts[categoryId] ?? 0) + 1;
      }
    }

    return counts;
  }

  @override
  Future<({int totalCount, double totalAmount, double averageAmount})>
      getCategorySummary(int categoryId) async {
    final results = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'category_id', operator: 'eq', value: categoryId),
      ],
    );

    if (results.isEmpty) {
      return (totalCount: 0, totalAmount: 0.0, averageAmount: 0.0);
    }

    final totalCount = results.length;
    final totalAmount = results.fold<double>(
      0.0,
      (sum, tx) => sum + (tx['amount'] as num).toDouble(),
    );
    final averageAmount = totalAmount / totalCount;

    return (
      totalCount: totalCount,
      totalAmount: totalAmount,
      averageAmount: averageAmount,
    );
  }

  @override
  Future<List<Transaction>> getTransactionsByCategory(int categoryId) async {
    final results = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'category_id', operator: 'eq', value: categoryId),
      ],
      orderBy: 'happened_at',
      descending: true,
    );

    return results.map((data) => _transactionFromJson(data)).toList();
  }

  @override
  Future<List<Transaction>> getTransactionsByCategoryWithSort(
    int categoryId, {
    String sortBy = 'time',
    bool ascending = false,
  }) async {
    String orderBy;
    switch (sortBy) {
      case 'amount':
        orderBy = 'amount';
        break;
      case 'time':
      default:
        orderBy = 'happened_at';
    }

    if (!ascending) {
      orderBy += ' DESC';
    }

    final results = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'category_id', operator: 'eq', value: categoryId),
      ],
      orderBy: orderBy,
    );

    return results.map((data) => _transactionFromJson(data)).toList();
  }

  @override
  Future<int> migrateCategory({
    required int fromCategoryId,
    required int toCategoryId,
  }) async {
    // 云端迁移需要更新所有交易的 category_id
    // 但 Supabase 不支持批量更新，暂不实现
    throw UnimplementedError('云端分类迁移暂不支持');
  }

  @override
  Future<({int migratedTransactions, int migratedSubCategories})>
      migrateCategoryTransactions({
    required int fromCategoryId,
    required int toCategoryId,
  }) async {
    throw UnimplementedError('云端分类迁移暂不支持');
  }

  @override
  Future<({int transactionCount, bool canMigrate})> getCategoryMigrationInfo({
    required int fromCategoryId,
    required int toCategoryId,
  }) async {
    final txCount = await getTransactionCountByCategory(fromCategoryId);

    // 检查目标分类是否存在
    final toCategory = await getCategoryById(toCategoryId);
    final canMigrate = toCategory != null;

    return (transactionCount: txCount, canMigrate: canMigrate);
  }

  @override
  Future<void> updateCategorySortOrders(
      List<({int id, int sortOrder})> updates) async {
    // 批量更新排序，需要逐个更新
    for (final update in updates) {
      await supabase.databaseService!.update(
        table: 'categories',
        id: update.id.toString(),
        data: {'sort_order': update.sortOrder},
      );
    }
  }

  @override
  Future<String> getCategoryFullName(int categoryId) async {
    final category = await getCategoryById(categoryId);
    if (category == null) return '';

    // 如果是二级分类，获取父分类名称
    if (category.parentId != null) {
      final parent = await getCategoryById(category.parentId!);
      if (parent != null) {
        return '${parent.name} / ${category.name}';
      }
    }

    return category.name;
  }

  @override
  Stream<Category?> watchCategory(int categoryId) {
    final controller = StreamController<Category?>();

    // 立即获取初始数据
    getCategoryById(categoryId).then((category) {
      if (!controller.isClosed) {
        controller.add(category);
      }
    });

    // 创建 Realtime 频道
    final channel = supabase.realtimeService!.channel('category:$categoryId');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'categories',
      callback: (payload) async {
        try {
          final category = await getCategoryById(categoryId);
          if (!controller.isClosed) {
            controller.add(category);
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
  Stream<List<Transaction>> watchTransactionsByCategory(
    int categoryId, {
    int? ledgerId,
  }) {
    final controller = StreamController<List<Transaction>>();

    // 立即获取初始数据
    getTransactionsByCategory(categoryId).then((txs) {
      if (!controller.isClosed) {
        controller.add(txs);
      }
    });

    // 创建 Realtime 频道
    final channel = supabase.realtimeService!
        .channel('transactions:category:$categoryId');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'transactions',
      callback: (payload) async {
        try {
          final txs = await getTransactionsByCategory(categoryId);
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

  @override
  Stream<List<Category>> watchCategoryWithSubs(int categoryId) {
    final controller = StreamController<List<Category>>();

    // 立即获取初始数据
    _fetchCategoryWithSubs(categoryId).then((categories) {
      if (!controller.isClosed) {
        controller.add(categories);
      }
    });

    // 创建 Realtime 频道
    final channel = supabase.realtimeService!
        .channel('categories:subs:$categoryId');

    channel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'categories',
      callback: (payload) async {
        try {
          final categories = await _fetchCategoryWithSubs(categoryId);
          if (!controller.isClosed) {
            controller.add(categories);
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

  Future<List<Category>> _fetchCategoryWithSubs(int categoryId) async {
    final category = await getCategoryById(categoryId);
    if (category == null) return [];

    final subs = await getSubCategories(categoryId);
    return [category, ...subs];
  }

  // 缓存 Stream 以避免重复订阅
  Stream<List<({Category category, int transactionCount})>>? _categoriesWithCountStream;
  StreamController<List<({Category category, int transactionCount})>>? _categoriesController;

  @override
  Stream<List<({Category category, int transactionCount})>>
      watchCategoriesWithCount() {
    // 如果已有缓存的 Stream，直接返回
    if (_categoriesWithCountStream != null) {
      return _categoriesWithCountStream!;
    }

    final controller = StreamController<List<({Category category, int transactionCount})>>.broadcast(
      onCancel: () {
        // 清理缓存
        _categoriesWithCountStream = null;
        _categoriesController = null;
      },
    );

    // 保存 controller 引用以便手动刷新
    _categoriesController = controller;

    // 立即获取初始数据
    _fetchCategoriesWithCount().then((data) {
      if (!controller.isClosed) {
        controller.add(data);
      }
    }).catchError((e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    });

    // 创建 Realtime 频道（监听分类和交易表）
    final categoryChannel = supabase.realtimeService!.channel('categories:withcount');
    final transactionChannel =
        supabase.realtimeService!.channel('transactions:withcount');

    void refresh() async {
      try {
        final data = await _fetchCategoriesWithCount();
        if (!controller.isClosed) {
          controller.add(data);
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    categoryChannel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'categories',
      callback: (payload) {
        logger.info('CloudCategoryRepository', '🔄 Categories changed, refreshing...');
        refresh();
      },
    );

    transactionChannel.onPostgresChanges(
      event: '*',
      schema: 'public',
      table: 'transactions',
      callback: (payload) {
        logger.info('CloudCategoryRepository', '🔄 Transactions changed, refreshing...');
        refresh();
      },
    );

    logger.info('CloudCategoryRepository', '📡 Subscribing to categories withcount channels');
    categoryChannel.subscribe();
    transactionChannel.subscribe();

    // 当所有监听者都取消订阅时，取消 Realtime 订阅
    controller.onCancel = () {
      logger.info('CloudCategoryRepository', '🔕 Unsubscribing from categories withcount channels');
      categoryChannel.unsubscribe();
      transactionChannel.unsubscribe();
    };

    _categoriesWithCountStream = controller.stream;
    return _categoriesWithCountStream!;
  }

  Future<List<({Category category, int transactionCount})>>
      _fetchCategoriesWithCount() async {
    // 获取所有分类（过滤掉虚拟转账分类）
    final categories = await supabase.databaseService!.query(
      table: 'categories',
      orderBy: 'sort_order',
      filters: [
        QueryFilter(column: 'kind', operator: 'neq', value: 'transfer'),
      ],
    );

    // 获取交易数量统计（直接交易数）
    final directCounts = await getAllCategoryTransactionCounts();

    // 构建分类映射
    final categoryMap = <int, Category>{};
    for (final data in categories) {
      final category = _categoryFromJson(data);
      categoryMap[category.id] = category;
    }

    // 计算包含子分类的总交易数
    final results = <({Category category, int transactionCount})>[];
    for (final data in categories) {
      final category = _categoryFromJson(data);
      var totalCount = directCounts[category.id] ?? 0;

      // 如果是父分类（level=1），累加所有子分类的交易数
      if (category.level == 1) {
        for (final child in categoryMap.values) {
          if (child.parentId == category.id && child.level == 2) {
            totalCount += directCounts[child.id] ?? 0;
          }
        }
      }

      results.add((category: category, transactionCount: totalCount));
    }

    return results;
  }

  // ============================================
  // 辅助方法：数据转换
  // ============================================

  Category _categoryFromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      name: json['name'] as String,
      kind: json['kind'] as String,
      icon: json['icon'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      parentId: json['parent_id'] as int?,
      level: json['level'] as int? ?? 1,
      iconType: json['icon_type'] as String? ?? 'material',
      customIconPath: json['custom_icon_path'] as String?,
      communityIconId: json['community_icon_id'] as String?,
    );
  }

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

  @override
  Future<List<Category>> getAllCategories() async {
    throw UnimplementedError('getAllCategories 在云端模式下暂不可用');
  }

  @override
  Future<void> batchInsertCategories(List<CategoriesCompanion> categories) async {
    throw UnimplementedError('云端批量插入分类暂不支持');
  }

  @override
  Future<int> insertCategory(CategoriesCompanion category) async {
    throw UnimplementedError('云端插入分类暂不支持');
  }

  @override
  Future<void> updateCategoryIcon(
    int id, {
    required String iconType,
    String? icon,
    String? customIconPath,
    String? communityIconId,
  }) async {
    throw UnimplementedError('云端更新分类图标暂不支持');
  }

  @override
  Future<void> clearCategoryCustomIcon(int id, {String? materialIcon}) async {
    throw UnimplementedError('云端清除自定义图标暂不支持');
  }

  @override
  Future<List<String>> getCustomIconPaths() async {
    throw UnimplementedError('云端获取自定义图标路径暂不支持');
  }

  @override
  Future<Category> getTransferCategory() async {
    // 查找现有的转账分类
    final categories = await supabase.databaseService!.query(
      table: 'categories',
      filters: [
        QueryFilter(column: 'kind', operator: 'eq', value: 'transfer'),
      ],
    );

    if (categories.isNotEmpty) {
      return _categoryFromJson(categories.first);
    }

    // 不存在则创建（理论上seed时已创建，这里是兜底逻辑）
    logger.warning('CloudCategoryRepository', '转账分类不存在，正在创建...');
    final result = await supabase.databaseService!.insert(
      table: 'categories',
      data: {
        'name': '转账',
        'kind': 'transfer',
        'icon': 'swap_horiz',
        'sort_order': -1,
        'level': 1,
      },
    );

    return _categoryFromJson(result);
  }
}
