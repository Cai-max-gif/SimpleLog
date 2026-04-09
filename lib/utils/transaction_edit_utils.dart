import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart';
import '../pages/transaction/transaction_editor_page.dart';
import '../providers/database_providers.dart';

class TransactionEditUtils {
  static Future<void> editTransaction(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
    Category? category,
  ) async {
    // 获取交易关联的标签ID
    final repo = ref.read(repositoryProvider);
    final tags = await repo.getTagsForTransaction(transaction.id);
    final tagIds = tags.map((t) => t.id).toList();

    if (!context.mounted) return;

    // 所有类型（收入/支出/转账）都使用交易编辑器页面
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: transaction.type, // 'expense', 'income', 或 'transfer'
          quickAdd: true,
          initialCategoryId: transaction.categoryId,
          initialAmount: transaction.amount,
          initialDate: transaction.happenedAt,
          initialNote: transaction.note,
          editingTransactionId: transaction.id,
          initialAccountId: transaction.accountId,
          // 转账特有的参数
          initialToAccountId: transaction.toAccountId,
          // 标签
          initialTagIds: tagIds,
        ),
      ),
    );
  }
}