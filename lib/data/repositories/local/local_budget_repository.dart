import 'package:drift/drift.dart' as d;

import '../../db.dart';
import '../budget_repository.dart';

/// 本地预算Repository实现
/// 基于 Drift 数据库实现
class LocalBudgetRepository implements BudgetRepository {
  final BeeDatabase db;

  LocalBudgetRepository(this.db);

  // ============================================
  // 基础 CRUD 操作
  // ============================================

  @override
  Future<int> createBudget({
    required int ledgerId,
    required String type,
    int? categoryId,
    required double amount,
    String period = 'monthly',
    int startDay = 1,
  }) async {
    return await db.into(db.budgets).insert(
      BudgetsCompanion.insert(
        ledgerId: ledgerId,
        type: d.Value(type),
        categoryId: d.Value(categoryId),
        amount: amount,
        period: d.Value(period),
        startDay: d.Value(startDay),
      ),
    );
  }

  @override
  Future<void> updateBudget(
    int id, {
    double? amount,
    int? startDay,
    bool? enabled,
  }) async {
    await (db.update(db.budgets)..where((b) => b.id.equals(id))).write(
      BudgetsCompanion(
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        startDay: startDay != null ? d.Value(startDay) : const d.Value.absent(),
        enabled: enabled != null ? d.Value(enabled) : const d.Value.absent(),
        updatedAt: d.Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteBudget(int id) async {
    // 先获取预算信息，判断是否为总预算
    final budget = await (db.select(db.budgets)
          ..where((b) => b.id.equals(id)))
        .getSingleOrNull();

    if (budget == null) return;

    if (budget.type == 'total') {
      // 删除总预算时，同时删除该账本的所有分类预算
      await (db.delete(db.budgets)
            ..where((b) => b.ledgerId.equals(budget.ledgerId)))
          .go();
    } else {
      // 删除单个分类预算
      await (db.delete(db.budgets)..where((b) => b.id.equals(id))).go();
    }
  }

  @override
  Future<Budget?> getTotalBudget(int ledgerId) async {
    // 使用 .get() 然后取第一个，避免多条脏数据时报错
    final budgets = await (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId) & b.type.equals('total') & b.enabled.equals(true))
          ..orderBy([(b) => d.OrderingTerm(expression: b.createdAt)]))
        .get();
    return budgets.firstOrNull;
  }

  @override
  Future<List<Budget>> getCategoryBudgets(int ledgerId) async {
    return await (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId) & b.type.equals('category') & b.enabled.equals(true)))
        .get();
  }

  @override
  Future<Budget?> getBudgetByCategory(int ledgerId, int categoryId) async {
    return await (db.select(db.budgets)
          ..where((b) =>
              b.ledgerId.equals(ledgerId) &
              b.type.equals('category') &
              b.categoryId.equals(categoryId) &
              b.enabled.equals(true)))
        .getSingleOrNull();
  }

  @override
  Future<List<Budget>> getAllBudgets(int ledgerId) async {
    return await (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId))
          ..orderBy([
            (b) => d.OrderingTerm(expression: b.type),
            (b) => d.OrderingTerm(expression: b.createdAt),
          ]))
        .get();
  }

  @override
  Future<List<Budget>> getAllBudgetsForExport() async {
    return await (db.select(db.budgets)
          ..orderBy([
            (b) => d.OrderingTerm(expression: b.ledgerId),
            (b) => d.OrderingTerm(expression: b.type),
            (b) => d.OrderingTerm(expression: b.createdAt),
          ]))
        .get();
  }

  // ============================================
  // 预算统计
  // ============================================

  @override
  Future<BudgetUsage> getBudgetUsage(int budgetId, DateTime month) async {
    final budget = await (db.select(db.budgets)
          ..where((b) => b.id.equals(budgetId)))
        .getSingleOrNull();

    if (budget == null) {
      return BudgetUsage(used: 0, budget: 0);
    }

    // 计算月份范围（基于startDay）
    DateTime startDate;
    DateTime endDate;

    if (budget.startDay <= month.day) {
      // 起始日在当前日期之前，周期是本月startDay到下月startDay
      startDate = DateTime(month.year, month.month, budget.startDay);
      endDate = DateTime(month.year, month.month + 1, budget.startDay);
    } else {
      // 起始日在当前日期之后，周期是上月startDay到本月startDay
      startDate = DateTime(month.year, month.month - 1, budget.startDay);
      endDate = DateTime(month.year, month.month, budget.startDay);
    }

    // 查询该周期内的支出
    double used = 0;
    if (budget.type == 'total') {
      // 总预算：统计所有支出
      final result = await db.customSelect(
        '''
        SELECT COALESCE(SUM(amount), 0) as total
        FROM transactions
        WHERE ledger_id = ?
          AND type = 'expense'
          AND happened_at >= ?
          AND happened_at < ?
        ''',
        variables: [
          d.Variable.withInt(budget.ledgerId),
          d.Variable.withDateTime(startDate),
          d.Variable.withDateTime(endDate),
        ],
        readsFrom: {db.transactions},
      ).getSingle();
      used = _parseDouble(result.data['total']);
    } else {
      // 分类预算：统计该分类支出（包含子分类）
      final result = await db.customSelect(
        '''
        SELECT COALESCE(SUM(t.amount), 0) as total
        FROM transactions t
        LEFT JOIN categories c ON t.category_id = c.id
        WHERE t.ledger_id = ?
          AND t.type = 'expense'
          AND t.happened_at >= ?
          AND t.happened_at < ?
          AND (t.category_id = ? OR c.parent_id = ?)
        ''',
        variables: [
          d.Variable.withInt(budget.ledgerId),
          d.Variable.withDateTime(startDate),
          d.Variable.withDateTime(endDate),
          d.Variable.withInt(budget.categoryId!),
          d.Variable.withInt(budget.categoryId!),
        ],
        readsFrom: {db.transactions, db.categories},
      ).getSingle();
      used = _parseDouble(result.data['total']);
    }

    return BudgetUsage(used: used, budget: budget.amount);
  }

  @override
  Future<BudgetOverview> getBudgetOverview(int ledgerId, DateTime month) async {
    // 获取总预算
    final totalBudget = await getTotalBudget(ledgerId);
    BudgetUsage? totalUsage;

    if (totalBudget != null) {
      totalUsage = await getBudgetUsage(totalBudget.id, month);
    }

    // 获取分类预算使用情况
    final categoryUsages = await getCategoryBudgetUsages(ledgerId, month);

    // 计算剩余天数
    final now = DateTime.now();
    final startDay = totalBudget?.startDay ?? 1;
    DateTime endDate;
    if (startDay <= now.day) {
      endDate = DateTime(now.year, now.month + 1, startDay);
    } else {
      endDate = DateTime(now.year, now.month, startDay);
    }
    final daysRemaining = endDate.difference(now).inDays;

    // 计算日均可用
    final remaining = totalUsage?.remaining ?? 0;
    final dailyAvailable = daysRemaining > 0 ? remaining / daysRemaining : 0.0;

    return BudgetOverview(
      totalBudget: totalUsage,
      categoryBudgets: categoryUsages,
      daysRemaining: daysRemaining > 0 ? daysRemaining : 0,
      dailyAvailable: dailyAvailable > 0 ? dailyAvailable : 0,
    );
  }

  @override
  Future<List<CategoryBudgetUsage>> getCategoryBudgetUsages(
    int ledgerId,
    DateTime month,
  ) async {
    final budgets = await getCategoryBudgets(ledgerId);
    final result = <CategoryBudgetUsage>[];

    for (final budget in budgets) {
      if (budget.categoryId == null) continue;

      // 获取分类信息
      final category = await (db.select(db.categories)
            ..where((c) => c.id.equals(budget.categoryId!)))
          .getSingleOrNull();

      if (category == null) continue;

      // 获取使用情况
      final usage = await getBudgetUsage(budget.id, month);

      result.add(CategoryBudgetUsage(
        budgetId: budget.id,
        categoryId: category.id,
        categoryName: category.name,
        categoryIcon: category.icon,
        usage: usage,
      ));
    }

    // 按使用率降序排列
    result.sort((a, b) => b.usage.rate.compareTo(a.usage.rate));

    return result;
  }

  // ============================================
  // 监听
  // ============================================

  @override
  Stream<List<Budget>> watchBudgets(int ledgerId) {
    return (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId))
          ..orderBy([
            (b) => d.OrderingTerm(expression: b.type),
            (b) => d.OrderingTerm(expression: b.createdAt),
          ]))
        .watch();
  }

  // ============================================
  // 辅助方法
  // ============================================

  double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return 0.0;
  }
}
