import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../providers.dart';
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../services/billing/post_processor.dart';
import '../../services/attachment_service.dart';
import '../biz/amount_editor_sheet.dart';
import '../../utils/account_type_utils.dart';
import '../ui/ui.dart';

/// 转账表单组件
/// 用于创建或编辑转账记录
class TransferForm extends ConsumerStatefulWidget {
  /// 转账完成回调
  final VoidCallback onTransferComplete;

  /// 初始转出账户ID（可选）
  final int? initialFromAccountId;

  /// 初始转入账户ID（可选）
  final int? initialToAccountId;

  /// 正在编辑的交易ID（编辑模式）
  final int? editingTransactionId;

  /// 初始金额（可选）
  final double? initialAmount;

  /// 初始备注（可选）
  final String? initialNote;

  /// 初始日期（可选）
  final DateTime? initialDate;

  /// 初始标签ID列表（可选）
  final List<int>? initialTagIds;

  const TransferForm({
    super.key,
    required this.onTransferComplete,
    this.initialFromAccountId,
    this.initialToAccountId,
    this.editingTransactionId,
    this.initialAmount,
    this.initialNote,
    this.initialDate,
    this.initialTagIds,
  });

  @override
  ConsumerState<TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends ConsumerState<TransferForm> {
  int? _fromAccountId;
  int? _toAccountId;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    // 初始化账户ID（用于编辑模式）
    _fromAccountId = widget.initialFromAccountId;
    _toAccountId = widget.initialToAccountId;

    // 如果是编辑模式且两个账户都已选择，自动打开金额编辑弹窗
    if (widget.editingTransactionId != null &&
        _fromAccountId != null &&
        _toAccountId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && !_autoOpened) {
          _autoOpened = true;
          await _openAmountSheet();
        }
      });
    }
  }

  // 检查两个账户是否是相同币种
  Future<bool> _checkSameCurrency() async {
    if (_fromAccountId == null || _toAccountId == null) return false;

    final repo = ref.read(repositoryProvider);
    final fromAccount = await repo.getAccount(_fromAccountId!);
    final toAccount = await repo.getAccount(_toAccountId!);

    return fromAccount?.currency == toAccount?.currency;
  }

  // 当两个账户都选择后，自动弹出金额输入弹窗
  Future<void> _openAmountSheet() async {
    final l10n = AppLocalizations.of(context);

    // 检查币种是否一致
    final sameCurrency = await _checkSameCurrency();
    if (!sameCurrency) {
      if (mounted) {
        showToast(context, l10n.transferDifferentCurrencyError);
        // 重置转入账户
        setState(() => _toAccountId = null);
      }
      return;
    }

    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      builder: (context) => AmountEditorSheet(
        categoryName: l10n.transferTitle,
        initialDate: widget.initialDate ?? DateTime.now(),
        initialAmount: widget.initialAmount,
        initialNote: widget.initialNote,
        initialTagIds: widget.initialTagIds,
        showAccountPicker: false,
        ledgerId: ledgerId,
        editingTransactionId: widget.editingTransactionId,
        onSubmit: (result) async {
          final attachmentService = ref.read(attachmentServiceProvider);
          // 获取虚拟转账分类ID
          final transferCategory = await ref.read(transferCategoryProvider.future);
          final transferCategoryId = transferCategory.id;

          try {
            if (widget.editingTransactionId != null) {
              // 编辑模式：更新现有转账记录
              await repo.updateTransaction(
                id: widget.editingTransactionId!,
                type: 'transfer',
                amount: result.amount,
                categoryId: transferCategoryId, // 使用虚拟转账分类ID
                note: result.note,
                happenedAt: result.date,
                accountId: _fromAccountId,
              );
              // 更新 toAccountId（使用专用方法）
              await repo.updateTransactionFields(
                id: widget.editingTransactionId!,
                toAccountId: _toAccountId,
              );
              // 更新标签
              if (result.tagIds.isNotEmpty) {
                await repo.updateTransactionTags(
                  transactionId: widget.editingTransactionId!,
                  tagIds: result.tagIds,
                );
                // 刷新标签列表缓存
                ref.read(tagListRefreshProvider.notifier).state++;
              } else {
                // 编辑模式：如果没有选择标签，清除原有标签
                await repo.removeAllTagsFromTransaction(widget.editingTransactionId!);
                ref.read(tagListRefreshProvider.notifier).state++;
              }

              // 保存待上传的附件
              if (result.pendingAttachments.isNotEmpty) {
                await attachmentService.saveAttachments(
                  transactionId: widget.editingTransactionId!,
                  sourceFiles: result.pendingAttachments,
                  startIndex: 0,
                );
                // 刷新附件列表缓存
                ref.read(attachmentListRefreshProvider.notifier).state++;
              }

              // 统一处理：自动/手动同步与状态刷新
              await PostProcessor.sync(ref, ledgerId: ledgerId);
              // 刷新统计
              ref.invalidate(countsForLedgerProvider(ledgerId));
              ref.read(statsRefreshProvider.notifier).state++;

              if (!context.mounted) return;
              Navigator.of(context).pop(); // 关闭金额输入弹窗
              showToast(context, l10n.transferUpdateSuccess);
              widget.onTransferComplete();
            } else {
              // 创建模式：新建转账记录
              final txId = await repo.addTransaction(
                ledgerId: ledgerId,
                type: 'transfer',
                amount: result.amount,
                categoryId: transferCategoryId, // 使用虚拟转账分类ID
                accountId: _fromAccountId,
                toAccountId: _toAccountId,
                note: result.note,
                happenedAt: result.date,
              );

              // 关联标签
              if (result.tagIds.isNotEmpty) {
                await repo.updateTransactionTags(
                  transactionId: txId,
                  tagIds: result.tagIds,
                );
                // 刷新标签列表缓存
                ref.read(tagListRefreshProvider.notifier).state++;
              }

              // 保存待上传的附件
              if (result.pendingAttachments.isNotEmpty) {
                await attachmentService.saveAttachments(
                  transactionId: txId,
                  sourceFiles: result.pendingAttachments,
                  startIndex: 0,
                );
                // 刷新附件列表缓存
                ref.read(attachmentListRefreshProvider.notifier).state++;
              }

              // 统一处理：自动/手动同步与状态刷新
              await PostProcessor.sync(ref, ledgerId: ledgerId);
              // 刷新统计
              ref.invalidate(countsForLedgerProvider(ledgerId));
              ref.read(statsRefreshProvider.notifier).state++;

              if (!context.mounted) return;
              Navigator.of(context).pop(); // 关闭金额输入弹窗
              showToast(context, l10n.transferCreateSuccess);

              // 重置状态
              setState(() {
                _fromAccountId = null;
                _toAccountId = null;
              });

              widget.onTransferComplete();
            }
          } catch (e) {
            if (context.mounted) {
              Navigator.of(context).pop();
              showToast(context, '${l10n.commonError}: $e');
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = ref.watch(primaryColorProvider);
    final allAccountsAsync = ref.watch(allAccountsStreamProvider);
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currentCurrency = currentLedgerAsync.asData?.value?.currency ?? 'CNY';

    return allAccountsAsync.when(
      data: (allAccounts) {
        // 只显示与当前账本同币种的账户
        final accounts = allAccounts
            .where((account) => account.currency == currentCurrency)
            .toList();

        if (accounts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l10n.transferSelectAccount,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }

        // 根据转出账户过滤转入账户列表
        final toAccounts = _fromAccountId != null
            ? accounts.where((a) => a.id != _fromAccountId).toList()
            : accounts;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 转出账户标题
              Text(
                l10n.transferFromAccount,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              // 转出账户网格
              _buildAccountGrid(accounts, true, primary),
              const SizedBox(height: 24),
              // 转账箭头
              Center(
                child: Icon(
                  Icons.arrow_downward,
                  color: primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),
              // 转入账户标题
              Text(
                l10n.transferToAccount,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              // 转入账户网格
              _buildAccountGrid(toAccounts, false, primary),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          '${l10n.commonError}: $err',
          style: const TextStyle(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildAccountGrid(List<Account> accounts, bool isFrom, Color primary) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: accounts.length,
      itemBuilder: (context, index) {
        final account = accounts[index];
        final isSelected = isFrom
            ? _fromAccountId == account.id
            : _toAccountId == account.id;

        return _buildAccountCard(account, isSelected, isFrom, primary);
      },
    );
  }

  Widget _buildAccountCard(
    Account account,
    bool isSelected,
    bool isFrom,
    Color primary,
  ) {
    return InkWell(
      onTap: () async {
        setState(() {
          if (isFrom) {
            _fromAccountId = account.id;
            // 如果转入账户已选择且与转出账户相同，则清空转入账户
            if (_toAccountId == account.id) {
              _toAccountId = null;
            }
          } else {
            _toAccountId = account.id;
          }
        });

        // 如果两个账户都已选择，自动弹出金额输入弹窗
        if (_fromAccountId != null && _toAccountId != null) {
          await _openAmountSheet();
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.1) : Colors.white,
          border: Border.all(
            color: isSelected ? primary : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AccountTypeIcon(
              type: account.type,
              size: 32,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                account.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? primary : Colors.grey[800],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
