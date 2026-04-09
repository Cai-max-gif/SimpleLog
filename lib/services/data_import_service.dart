import 'package:drift/drift.dart' as d;
import '../data/db.dart';
import '../data/repositories/base_repository.dart';
import 'system/logger_service.dart';

/// 统一的数据导入服务
///
/// 用于CSV导入和云端恢复，确保两者使用相同的导入逻辑

// --- 导入数据模型 ---

/// 导入账户数据
class ImportAccount {
  final String name;
  final String? type;
  final String? currency;
  final double? initialBalance;

  const ImportAccount({
    required this.name,
    this.type,
    this.currency,
    this.initialBalance,
  });
}

/// 导入分类数据
class ImportCategory {
  final String name;
  final String kind; // 'income' or 'expense'
  final int level; // 1 or 2
  final int sortOrder; // 排序顺序
  final String? icon;
  final String? parentName; // 二级分类的父分类名称
  final String? iconType; // 图标类型: material / custom / community
  final String? customIconPath; // 自定义图标路径
  final String? communityIconId; // 社区图标ID

  const ImportCategory({
    required this.name,
    required this.kind,
    this.level = 1,
    this.sortOrder = 0,
    this.icon,
    this.parentName,
    this.iconType,
    this.customIconPath,
    this.communityIconId,
  });
}

/// 导入标签数据
class ImportTag {
  final String name;
  final String? color;

  const ImportTag({
    required this.name,
    this.color,
  });
}

/// 导入附件数据
class ImportAttachment {
  final String fileName;
  final String? originalName;
  final int? fileSize;
  final int? width;
  final int? height;
  final int sortOrder;

  const ImportAttachment({
    required this.fileName,
    this.originalName,
    this.fileSize,
    this.width,
    this.height,
    this.sortOrder = 0,
  });
}

/// 导入交易数据
class ImportTransaction {
  final String type; // 'income', 'expense', 'transfer'
  final double amount;
  final String? categoryName;
  final String? categoryKind;
  final DateTime happenedAt;
  final String? note;
  final String? accountName; // 普通账户（收入/支出）
  final String? fromAccountName; // 转出账户（转账）
  final String? toAccountName; // 转入账户（转账）
  final List<String>? tagNames; // 标签名称列表
  final int? categoryId; // 预解析的分类ID（优先于categoryName）
  final List<ImportAttachment>? attachments; // 附件元数据列表
  final String? syncId; // 跨设备同步唯一标识

  const ImportTransaction({
    required this.type,
    required this.amount,
    this.categoryName,
    this.categoryKind,
    required this.happenedAt,
    this.note,
    this.accountName,
    this.fromAccountName,
    this.toAccountName,
    this.tagNames,
    this.categoryId,
    this.attachments,
    this.syncId,
  });
}

/// 统一的导入数据格式
class ImportData {
  final List<ImportAccount> accounts;
  final List<ImportCategory> categories;
  final List<ImportTag> tags;
  final List<ImportTransaction> transactions;

  /// 账本名称（可选，用于更新账本信息）
  final String? ledgerName;
  /// 货币（可选，用于更新账本信息）
  final String? currency;

  const ImportData({
    this.accounts = const [],
    this.categories = const [],
    this.tags = const [],
    this.transactions = const [],
    this.ledgerName,
    this.currency,
  });
}

/// 导入结果
class ImportResult {
  final int inserted;
  final int failed;

  const ImportResult({
    required this.inserted,
    required this.failed,
  });
}

// --- 数据导入服务 ---

/// 通用数据导入服务
///
/// 提供统一的导入逻辑，支持：
/// - 账户创建（全局按名称去重）
/// - 分类创建（先一级后二级）
/// - 标签创建
/// - 交易插入（批量写入）
/// - 标签关联
class DataImportService {
  /// 导入数据到指定账本
  ///
  /// [repo] - 数据仓库
  /// [ledgerId] - 目标账本ID
  /// [data] - 导入数据
  /// [defaultCurrency] - 默认货币（用于创建账户）
  /// [onProgress] - 进度回调 (done, total)
  Future<ImportResult> importData(
    BaseRepository repo,
    int ledgerId,
    ImportData data, {
    String defaultCurrency = 'CNY',
    void Function(int done, int total)? onProgress,
  }) async {
    // 1. 更新账本信息（如果提供）
    if (data.ledgerName != null || data.currency != null) {
      try {
        await repo.updateLedger(
          id: ledgerId,
          name: data.ledgerName,
          currency: data.currency,
        );
      } catch (_) {}
    }

    // 2. 导入账户
    final accountNameToId = await _importAccounts(
      repo,
      data.accounts,
      defaultCurrency: data.currency ?? defaultCurrency,
    );

    // 3. 导入分类
    final categoryCache = await _importCategories(repo, data.categories);

    // 4. 导入标签
    final tagNameToId = await _importTags(repo, data.tags);

    // 5. 导入交易
    final result = await _importTransactions(
      repo,
      ledgerId,
      data.transactions,
      accountNameToId: accountNameToId,
      categoryCache: categoryCache,
      tagNameToId: tagNameToId,
      onProgress: onProgress,
    );

    return result;
  }

  /// 导入账户（全局按名称去重）
  Future<Map<String, int>> _importAccounts(
    BaseRepository repo,
    List<ImportAccount> accounts,
    {String defaultCurrency = 'CNY'}
  ) async {
    final accountNameToId = <String, int>{};

    if (accounts.isEmpty) return accountNameToId;

    try {
      // 获取所有现有账户（全局去重）
      final existingAccounts = await repo.getAllAccounts();
      for (final acc in existingAccounts) {
        accountNameToId[acc.name] = acc.id;
      }

      // 创建不存在的账户
      for (final acc in accounts) {
        if (!accountNameToId.containsKey(acc.name)) {
          final id = await repo.createAccount(
            ledgerId: 0, // 账户独立，不绑定账本
            name: acc.name,
            type: acc.type ?? 'cash',
            currency: acc.currency ?? defaultCurrency,
            initialBalance: acc.initialBalance ?? 0.0,
          );
          accountNameToId[acc.name] = id;
        }
      }
    } catch (_) {
      // 账户导入失败不影响交易导入
    }

    return accountNameToId;
  }

  /// 导入分类（先一级后二级）
  Future<Map<String, int>> _importCategories(
    BaseRepository repo,
    List<ImportCategory> categories,
  ) async {
    final categoryCache = <String, int>{}; // key: kind|name -> id

    if (categories.isEmpty) return categoryCache;

    try {
      // 获取所有现有分类
      final existingExpense = await repo.getTopLevelCategories('expense');
      final existingIncome = await repo.getTopLevelCategories('income');
      final existingCategoryMap = <String, int>{};

      for (final cat in [...existingExpense, ...existingIncome]) {
        existingCategoryMap['${cat.kind}|${cat.name}'] = cat.id;
        // 获取子分类
        final subCats = await repo.getSubCategories(cat.id);
        for (final sub in subCats) {
          existingCategoryMap['${sub.kind}|${sub.name}'] = sub.id;
        }
      }

      // 分离一级和二级分类
      final level1 = categories.where((c) => c.level == 1 || c.parentName == null).toList();
      final level2 = categories.where((c) => c.level == 2 && c.parentName != null).toList();

      // 导入一级分类
      for (final cat in level1) {
        final key = '${cat.kind}|${cat.name}';
        if (existingCategoryMap.containsKey(key)) {
          categoryCache[key] = existingCategoryMap[key]!;
        } else {
          final id = await repo.createCategory(
            name: cat.name,
            kind: cat.kind,
            icon: cat.icon,
            sortOrder: cat.sortOrder,
          );
          categoryCache[key] = id;

          // 如果有自定义图标信息，更新图标
          if (cat.iconType != null && cat.iconType != 'material') {
            await repo.updateCategoryIcon(
              id,
              iconType: cat.iconType!,
              icon: cat.icon,
              customIconPath: cat.customIconPath,
              communityIconId: cat.communityIconId,
            );
          }
        }
      }

      // 导入二级分类
      for (final cat in level2) {
        final key = '${cat.kind}|${cat.name}';
        if (existingCategoryMap.containsKey(key)) {
          categoryCache[key] = existingCategoryMap[key]!;
        } else {
          // 查找父分类ID
          final parentKey = '${cat.kind}|${cat.parentName}';
          final parentId = categoryCache[parentKey];
          if (parentId != null) {
            final id = await repo.createSubCategory(
              parentId: parentId,
              name: cat.name,
              kind: cat.kind,
              icon: cat.icon,
              sortOrder: cat.sortOrder,
            );
            categoryCache[key] = id;

            // 如果有自定义图标信息，更新图标
            if (cat.iconType != null && cat.iconType != 'material') {
              await repo.updateCategoryIcon(
                id,
                iconType: cat.iconType!,
                icon: cat.icon,
                customIconPath: cat.customIconPath,
                communityIconId: cat.communityIconId,
              );
            }
          }
        }
      }
    } catch (_) {
      // 分类导入失败不影响交易导入
    }

    return categoryCache;
  }

  /// 导入标签
  Future<Map<String, int>> _importTags(
    BaseRepository repo,
    List<ImportTag> tags,
  ) async {
    final tagNameToId = <String, int>{};

    if (tags.isEmpty) return tagNameToId;

    logger.info('TagImport', '开始导入标签: ${tags.length}个');

    try {
      // 获取所有现有标签
      final existingTags = await repo.getAllTags();
      final existingTagMap = <String, Tag>{};
      for (final tag in existingTags) {
        tagNameToId[tag.name] = tag.id;
        existingTagMap[tag.name] = tag;
      }

      // 创建不存在的标签，更新已存在标签的颜色
      for (final tag in tags) {
        logger.info('TagImport', '处理标签: name="${tag.name}", color="${tag.color}"');
        if (!tagNameToId.containsKey(tag.name)) {
          // 创建新标签
          logger.info('TagImport', '创建新标签: name="${tag.name}", color="${tag.color}"');
          final id = await repo.createTag(name: tag.name, color: tag.color);
          tagNameToId[tag.name] = id;
          // 验证创建结果
          final created = await repo.getTagById(id);
          logger.info('TagImport', '创建结果: id=$id, name="${created?.name}", color="${created?.color}"');
        } else if (tag.color != null) {
          // 标签已存在，检查是否需要更新颜色
          final existingTag = existingTagMap[tag.name];
          if (existingTag != null && existingTag.color != tag.color) {
            logger.info('TagImport', '更新标签颜色: ${tag.name}, "${existingTag.color}" -> "${tag.color}"');
            await repo.updateTag(existingTag.id, color: tag.color);
          }
        }
      }
      logger.info('TagImport', '标签导入完成');
    } catch (e) {
      logger.error('TagImport', '标签导入失败', e);
      // 标签导入失败不影响交易导入
    }

    return tagNameToId;
  }

  /// 导入交易（批量写入 + 标签关联）
  Future<ImportResult> _importTransactions(
    BaseRepository repo,
    int ledgerId,
    List<ImportTransaction> transactions, {
    required Map<String, int> accountNameToId,
    required Map<String, int> categoryCache,
    required Map<String, int> tagNameToId,
    void Function(int done, int total)? onProgress,
  }) async {
    int inserted = 0;
    int failed = 0;
    int processed = 0;
    final total = transactions.length;

    // 批量待插入列表
    final toInsert = <TransactionsCompanion>[];
    const batchSize = 500;

    // 分类缓存（用于动态创建）
    final localCategoryCache = Map<String, int>.from(categoryCache);

    for (final tx in transactions) {
      // 解析分类ID
      int? categoryId;
      // 优先使用预解析的分类ID
      if (tx.categoryId != null) {
        categoryId = tx.categoryId;
      } else if (tx.categoryName != null && tx.categoryKind != null) {
        final key = '${tx.categoryKind}|${tx.categoryName}';
        categoryId = localCategoryCache[key];
        if (categoryId == null && tx.type != 'transfer') {
          // 动态创建分类
          try {
            categoryId = await repo.upsertCategory(
              name: tx.categoryName!,
              kind: tx.categoryKind!,
            );
            localCategoryCache[key] = categoryId;
          } catch (_) {}
        }
      }

      // 解析账户ID
      int? accountId;
      int? toAccountId;

      if (tx.type == 'transfer') {
        // 转账：使用 fromAccountName 和 toAccountName
        if (tx.fromAccountName != null) {
          accountId = accountNameToId[tx.fromAccountName];
          // 提供了账户名但找不到对应账户 -> 失败
          if (accountId == null) {
            failed++;
            processed++;
            continue;
          }
        }
        if (tx.toAccountName != null) {
          toAccountId = accountNameToId[tx.toAccountName];
          // 提供了账户名但找不到对应账户 -> 失败
          if (toAccountId == null) {
            failed++;
            processed++;
            continue;
          }
        }
        // 注意：旧版本数据可能没有账户信息，允许导入（账户为空）
      } else {
        // 收入或支出：使用 accountName
        if (tx.accountName != null) {
          accountId = accountNameToId[tx.accountName];
        }
      }

      // 解析标签ID
      final tagIds = <int>[];
      if (tx.tagNames != null) {
        for (final tagName in tx.tagNames!) {
          var tagId = tagNameToId[tagName];
          if (tagId == null) {
            // 动态创建标签
            try {
              final existingTag = await repo.getTagByName(tagName);
              if (existingTag != null) {
                tagId = existingTag.id;
              } else {
                tagId = await repo.createTag(name: tagName);
              }
              tagNameToId[tagName] = tagId;
            } catch (_) {}
          }
          if (tagId != null) {
            tagIds.add(tagId);
          }
        }
      }

      // 构建交易记录
      final txCompanion = TransactionsCompanion.insert(
        ledgerId: ledgerId,
        type: tx.type,
        amount: tx.amount,
        categoryId: d.Value(tx.type == 'transfer' ? null : categoryId),
        accountId: d.Value(accountId),
        toAccountId: d.Value(toAccountId),
        happenedAt: d.Value(tx.happenedAt),
        note: d.Value(tx.note),
        syncId: d.Value(tx.syncId),
      );

      // 如果有标签或附件，单独插入并关联
      final hasAttachments = tx.attachments != null && tx.attachments!.isNotEmpty;
      if (tagIds.isNotEmpty || hasAttachments) {
        try {
          final txId = await repo.insertTransactionCompanion(txCompanion);
          // 关联标签
          if (tagIds.isNotEmpty) {
            await repo.updateTransactionTags(
              transactionId: txId,
              tagIds: tagIds,
            );
          }
          // 创建附件元数据记录（注意：仅创建记录，实际图片文件需单独导入）
          if (hasAttachments) {
            for (final attachment in tx.attachments!) {
              try {
                await repo.createAttachment(
                  transactionId: txId,
                  fileName: attachment.fileName,
                  originalName: attachment.originalName,
                  fileSize: attachment.fileSize,
                  width: attachment.width,
                  height: attachment.height,
                  sortOrder: attachment.sortOrder,
                );
              } catch (_) {
                // 附件记录创建失败不影响交易导入
              }
            }
          }
          inserted++;
        } catch (_) {
          failed++;
        }
        processed++;
      } else {
        // 没有标签和附件，批量插入
        toInsert.add(txCompanion);
      }

      // 批量写入
      if (toInsert.length >= batchSize) {
        try {
          final n = await repo.insertTransactionsBatch(List.of(toInsert));
          inserted += n;
          processed += n;
        } catch (_) {
          failed += toInsert.length;
          processed += toInsert.length;
        }
        toInsert.clear();
        if (onProgress != null) onProgress(processed, total);
      }
    }

    // 刷新剩余缓冲
    if (toInsert.isNotEmpty) {
      try {
        final n = await repo.insertTransactionsBatch(toInsert);
        inserted += n;
        processed += n;
      } catch (_) {
        failed += toInsert.length;
        processed += toInsert.length;
      }
    }

    if (onProgress != null) onProgress(processed, total);

    return ImportResult(inserted: inserted, failed: failed);
  }
}

/// 全局单例
final dataImportService = DataImportService();
