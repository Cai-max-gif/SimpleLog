import 'package:drift/drift.dart' as d;

import '../../db.dart';
import '../statistics_repository.dart';

/// 本地统计Repository实现
/// 基于 Drift 数据库实现
class LocalStatisticsRepository implements StatisticsRepository {
  final BeeDatabase db;

  LocalStatisticsRepository(this.db);

  @override
  Future<List<({int? id, String name, String? icon, double total})>> totalsByCategory({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBiggerOrEqualValue(start) & t.happenedAt.isSmallerThanValue(end)))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    final rows = await q.get();
    final map = <int?, double>{};
    final names = <int?, String>{};
    final icons = <int?, String?>{};
    for (final r in rows) {
      final t = r.readTable(db.transactions);
      final c = r.readTableOrNull(db.categories);
      final id = c?.id;
      final name = c?.name ?? '未分类';
      final icon = c?.icon;
      names[id] = name;
      icons[id] = icon;
      map.update(id, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final list = map.entries
        .map((e) => (id: e.key, name: names[e.key] ?? '未分类', icon: icons[e.key], total: e.value))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  @override
  Future<List<({int? id, String name, String? icon, int? parentId, int level, double total})>>
      totalsByCategoryWithHierarchy({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBiggerOrEqualValue(start) & t.happenedAt.isSmallerThanValue(end)))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);

    final rows = await q.get();
    final map = <int?, double>{};
    final categoryInfo = <int?, ({String name, String? icon, int? parentId, int level})>{};

    for (final r in rows) {
      final t = r.readTable(db.transactions);
      final c = r.readTableOrNull(db.categories);
      final id = c?.id;

      if (c != null) {
        categoryInfo[id] = (
          name: c.name,
          icon: c.icon,
          parentId: c.parentId,
          level: c.level,
        );
      } else {
        categoryInfo[id] = (
          name: '未分类',
          icon: null,
          parentId: null,
          level: 1,
        );
      }

      map.update(id, (v) => v + t.amount, ifAbsent: () => t.amount);
    }

    final list = map.entries.map((e) {
      final info = categoryInfo[e.key]!;
      return (
        id: e.key,
        name: info.name,
        icon: info.icon,
        parentId: info.parentId,
        level: info.level,
        total: e.value,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return list;
  }

  @override
  Future<List<({DateTime day, double total})>> totalsByDay({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBiggerOrEqualValue(start) & t.happenedAt.isSmallerThanValue(end)))
        .get();
    final map = <DateTime, double>{};
    for (final t in rows) {
      final dt = t.happenedAt.toLocal();
      final day = DateTime(dt.year, dt.month, dt.day);
      map.update(day, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    // ensure full range continuity
    final result = <({DateTime day, double total})>[];
    for (DateTime d = DateTime(start.year, start.month, start.day);
        d.isBefore(end);
        d = d.add(const Duration(days: 1))) {
      result.add((day: d, total: map[d] ?? 0));
    }
    return result;
  }

  @override
  Future<List<({DateTime month, double total})>> totalsByMonth({
    required int ledgerId,
    required String type,
    required int year,
  }) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBiggerOrEqualValue(start) & t.happenedAt.isSmallerThanValue(end)))
        .get();
    final map = <int, double>{};
    for (final t in rows) {
      final dt = t.happenedAt.toLocal();
      map.update(dt.month, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final result = <({DateTime month, double total})>[];
    for (int m = 1; m <= 12; m++) {
      result.add((month: DateTime(year, m, 1), total: map[m] ?? 0));
    }
    return result;
  }

  @override
  Future<List<({int year, double total})>> totalsByYearSeries({
    required int ledgerId,
    required String type,
  }) async {
    final rows = await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId) & t.type.equals(type)))
        .get();
    if (rows.isEmpty) return const [];
    final map = <int, double>{};
    int minYear = 9999, maxYear = 0;
    for (final t in rows) {
      final y = t.happenedAt.toLocal().year;
      if (y < minYear) minYear = y;
      if (y > maxYear) maxYear = y;
      map.update(y, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final out = <({int year, double total})>[];
    for (int y = minYear; y <= maxYear; y++) {
      out.add((year: y, total: map[y] ?? 0));
    }
    return out;
  }

  @override
  Future<(double income, double expense)> totalsInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    // 使用 SQL 聚合查询，比查出全部数据再累加快得多
    final result = await db.customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE ledger_id = ?1 AND happened_at >= ?2 AND happened_at < ?3
      ''',
      variables: [
        d.Variable<int>(ledgerId),
        d.Variable<DateTime>(start),
        d.Variable<DateTime>(end),
      ],
      readsFrom: {db.transactions},
    ).getSingle();

    final income = (result.data['income'] as num?)?.toDouble() ?? 0.0;
    final expense = (result.data['expense'] as num?)?.toDouble() ?? 0.0;
    return (income, expense);
  }

  @override
  Future<(double income, double expense)> monthlyTotals({
    required int ledgerId,
    required DateTime month,
  }) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    // 使用 SQL 聚合查询，比查出全部数据再累加快得多
    final result = await db.customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE ledger_id = ?1 AND happened_at >= ?2 AND happened_at < ?3
      ''',
      variables: [
        d.Variable<int>(ledgerId),
        d.Variable<DateTime>(start),
        d.Variable<DateTime>(end),
      ],
      readsFrom: {db.transactions},
    ).getSingle();

    final income = (result.data['income'] as num?)?.toDouble() ?? 0.0;
    final expense = (result.data['expense'] as num?)?.toDouble() ?? 0.0;
    return (income, expense);
  }

  @override
  Future<(double income, double expense)> yearlyTotals({
    required int ledgerId,
    required int year,
  }) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);

    // 使用 SQL 聚合查询，比查出全部数据再累加快得多
    final result = await db.customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE ledger_id = ?1 AND happened_at >= ?2 AND happened_at < ?3
      ''',
      variables: [
        d.Variable<int>(ledgerId),
        d.Variable<DateTime>(start),
        d.Variable<DateTime>(end),
      ],
      readsFrom: {db.transactions},
    ).getSingle();

    final income = (result.data['income'] as num?)?.toDouble() ?? 0.0;
    final expense = (result.data['expense'] as num?)?.toDouble() ?? 0.0;
    return (income, expense);
  }
}
