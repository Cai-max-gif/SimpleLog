import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/section_card.dart';
import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/currencies.dart';
import '../../utils/account_type_utils.dart';
import 'account_edit_page.dart';
import 'account_detail_page.dart';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  /// 拖拽后临时保持本地排序，防止 stream rebuild 闪烁
  Map<String, List<db.Account>>? _reorderingGroups;

  Map<String, List<db.Account>> _groupAccounts(List<db.Account> accounts) {
    final Map<String, List<db.Account>> grouped = {};
    for (final account in accounts) {
      grouped.putIfAbsent(account.type, () => []).add(account);
    }
    return grouped;
  }

  void _onReorder(String type, List<db.Account> groupAccounts, int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    // 乐观更新：用本地状态锁住当前排序，防止 stream 刷新导致闪烁
    setState(() {
      _reorderingGroups ??= _groupAccounts(
        ref.read(allAccountsStreamProvider).asData?.value ?? [],
      );
      final list = _reorderingGroups![type]!;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
    });

    // 构建排序更新
    final list = _reorderingGroups![type]!;
    final updates = <({int id, int sortOrder})>[];
    for (var i = 0; i < list.length; i++) {
      updates.add((id: list[i].id, sortOrder: i));
    }

    // 写入数据库，延迟清除本地状态让 stream 先到位
    ref.read(repositoryProvider).updateAccountSortOrders(updates).then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _reorderingGroups = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final accountFeatureAsync = ref.watch(accountFeatureEnabledProvider);
    final primaryColor = ref.watch(primaryColorProvider);
    final totalStatsAsync = ref.watch(allAccountsTotalStatsProvider);
    final allStatsAsync = ref.watch(allAccountStatsProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.accountsTitle,
            showBack: true,
            actions: [
              IconButton(
                onPressed: () => _addAccount(context, ref, ledgerId),
                icon: const Icon(Icons.add),
                tooltip: l10n.accountAddTooltip,
              ),
            ],
          ),
          Expanded(
            child: accountsAsync.when(
              data: (accounts) {
                final groups = _reorderingGroups ?? _groupAccounts(accounts);

                return ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.0.scaled(context, ref),
                    vertical: 8.0.scaled(context, ref),
                  ),
                  children: [
                    if (accounts.isEmpty)
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 64.0.scaled(context, ref),
                                color: BeeTokens.textTertiary(context),
                              ),
                              SizedBox(height: 16.0.scaled(context, ref)),
                              Text(
                                l10n.accountsEmptyMessage,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              SizedBox(height: 24.0.scaled(context, ref)),
                              ElevatedButton.icon(
                                onPressed: () => _addAccount(context, ref, ledgerId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.add),
                                label: Text(l10n.accountAddButton),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // 1. 汇总卡片
                      totalStatsAsync.when(
                        data: (stats) => SectionCard(
                          margin: EdgeInsets.zero,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
                            child: Stack(
                              children: [
                                // 右上角装饰：主题色半透明钱包图标
                                Positioned(
                                  right: -8,
                                  top: -8,
                                  child: Icon(
                                    Icons.account_balance_wallet_rounded,
                                    size: 72.0.scaled(context, ref),
                                    color: primaryColor.withValues(alpha: 0.06),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16.0.scaled(context, ref),
                                    vertical: 20.0.scaled(context, ref),
                                  ),
                                  child: Column(
                                    children: [
                                      // 总余额
                                      Text(
                                        l10n.accountTotalBalance,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: BeeTokens.textTertiary(context),
                                        ),
                                      ),
                                      SizedBox(height: 4.0.scaled(context, ref)),
                                      AmountText(
                                        value: stats.totalBalance,
                                        signed: false,
                                        showCurrency: false,
                                        useCompactFormat: ref.watch(compactAmountProvider),
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: BeeTokens.textPrimary(context),
                                        ),
                                      ),
                                      SizedBox(height: 16.0.scaled(context, ref)),
                                      // 收入/支出
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _SummaryStatItem(
                                              label: l10n.accountTotalIncome,
                                              value: stats.totalIncome,
                                              color: BeeTokens.incomeColor(context, ref),
                                            ),
                                          ),
                                          Container(
                                            width: 1,
                                            height: 28.0.scaled(context, ref),
                                            color: BeeTokens.divider(context),
                                          ),
                                          Expanded(
                                            child: _SummaryStatItem(
                                              label: l10n.accountTotalExpense,
                                              value: stats.totalExpense,
                                              color: BeeTokens.expenseColor(context, ref),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        loading: () => SectionCard(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0.scaled(context, ref)),
                              child: const CircularProgressIndicator(),
                            ),
                          ),
                        ),
                        error: (err, stack) => const SizedBox.shrink(),
                      ),

                      // 2. 设置项（紧凑）
                      SizedBox(height: 8.0.scaled(context, ref)),
                      accountFeatureAsync.when(
                        data: (enabled) {
                          return SectionCard(
                            margin: EdgeInsets.zero,
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4.0.scaled(context, ref),
                                  ),
                                  child: SwitchListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    title: Text(
                                      l10n.accountsEnableFeature,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: BeeTokens.textSecondary(context),
                                      ),
                                    ),
                                    value: enabled,
                                    activeColor: primaryColor,
                                    onChanged: (value) async {
                                      await ref
                                          .read(accountFeatureSetterProvider)
                                          .setEnabled(value);
                                      ref.invalidate(accountFeatureEnabledProvider);
                                    },
                                  ),
                                ),
                                if (enabled && accounts.isNotEmpty) ...[
                                  Divider(
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                    color: BeeTokens.divider(context),
                                  ),
                                  _CompactDefaultAccount(
                                    accounts: accounts,
                                    primaryColor: primaryColor,
                                    type: 'expense',
                                  ),
                                  Divider(
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                    color: BeeTokens.divider(context),
                                  ),
                                  _CompactDefaultAccount(
                                    accounts: accounts,
                                    primaryColor: primaryColor,
                                    type: 'income',
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),

                      // 2. 按类型分组的账户列表
                      ...accountTypeOrder
                          .where((type) => groups.containsKey(type) && groups[type]!.isNotEmpty)
                          .map((type) {
                        final groupList = groups[type]!;
                        return _AccountTypeGroup(
                          type: type,
                          accounts: groupList,
                          primaryColor: primaryColor,
                          allStats: allStatsAsync.asData?.value,
                          onReorder: (oldIndex, newIndex) =>
                              _onReorder(type, groupList, oldIndex, newIndex),
                          onTap: (account) =>
                              _viewAccountDetail(context, ref, account),
                          onEdit: (account) =>
                              _editAccount(context, ref, account, ledgerId),
                        );
                      }),

                      // 处理不在固定类型列表中的类型
                      ...groups.keys
                          .where((type) => !accountTypeOrder.contains(type) && groups[type]!.isNotEmpty)
                          .map((type) {
                        final groupList = groups[type]!;
                        return _AccountTypeGroup(
                          type: type,
                          accounts: groupList,
                          primaryColor: primaryColor,
                          allStats: allStatsAsync.asData?.value,
                          onReorder: (oldIndex, newIndex) =>
                              _onReorder(type, groupList, oldIndex, newIndex),
                          onTap: (account) =>
                              _viewAccountDetail(context, ref, account),
                          onEdit: (account) =>
                              _editAccount(context, ref, account, ledgerId),
                        );
                      }),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text('${l10n.commonError}: $err'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addAccount(BuildContext context, WidgetRef ref, int ledgerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountEditPage(ledgerId: ledgerId),
      ),
    );

    ref.invalidate(allAccountStatsProvider);
    ref.invalidate(allAccountsTotalStatsProvider);
    ref.invalidate(statsRefreshProvider);
  }

  Future<void> _editAccount(BuildContext context, WidgetRef ref,
      db.Account account, int ledgerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountEditPage(
          account: account,
          ledgerId: ledgerId,
        ),
      ),
    );

    ref.invalidate(allAccountStatsProvider);
    ref.invalidate(allAccountsTotalStatsProvider);
    ref.invalidate(statsRefreshProvider);
  }

  void _viewAccountDetail(
      BuildContext context, WidgetRef ref, db.Account account) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountDetailPage(account: account),
      ),
    );
  }
}

/// 账户类型分组（可折叠，默认折叠）
class _AccountTypeGroup extends ConsumerStatefulWidget {
  final String type;
  final List<db.Account> accounts;
  final Color primaryColor;
  final Map<int, ({double balance, double expense, double income})>? allStats;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(db.Account account) onTap;
  final void Function(db.Account account) onEdit;

  const _AccountTypeGroup({
    required this.type,
    required this.accounts,
    required this.primaryColor,
    this.allStats,
    required this.onReorder,
    required this.onTap,
    required this.onEdit,
  });

  @override
  ConsumerState<_AccountTypeGroup> createState() => _AccountTypeGroupState();
}

class _AccountTypeGroupState extends ConsumerState<_AccountTypeGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final typeColor = getColorForAccountType(widget.type, widget.primaryColor);
    final canReorder = widget.accounts.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 类型标题栏（点击展开/折叠）
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.only(
              top: 14.0.scaled(context, ref),
              bottom: 8.0.scaled(context, ref),
              left: 4.0.scaled(context, ref),
              right: 4.0.scaled(context, ref),
            ),
            child: Row(
              children: [
                Container(
                  width: 32.0.scaled(context, ref),
                  height: 32.0.scaled(context, ref),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
                  ),
                  child: Center(
                    child: AccountTypeIcon(
                      type: widget.type,
                      size: 18.0.scaled(context, ref),
                      color: typeColor,
                    ),
                  ),
                ),
                SizedBox(width: 10.0.scaled(context, ref)),
                Text(
                  getAccountTypeLabel(context, widget.type),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                SizedBox(width: 6.0.scaled(context, ref)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6.0.scaled(context, ref),
                    vertical: 1.0.scaled(context, ref),
                  ),
                  decoration: BoxDecoration(
                    color: BeeTokens.textTertiary(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10.0.scaled(context, ref)),
                  ),
                  child: Text(
                    '${widget.accounts.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textTertiary(context),
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20.0.scaled(context, ref),
                    color: BeeTokens.iconTertiary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 可折叠的账户卡片列表
        if (_expanded)
          canReorder
              ? ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: widget.accounts.length,
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      elevation: 4,
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12.0),
                      child: child,
                    );
                  },
                  onReorder: widget.onReorder,
                  itemBuilder: (context, index) {
                    final account = widget.accounts[index];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(account.id),
                      index: index,
                      child: _AccountCard(
                        account: account,
                        primaryColor: widget.primaryColor,
                        typeColor: typeColor,
                        stats: widget.allStats?[account.id],
                        onTap: () => widget.onTap(account),
                        onEdit: () => widget.onEdit(account),
                      ),
                    );
                  },
                )
              : Column(
                  children: widget.accounts.map((account) {
                    return _AccountCard(
                      account: account,
                      primaryColor: widget.primaryColor,
                      typeColor: typeColor,
                      stats: widget.allStats?[account.id],
                      onTap: () => widget.onTap(account),
                      onEdit: () => widget.onEdit(account),
                    );
                  }).toList(),
                ),
      ],
    );
  }
}

/// 汇总卡片内收入/支出项
class _SummaryStatItem extends ConsumerWidget {
  final String label;
  final double value;
  final Color color;

  const _SummaryStatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: BeeTokens.textTertiary(context),
          ),
        ),
        SizedBox(height: 2.0.scaled(context, ref)),
        AmountText(
          value: value,
          signed: false,
          showCurrency: false,
          useCompactFormat: ref.watch(compactAmountProvider),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 紧凑默认账户选择行
class _CompactDefaultAccount extends ConsumerWidget {
  final List<db.Account> accounts;
  final Color primaryColor;
  final String type;

  const _CompactDefaultAccount({
    required this.accounts,
    required this.primaryColor,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isIncome = type == 'income';
    final defaultAccountIdAsync = isIncome
        ? ref.watch(defaultIncomeAccountIdProvider)
        : ref.watch(defaultExpenseAccountIdProvider);

    return defaultAccountIdAsync.when(
      data: (defaultAccountId) {
        db.Account? defaultAccount;
        if (defaultAccountId != null) {
          defaultAccount = accounts.where((a) => a.id == defaultAccountId).firstOrNull;
        }

        final title = isIncome
            ? l10n.accountDefaultIncomeTitle
            : l10n.accountDefaultExpenseTitle;

        return InkWell(
          onTap: () => _showPicker(context, ref, accounts, defaultAccountId),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16.0.scaled(context, ref),
              vertical: 10.0.scaled(context, ref),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
                const Spacer(),
                Text(
                  defaultAccount?.name ?? l10n.accountDefaultNone,
                  style: TextStyle(
                    fontSize: 13,
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
                SizedBox(width: 2.0.scaled(context, ref)),
                Icon(
                  Icons.chevron_right,
                  size: 16.0.scaled(context, ref),
                  color: BeeTokens.iconTertiary(context),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref, List<db.Account> accounts, int? currentDefaultId) {
    final l10n = AppLocalizations.of(context);
    final isIncome = type == 'income';
    final title = isIncome ? l10n.accountDefaultIncomeTitle : l10n.accountDefaultExpenseTitle;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BeeTokens.surfaceElevated(context),
        title: Text(title, style: TextStyle(color: BeeTokens.textPrimary(context))),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: Icon(Icons.block, color: BeeTokens.iconSecondary(context)),
                title: Text(
                  l10n.accountDefaultNone,
                  style: TextStyle(
                    color: currentDefaultId == null ? primaryColor : BeeTokens.textPrimary(context),
                    fontWeight: currentDefaultId == null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: currentDefaultId == null ? Icon(Icons.check, color: primaryColor) : null,
                onTap: () async {
                  if (isIncome) {
                    await ref.read(defaultAccountSetterProvider).setDefaultIncomeAccountId(null);
                    ref.invalidate(defaultIncomeAccountIdProvider);
                  } else {
                    await ref.read(defaultAccountSetterProvider).setDefaultExpenseAccountId(null);
                    ref.invalidate(defaultExpenseAccountIdProvider);
                  }
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              ...accounts.map((account) {
                final isSelected = account.id == currentDefaultId;
                return ListTile(
                  dense: true,
                  leading: AccountTypeIcon(
                    type: account.type,
                    size: 24,
                  ),
                  title: Text(
                    account.name,
                    style: TextStyle(
                      color: isSelected ? primaryColor : BeeTokens.textPrimary(context),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                  onTap: () async {
                    if (isIncome) {
                      await ref.read(defaultAccountSetterProvider).setDefaultIncomeAccountId(account.id);
                      ref.invalidate(defaultIncomeAccountIdProvider);
                    } else {
                      await ref.read(defaultAccountSetterProvider).setDefaultExpenseAccountId(account.id);
                      ref.invalidate(defaultExpenseAccountIdProvider);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// 账户卡片 - 类似银行卡样式
class _AccountCard extends ConsumerWidget {
  final db.Account account;
  final Color primaryColor;
  final Color typeColor;
  final ({double balance, double expense, double income})? stats;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _AccountCard({
    required this.account,
    required this.primaryColor,
    required this.typeColor,
    this.stats,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 8.0.scaled(context, ref)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              typeColor,
              typeColor.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10.0.scaled(context, ref)),
          boxShadow: [
            BoxShadow(
              color: typeColor.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.0.scaled(context, ref)),
          child: Stack(
            children: [
              // 背景装饰圆圈
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 80.0.scaled(context, ref),
                  height: 80.0.scaled(context, ref),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              // 卡片内容
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14.0.scaled(context, ref),
                  vertical: 12.0.scaled(context, ref),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部：图标 + 账户名称 + 币种 + 编辑
                    Row(
                      children: [
                        Container(
                          width: 32.0.scaled(context, ref),
                          height: 32.0.scaled(context, ref),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: AccountTypeIcon(
                              type: account.type,
                              size: 18.0.scaled(context, ref),
                            ),
                          ),
                        ),
                        SizedBox(width: 10.0.scaled(context, ref)),
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  account.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 8.0.scaled(context, ref)),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 5.0.scaled(context, ref),
                                  vertical: 1.0.scaled(context, ref),
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
                                ),
                                child: Text(
                                  getCurrencyName(account.currency, context),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => onEdit(),
                          child: Container(
                            padding: EdgeInsets.all(6.0.scaled(context, ref)),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 14.0.scaled(context, ref),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.0.scaled(context, ref)),
                    // 统计数据
                    if (stats != null)
                      Row(
                        children: [
                          Expanded(
                            child: _CardStatItem(
                              label:
                                  AppLocalizations.of(context).accountBalance,
                              value: stats!.balance,
                              currencyCode: account.currency,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 24.0.scaled(context, ref),
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          Expanded(
                            child: _CardStatItem(
                              label: AppLocalizations.of(context).homeIncome,
                              value: stats!.income,
                              currencyCode: account.currency,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 24.0.scaled(context, ref),
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          Expanded(
                            child: _CardStatItem(
                              label: AppLocalizations.of(context).homeExpense,
                              value: stats!.expense,
                              currencyCode: account.currency,
                            ),
                          ),
                        ],
                      )
                    else
                      Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 4.0.scaled(context, ref)),
                          child: const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片内统计项
class _CardStatItem extends ConsumerWidget {
  final String label;
  final double value;
  final String currencyCode;

  const _CardStatItem({
    required this.label,
    required this.value,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        AmountText(
          value: value,
          signed: false,
          showCurrency: false,
          useCompactFormat: ref.watch(compactAmountProvider),
          currencyCode: currencyCode,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 1.0.scaled(context, ref)),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

