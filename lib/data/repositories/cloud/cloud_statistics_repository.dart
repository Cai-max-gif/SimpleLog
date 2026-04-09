import 'package:flutter_cloud_sync_supabase/flutter_cloud_sync_supabase.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

import '../statistics_repository.dart';

/// 云端统计Repository实现
/// 基于 Supabase 实现
class CloudStatisticsRepository implements StatisticsRepository {
  final SupabaseProvider supabase;

  CloudStatisticsRepository(this.supabase);

  @override
  Future<List<({int? id, String name, String? icon, double total})>>
      totalsByCategory({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    // 获取时间范围内的交易
    final transactions = await supabase.databaseService!.query(
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

    // 按分类分组统计
    final categoryTotals = <int, double>{};
    for (final tx in transactions) {
      final categoryId = tx['category_id'] as int?;
      if (categoryId != null) {
        final amount = (tx['amount'] as num).toDouble();
        categoryTotals[categoryId] = (categoryTotals[categoryId] ?? 0.0) + amount;
      }
    }

    // 获取分类信息
    final categories = await supabase.databaseService!.query(
      table: 'categories',
    );

    final categoryMap = <int, Map<String, dynamic>>{};
    for (final cat in categories) {
      categoryMap[cat['id'] as int] = cat;
    }

    // 组合结果
    final results = <({int? id, String name, String? icon, double total})>[];
    for (final entry in categoryTotals.entries) {
      final category = categoryMap[entry.key];
      if (category != null) {
        results.add((
          id: entry.key,
          name: category['name'] as String,
          icon: category['icon'] as String?,
          total: entry.value,
        ));
      }
    }

    // 按金额降序排序
    results.sort((a, b) => b.total.compareTo(a.total));

    return results;
  }

  @override
  Future<
      List<
          ({
            int? id,
            String name,
            String? icon,
            int? parentId,
            int level,
            double total
          })>> totalsByCategoryWithHierarchy({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    // 查询时间范围内的交易
    final transactions = await supabase.databaseService!.query(
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

    if (transactions.isEmpty) {
      return [];
    }

    // 提取所有分类ID（包括null）
    final categoryIds = transactions
        .map((t) => t['category_id'] as int?)
        .where((id) => id != null)
        .toSet();

    // 查询所有相关分类
    Map<int, Map<String, dynamic>> categoryMap = {};
    if (categoryIds.isNotEmpty) {
      final categories = await supabase.databaseService!.query(
        table: 'categories',
      );

      for (final cat in categories) {
        final catId = cat['id'] as int;
        if (categoryIds.contains(catId)) {
          categoryMap[catId] = cat;
        }
      }
    }

    // 统计每个分类的总额
    final categoryTotals = <int?, double>{};
    final categoryInfo = <int?, ({String name, String? icon, int? parentId, int level})>{};

    for (final transaction in transactions) {
      final categoryId = transaction['category_id'] as int?;
      final amount = (transaction['amount'] as num).toDouble();

      if (categoryId != null && categoryMap.containsKey(categoryId)) {
        final category = categoryMap[categoryId]!;
        categoryInfo[categoryId] = (
          name: category['name'] as String,
          icon: category['icon'] as String?,
          parentId: category['parent_id'] as int?,
          level: category['level'] as int,
        );
      } else if (!categoryInfo.containsKey(categoryId)) {
        // 未分类
        categoryInfo[categoryId] = (
          name: '未分类',
          icon: null,
          parentId: null,
          level: 1,
        );
      }

      categoryTotals.update(
        categoryId,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
    }

    // 组合结果
    final results = categoryTotals.entries.map((entry) {
      final info = categoryInfo[entry.key]!;
      return (
        id: entry.key,
        name: info.name,
        icon: info.icon,
        parentId: info.parentId,
        level: info.level,
        total: entry.value,
      );
    }).toList();

    // 按金额降序排序
    results.sort((a, b) => b.total.compareTo(a.total));

    return results;
  }

  @override
  Future<List<({DateTime day, double total})>> totalsByDay({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    // 获取时间范围内的交易
    final transactions = await supabase.databaseService!.query(
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
      orderBy: 'happened_at',
    );

    // 按天分组统计
    final dayTotals = <String, double>{};
    for (final tx in transactions) {
      final happenedAt = DateTime.parse(tx['happened_at'] as String);
      final dayKey =
          '${happenedAt.year}-${happenedAt.month.toString().padLeft(2, '0')}-${happenedAt.day.toString().padLeft(2, '0')}';
      final amount = (tx['amount'] as num).toDouble();
      dayTotals[dayKey] = (dayTotals[dayKey] ?? 0.0) + amount;
    }

    // 转换为结果列表
    final results = <({DateTime day, double total})>[];
    for (final entry in dayTotals.entries) {
      final parts = entry.key.split('-');
      final day = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      results.add((day: day, total: entry.value));
    }

    // 按日期排序
    results.sort((a, b) => a.day.compareTo(b.day));

    return results;
  }

  @override
  Future<List<({DateTime month, double total})>> totalsByMonth({
    required int ledgerId,
    required String type,
    required int year,
  }) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);

    // 获取该年的所有交易
    final transactions = await supabase.databaseService!.query(
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
      orderBy: 'happened_at',
    );

    // 按月分组统计
    final monthTotals = <int, double>{};
    for (final tx in transactions) {
      final happenedAt = DateTime.parse(tx['happened_at'] as String);
      final month = happenedAt.month;
      final amount = (tx['amount'] as num).toDouble();
      monthTotals[month] = (monthTotals[month] ?? 0.0) + amount;
    }

    // 转换为结果列表（包含所有12个月）
    final results = <({DateTime month, double total})>[];
    for (int month = 1; month <= 12; month++) {
      results.add((
        month: DateTime(year, month, 1),
        total: monthTotals[month] ?? 0.0,
      ));
    }

    return results;
  }

  @override
  Future<List<({int year, double total})>> totalsByYearSeries({
    required int ledgerId,
    required String type,
  }) async {
    // 获取所有交易
    final transactions = await supabase.databaseService!.query(
      table: 'transactions',
      filters: [
        QueryFilter(column: 'ledger_id', operator: 'eq', value: ledgerId),
        QueryFilter(column: 'type', operator: 'eq', value: type),
      ],
      orderBy: 'happened_at',
    );

    // 按年分组统计
    final yearTotals = <int, double>{};
    for (final tx in transactions) {
      final happenedAt = DateTime.parse(tx['happened_at'] as String);
      final year = happenedAt.year;
      final amount = (tx['amount'] as num).toDouble();
      yearTotals[year] = (yearTotals[year] ?? 0.0) + amount;
    }

    // 转换为结果列表
    final results = <({int year, double total})>[];
    for (final entry in yearTotals.entries) {
      results.add((year: entry.key, total: entry.value));
    }

    // 按年份排序
    results.sort((a, b) => a.year.compareTo(b.year));

    return results;
  }

  @override
  Future<(double income, double expense)> totalsInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    // 获取时间范围内的所有交易
    final transactions = await supabase.databaseService!.query(
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
    );

    double income = 0.0;
    double expense = 0.0;

    for (final tx in transactions) {
      final type = tx['type'] as String;
      final amount = (tx['amount'] as num).toDouble();

      if (type == 'income') {
        income += amount;
      } else if (type == 'expense') {
        expense += amount;
      }
    }

    return (income, expense);
  }

  @override
  Future<(double income, double expense)> monthlyTotals({
    required int ledgerId,
    required DateTime month,
  }) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    return totalsInRange(ledgerId: ledgerId, start: start, end: end);
  }

  @override
  Future<(double income, double expense)> yearlyTotals({
    required int ledgerId,
    required int year,
  }) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);

    return totalsInRange(ledgerId: ledgerId, start: start, end: end);
  }
}
