import 'dart:io';

import 'package:drift/drift.dart' as d;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../db.dart';
import '../transaction_repository.dart';
import '../../../services/system/logger_service.dart';

/// 本地交易Repository实现
/// 基于 Drift 数据库实现
class LocalTransactionRepository implements TransactionRepository {
  final BeeDatabase db;

  LocalTransactionRepository(this.db);

  @override
  Stream<List<Transaction>> watchRecentTransactions({
    required int ledgerId,
    int limit = 20,
  }) {
    return (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ])
          ..limit(limit))
        .watch();
  }

  @override
  Stream<List<Transaction>> watchTransactionsInMonth({
    required int ledgerId,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .watch();
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryAll({
    int? ledgerId,
  }) {
    final select = db.select(db.transactions);
    if (ledgerId != null) {
      select.where((t) => t.ledgerId.equals(ledgerId));
    }
    select.orderBy([
      (t) => d.OrderingTerm(
          expression: t.happenedAt, mode: d.OrderingMode.desc)
    ]);
    final q = select.join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList());
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryInMonth({
    required int ledgerId,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList());
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryInYear({
    required int ledgerId,
    required int year,
  }) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList());
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
    final base = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    if (categoryId == null) {
      base.where(db.transactions.categoryId.isNull());
    } else {
      base.where(db.transactions.categoryId.equals(categoryId));
    }
    return base.watch().map((rows) => rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList());
  }

  static const _uuid = Uuid();

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
    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          ledgerId: ledgerId,
          type: type,
          amount: amount,
          categoryId: d.Value(categoryId),
          accountId: d.Value(accountId),
          toAccountId: d.Value(toAccountId),
          happenedAt: d.Value(happenedAt),
          note: d.Value(note),
          syncId: d.Value(syncId ?? _uuid.v4()),
        ));
  }

  @override
  Future<int> insertTransactionsBatch(List<TransactionsCompanion> items) async {
    if (items.isEmpty) return 0;
    // 自动补上 syncId
    final effectiveItems = items.map((item) {
      if (item.syncId == const d.Value.absent() || item.syncId.value == null) {
        return item.copyWith(syncId: d.Value(_uuid.v4()));
      }
      return item;
    }).toList();
    return db.transaction(() async {
      await db.batch((b) => b.insertAll(db.transactions, effectiveItems));
      return effectiveItems.length;
    });
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
    // 处理 accountId 参数
    final d.Value<int?> accountIdValue;
    if (accountId == null) {
      accountIdValue = const d.Value.absent();
    } else if (accountId is d.Value<int?>) {
      accountIdValue = accountId;
    } else {
      accountIdValue = d.Value(accountId as int?);
    }

    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        type: d.Value(type),
        amount: d.Value(amount),
        categoryId: d.Value(categoryId),
        note: d.Value(note),
        happenedAt:
            happenedAt != null ? d.Value(happenedAt) : const d.Value.absent(),
        accountId: accountIdValue,
      ),
    );
  }

  @override
  Future<void> deleteTransaction(int id) async {
    // 先删除关联的标签
    await (db.delete(db.transactionTags)
          ..where((tt) => tt.transactionId.equals(id)))
        .go();

    // 再删除关联的附件
    await _deleteAttachmentsForTransaction(id);

    // 最后删除交易记录
    await (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
  }

  /// 删除交易关联的所有附件（包括文件和数据库记录）
  Future<void> _deleteAttachmentsForTransaction(int transactionId) async {
    try {
      // 获取该交易的所有附件
      final attachments = await (db.select(db.transactionAttachments)
            ..where((a) => a.transactionId.equals(transactionId)))
          .get();

      if (attachments.isEmpty) return;

      // 获取附件存储目录
      final appDir = await getApplicationDocumentsDirectory();
      final attachmentDir = Directory('${appDir.path}/attachments');
      final cacheDir = await getTemporaryDirectory();
      final thumbDir = Directory('${cacheDir.path}/attachment_thumbs');

      // 删除每个附件的文件
      for (final attachment in attachments) {
        // 删除原图
        final file = File('${attachmentDir.path}/${attachment.fileName}');
        if (await file.exists()) {
          await file.delete();
          logger.debug('LocalTransactionRepository', '删除附件文件: ${attachment.fileName}');
        }

        // 删除缩略图
        final thumbName = '${path.basenameWithoutExtension(attachment.fileName)}_thumb.jpg';
        final thumbFile = File('${thumbDir.path}/$thumbName');
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }

      // 删除数据库记录
      await (db.delete(db.transactionAttachments)
            ..where((a) => a.transactionId.equals(transactionId)))
          .go();

      logger.info('LocalTransactionRepository', '已删除交易 $transactionId 的 ${attachments.length} 个附件');
    } catch (e, stackTrace) {
      logger.error('LocalTransactionRepository', '删除交易附件失败', e, stackTrace);
      // 不抛出异常，继续删除交易
    }
  }

  @override
  Future<Transaction?> getTransactionById(int id) async {
    return await (db.select(db.transactions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  @override
  Future<int> insertTransactionCompanion(TransactionsCompanion item) async {
    // 自动补上 syncId（如果未提供）
    final effective = item.syncId == const d.Value.absent() || item.syncId.value == null
        ? item.copyWith(syncId: d.Value(_uuid.v4()))
        : item;
    return await db.into(db.transactions).insert(effective);
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      transactionsWithCategoryAll({
    int? ledgerId,
  }) =>
          watchTransactionsWithCategoryAll(ledgerId: ledgerId);

  @override
  Future<List<({Transaction t, Category? category})>>
      getRecentTransactionsWithCategory({
    required int ledgerId,
    required int limit,
  }) async {
    final q = (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ])
          ..limit(limit))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    final rows = await q.get();
    return rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList();
  }

  @override
  Future<int> countByTypeInRange({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS c FROM transactions WHERE ledger_id = ?1 AND type = ?2 AND happened_at >= ?3 AND happened_at < ?4',
      variables: [
        d.Variable<int>(ledgerId),
        d.Variable<String>(type),
        d.Variable<DateTime>(start),
        d.Variable<DateTime>(end),
      ],
      readsFrom: {db.transactions},
    ).getSingle();
    final v = row.data['c'];
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return 0;
  }

  @override
  Future<List<Transaction>> getTransactionsByLedger(int ledgerId) async {
    return await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) =>
                d.OrderingTerm(expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .get();
  }

  @override
  Future<List<Transaction>> getTransactionsByLedgerInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    return await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBiggerOrEqualValue(start) &
              t.happenedAt.isSmallerThanValue(end))
          ..orderBy([
            (t) =>
                d.OrderingTerm(expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .get();
  }

  @override
  Future<void> updateTransactionFields({
    required int id,
    int? accountId,
    int? toAccountId,
  }) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId:
            accountId != null ? d.Value(accountId) : const d.Value.absent(),
        toAccountId:
            toAccountId != null ? d.Value(toAccountId) : const d.Value.absent(),
      ),
    );
  }

  @override
  Future<Transaction?> getFirstTransactionByLedger(int ledgerId) async {
    return await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) =>
                d.OrderingTerm(expression: t.happenedAt, mode: d.OrderingMode.asc)
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<Transaction?> getLastTransactionByLedger(int ledgerId) async {
    return await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) =>
                d.OrderingTerm(expression: t.happenedAt, mode: d.OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<void> updateTransactionLedger({
    required int id,
    required int ledgerId,
  }) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(ledgerId: d.Value(ledgerId)),
    );
  }

  // ==================== 日历功能相关 ====================

  @override
  Future<Map<String, (double, double)>> getDailyTotalsByMonth({
    required int ledgerId,
    required DateTime month,
  }) async {
    final startDate = DateTime(month.year, month.month, 1);
    final endDate = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    print('🔍 Repository查询: ledgerId=$ledgerId, 日期范围: $startDate ~ $endDate');

    // 先查询该月份有多少条交易
    final countQuery = '''
      SELECT COUNT(*) as count
      FROM transactions
      WHERE ledger_id = ?
        AND happened_at >= ?
        AND happened_at <= ?
    ''';

    final countResult = await db.customSelect(
      countQuery,
      variables: [
        d.Variable.withInt(ledgerId),
        d.Variable.withDateTime(startDate),
        d.Variable.withDateTime(endDate),
      ],
    ).getSingle();

    final totalCount = countResult.read<int>('count');
    print('🔍 该月份总交易数: $totalCount');

    // 查看一条交易的 happened_at 值
    if (totalCount > 0) {
      final sampleQuery = 'SELECT happened_at FROM transactions WHERE ledger_id = ? LIMIT 1';
      final sample = await db.customSelect(
        sampleQuery,
        variables: [d.Variable.withInt(ledgerId)],
      ).getSingle();
      final happenedAtValue = sample.read<int>('happened_at');
      print('🔍 样例 happened_at 值(int): $happenedAtValue');

      // 尝试转换为 DateTime 看看
      final asDateTime = DateTime.fromMillisecondsSinceEpoch(happenedAtValue * 1000);
      print('🔍 转换为 DateTime (假设是秒): $asDateTime');
    }

    // SQL 聚合查询
    // Drift 存储 DateTime 为 Unix timestamp（秒），直接使用 strftime
    final query = '''
      SELECT
        strftime('%Y-%m-%d', happened_at, 'unixepoch', 'localtime') as date,
        SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as income,
        SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as expense
      FROM transactions
      WHERE ledger_id = ?
        AND happened_at >= ?
        AND happened_at <= ?
      GROUP BY date
      ORDER BY date DESC
    ''';

    final results = await db.customSelect(
      query,
      variables: [
        d.Variable.withInt(ledgerId),
        d.Variable.withDateTime(startDate),
        d.Variable.withDateTime(endDate),
      ],
    ).get();

    print('🔍 SQL聚合查询结果: ${results.length} 条');

    final map = <String, (double, double)>{};
    for (final row in results) {
      final date = row.read<String?>('date');
      if (date == null) continue; // 跳过null日期
      final income = row.read<double>('income') ?? 0.0;
      final expense = row.read<double>('expense') ?? 0.0;
      map[date] = (income, expense);
      print('  $date: 收入=$income, 支出=$expense');
    }

    print('🔍 最终返回 Map: ${map.length} 条');
    return map;
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
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    // 查询当天的所有交易
    final transactions = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(startOfDay, endOfDay))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .get();

    if (transactions.isEmpty) {
      return [];
    }

    final txIds = transactions.map((t) => t.id).toList();

    // 批量查询分类
    final categoriesMap = <int, Category>{};
    for (final tx in transactions) {
      if (tx.categoryId != null) {
        final category = await (db.select(db.categories)
              ..where((c) => c.id.equals(tx.categoryId!)))
            .getSingleOrNull();
        if (category != null) {
          categoriesMap[tx.categoryId!] = category;
        }
      }
    }

    // 批量查询标签
    final tagsMap = <int, List<Tag>>{};
    final tagRelations = await (db.select(db.transactionTags)
          ..where((tt) => tt.transactionId.isIn(txIds)))
        .get();

    final tagIds = tagRelations.map((r) => r.tagId).toSet();
    if (tagIds.isNotEmpty) {
      final tags = await (db.select(db.tags)
            ..where((t) => t.id.isIn(tagIds.toList())))
          .get();
      final tagsById = {for (var tag in tags) tag.id: tag};

      for (final rel in tagRelations) {
        final tag = tagsById[rel.tagId];
        if (tag != null) {
          tagsMap.putIfAbsent(rel.transactionId, () => []).add(tag);
        }
      }
    }

    // 批量查询附件
    final attachmentsMap = <int, List<TransactionAttachment>>{};
    final attachments = await (db.select(db.transactionAttachments)
          ..where((a) => a.transactionId.isIn(txIds)))
        .get();
    for (final attachment in attachments) {
      attachmentsMap
          .putIfAbsent(attachment.transactionId, () => [])
          .add(attachment);
    }

    // 批量查询账户
    final accountIds = transactions
        .where((t) => t.accountId != null)
        .map((t) => t.accountId!)
        .toSet();
    final accountsMap = <int, Account>{};
    if (accountIds.isNotEmpty) {
      final accounts = await (db.select(db.accounts)
            ..where((a) => a.id.isIn(accountIds.toList())))
          .get();
      for (final account in accounts) {
        accountsMap[account.id] = account;
      }
    }

    // 组装结果
    return transactions.map((tx) {
      return (
        t: tx,
        category: tx.categoryId != null ? categoriesMap[tx.categoryId] : null,
        tags: tagsMap[tx.id] ?? [],
        attachments: attachmentsMap[tx.id] ?? [],
        account: tx.accountId != null ? accountsMap[tx.accountId] : null,
      );
    }).toList();
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
    // 查询时间范围内的所有交易
    final transactions = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(startDate, endDate))
          ..orderBy([
            (t) => d.OrderingTerm(
                  expression: t.happenedAt,
                  mode: d.OrderingMode.desc,
                ),
          ]))
        .get();

    // 批量获取所有相关的 category, tags, attachments, account
    final result = <({
      Transaction t,
      Category? category,
      List<Tag> tags,
      List<TransactionAttachment> attachments,
      Account? account,
    })>[];

    for (final transaction in transactions) {
      // 获取分类
      Category? category;
      if (transaction.categoryId != null) {
        category = await (db.select(db.categories)
              ..where((c) => c.id.equals(transaction.categoryId!)))
            .getSingleOrNull();
      }

      // 获取标签
      final tagRelations = await (db.select(db.transactionTags)
            ..where((tt) => tt.transactionId.equals(transaction.id)))
          .get();

      final tags = <Tag>[];
      for (final rel in tagRelations) {
        final tag = await (db.select(db.tags)
              ..where((t) => t.id.equals(rel.tagId)))
            .getSingleOrNull();
        if (tag != null) tags.add(tag);
      }

      // 获取附件
      final attachments = await (db.select(db.transactionAttachments)
            ..where((a) => a.transactionId.equals(transaction.id)))
          .get();

      // 获取账户
      Account? account;
      if (transaction.accountId != null) {
        account = await (db.select(db.accounts)
              ..where((a) => a.id.equals(transaction.accountId!)))
            .getSingleOrNull();
      }

      result.add((
        t: transaction,
        category: category,
        tags: tags,
        attachments: attachments,
        account: account,
      ));
    }

    return result;
  }

  @override
  Future<List<String>> getTransactionDatesByMonth({
    required int ledgerId,
    required DateTime month,
  }) async {
    final startDate = DateTime(month.year, month.month, 1);
    final endDate = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    final query = '''
      SELECT DISTINCT DATE(happened_at) as date
      FROM transactions
      WHERE ledger_id = ?
        AND happened_at >= ?
        AND happened_at <= ?
      ORDER BY date DESC
    ''';

    final results = await db.customSelect(
      query,
      variables: [
        d.Variable.withInt(ledgerId),
        d.Variable.withDateTime(startDate),
        d.Variable.withDateTime(endDate),
      ],
    ).get();

    return results
        .map((row) => row.read<String?>('date'))
        .where((date) => date != null)
        .cast<String>()
        .toList();
  }

  // ==================== syncId 相关 ====================

  @override
  Future<Transaction?> getTransactionBySyncId(String syncId) async {
    return await (db.select(db.transactions)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingleOrNull();
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
    await (db.update(db.transactions)..where((t) => t.syncId.equals(syncId)))
        .write(TransactionsCompanion(
      type: d.Value(type),
      amount: d.Value(amount),
      categoryId: d.Value(categoryId),
      accountId: d.Value(accountId),
      toAccountId: d.Value(toAccountId),
      happenedAt: d.Value(happenedAt),
      note: d.Value(note),
    ));
  }

  @override
  Future<void> deleteTransactionBySyncId(String syncId) async {
    // 先查找交易ID，以便删除关联数据
    final tx = await getTransactionBySyncId(syncId);
    if (tx != null) {
      await deleteTransaction(tx.id);
    }
  }
}
