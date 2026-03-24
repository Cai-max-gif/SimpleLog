import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/biz/app_list_tile.dart';
import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../services/billing/post_processor.dart';
import '../../utils/currencies.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/account_type_utils.dart';

class AccountEditPage extends ConsumerStatefulWidget {
  final db.Account? account; // null表示新建
  final int ledgerId;

  const AccountEditPage({
    super.key,
    this.account,
    required this.ledgerId,
  });

  @override
  ConsumerState<AccountEditPage> createState() => _AccountEditPageState();
}

class _AccountEditPageState extends ConsumerState<AccountEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _initialBalanceController;
  late String _selectedType;
  late String _selectedCurrency;
  bool _saving = false;
  bool _isNameDuplicate = false;
  String? _nameErrorText;

  // 预设账户类型
  static const List<String> accountTypes = [
    'cash',
    'bank_card',
    'credit_card',
    'alipay',
    'wechat',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account?.name ?? '');
    _initialBalanceController = TextEditingController(
      text: widget.account?.initialBalance != null &&
              widget.account!.initialBalance != 0.0
          ? widget.account!.initialBalance.toStringAsFixed(2)
          : '',
    );
    _selectedType = widget.account?.type ?? 'cash';
    _selectedCurrency = widget.account?.currency ?? 'CNY';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _initialBalanceController.dispose();
    super.dispose();
  }

  bool get isEditing => widget.account != null;

  /// v1.15.0: 检查账户名称是否重复
  Future<void> _checkNameDuplicate(String name) async {
    if (name.trim().isEmpty) {
      setState(() {
        _isNameDuplicate = false;
        _nameErrorText = null;
      });
      return;
    }

    final repo = ref.read(repositoryProvider);
    final allAccounts = await repo.getAllAccounts();
    final isDuplicate = allAccounts.any((account) {
      // 如果是编辑模式，排除当前账户本身
      if (isEditing && account.id == widget.account!.id) {
        return false;
      }
      return account.name == name.trim();
    });

    if (mounted) {
      setState(() {
        _isNameDuplicate = isDuplicate;
        _nameErrorText = isDuplicate
            ? AppLocalizations.of(context).accountNameDuplicate
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: isEditing ? l10n.accountEditTitle : l10n.accountNewTitle,
            showBack: true,
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.0.scaled(context, ref),
                  vertical: 8.0.scaled(context, ref),
                ),
                children: [
                  // 账户名称
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(16.0.scaled(context, ref)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.accountNameLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textPrimary(context),
                            ),
                          ),
                          SizedBox(height: 12.0.scaled(context, ref)),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: l10n.accountNameHint,
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              errorText: _nameErrorText,
                              errorStyle: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                              border: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _isNameDuplicate
                                      ? Colors.red
                                      : Colors.grey[300]!,
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _isNameDuplicate ? Colors.red : primaryColor,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 8.0.scaled(context, ref),
                              ),
                            ),
                            style: const TextStyle(fontSize: 16),
                            onChanged: (value) {
                              _checkNameDuplicate(value);
                            },
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.accountNameRequired;
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 8.0.scaled(context, ref)),

                  // 账户类型
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(16.0.scaled(context, ref)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.accountTypeLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textPrimary(context),
                            ),
                          ),
                          SizedBox(height: 16.0.scaled(context, ref)),
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12.0.scaled(context, ref),
                            crossAxisSpacing: 12.0.scaled(context, ref),
                            childAspectRatio: 1.2,
                            children: accountTypes.map((type) {
                              final isSelected = _selectedType == type;
                              return _AccountTypeCard(
                                type: type,
                                label: getAccountTypeLabel(context, type),
                                isSelected: isSelected,
                                primaryColor: primaryColor,
                                onTap: () {
                                  setState(() {
                                    _selectedType = type;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 8.0.scaled(context, ref)),

                  // v1.15.0: 币种选择
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: AppListTile(
                      leading: Icons.monetization_on_outlined,
                      title: l10n.ledgersCurrency,
                      subtitle: displayCurrency(_selectedCurrency, context),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        // 检查是否有交易记录
                        if (isEditing) {
                          final repo = ref.read(repositoryProvider);
                          final hasTransactions = await repo.hasTransactions(widget.account!.id);
                          if (hasTransactions) {
                            if (!mounted) return;
                            await AppDialog.info(
                              context,
                              title: l10n.commonNotice,
                              message: l10n.accountCurrencyLocked,
                            );
                            return;
                          }
                        }

                        if (!mounted) return;
                        final picked = await _showCurrencyPicker(context, initial: _selectedCurrency);
                        if (picked != null) {
                          setState(() => _selectedCurrency = picked);
                        }
                      },
                    ),
                  ),

                  SizedBox(height: 8.0.scaled(context, ref)),

                  // 初始资金
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(16.0.scaled(context, ref)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.accountInitialBalance,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textPrimary(context),
                            ),
                          ),
                          SizedBox(height: 12.0.scaled(context, ref)),
                          TextFormField(
                            controller: _initialBalanceController,
                            decoration: InputDecoration(
                              hintText: l10n.accountInitialBalanceHint,
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              prefixText: '${getCurrencySymbol(_selectedCurrency)} ',
                              prefixStyle: TextStyle(
                                fontSize: 16,
                                color: BeeTokens.textPrimary(context),
                              ),
                              border: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: primaryColor, width: 2),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 8.0.scaled(context, ref),
                              ),
                            ),
                            style: const TextStyle(fontSize: 16),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            validator: (value) {
                              if (value != null && value.trim().isNotEmpty) {
                                final parsed = double.tryParse(value.trim());
                                if (parsed == null) {
                                  return '请输入有效的金额';
                                }
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.0.scaled(context, ref)),

                  // 保存按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48.0.scaled(context, ref),
                    child: ElevatedButton(
                      onPressed: (_saving || _isNameDuplicate) ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[400],
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(8.0.scaled(context, ref)),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              l10n.commonSave,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  // 删除按钮（仅编辑时显示）
                  if (isEditing) ...[
                    SizedBox(height: 12.0.scaled(context, ref)),
                    SizedBox(
                      width: double.infinity,
                      height: 48.0.scaled(context, ref),
                      child: OutlinedButton(
                        onPressed: _saving ? null : _delete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                8.0.scaled(context, ref)),
                          ),
                        ),
                        child: Text(
                          l10n.commonDelete,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final repo = ref.read(repositoryProvider);
      final name = _nameController.text.trim();
      final initialBalanceText = _initialBalanceController.text.trim();
      final initialBalance =
          initialBalanceText.isEmpty ? 0.0 : double.parse(initialBalanceText);

      if (isEditing) {
        // 检查币种是否变化
        String? currencyToUpdate;
        if (_selectedCurrency != widget.account!.currency) {
          // 币种变化了，需要再次检查是否有交易
          final hasTransactions = await repo.hasTransactions(widget.account!.id);
          if (hasTransactions) {
            if (mounted) {
              setState(() => _saving = false);
              final l10n = AppLocalizations.of(context);
              await AppDialog.info(
                context,
                title: l10n.commonNotice,
                message: l10n.accountCurrencyLocked,
              );
            }
            return;
          }
          currencyToUpdate = _selectedCurrency;
        }

        await repo.updateAccount(
          widget.account!.id,
          name: name,
          type: _selectedType,
          currency: currencyToUpdate,
          initialBalance: initialBalance,
        );
      } else {
        await repo.createAccount(
          ledgerId: widget.ledgerId,
          name: name,
          type: _selectedType,
          currency: _selectedCurrency,
          initialBalance: initialBalance,
        );
      }

      // 触发账本同步(后台异步,不阻塞页面关闭)
      if (mounted) {
        PostProcessor.sync(ref, ledgerId: widget.ledgerId);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '${AppLocalizations.of(context).commonError}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);

    // 检查是否有关联交易
    final repo = ref.read(repositoryProvider);
    final txCount = await repo.getTransactionCountByAccount(widget.account!.id);

    if (txCount > 0) {
      // 有关联交易，提示用户
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.accountDeleteWarningTitle),
          content: Text(l10n.accountDeleteWarningMessage(txCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.commonDelete),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    } else {
      // 没有关联交易，简单确认
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.commonConfirm),
          content: Text(l10n.accountDeleteConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.commonDelete),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    setState(() => _saving = true);

    try {
      await repo.deleteAccount(widget.account!.id);

      // 触发账本同步(后台异步,不阻塞页面关闭)
      if (mounted) {
        PostProcessor.sync(ref, ledgerId: widget.ledgerId);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '${l10n.commonError}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// 显示币种选择器（复用账本页面的实现）
  Future<String?> _showCurrencyPicker(BuildContext context, {String? initial}) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceElevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bctx) {
        String query = '';
        String? selected = initial;
        return StatefulBuilder(builder: (sctx, setState) {
          final filtered = getCurrencies(context).where((c) {
            final q = query.trim();
            if (q.isEmpty) return true;
            final uq = q.toUpperCase();
            return c.code.contains(uq) || c.name.contains(q);
          }).toList();

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 16 + MediaQuery.of(bctx).viewInsets.bottom,
            ),
            child: SizedBox(
              height: 420,
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    AppLocalizations.of(bctx).ledgersSelectCurrency,
                    style: Theme.of(bctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: AppLocalizations.of(bctx).ledgersSearchCurrency,
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final sel = c.code == selected;
                        return ListTile(
                          title: Text('${c.name} (${c.code})'),
                          trailing: sel
                              ? const Icon(Icons.check, color: Colors.black)
                              : null,
                          onTap: () => Navigator.pop(bctx, c.code),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
}

/// 账户类型选择卡片
class _AccountTypeCard extends ConsumerWidget {
  final String type;
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _AccountTypeCard({
    required this.type,
    required this.label,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
      child: Container(
        decoration: BoxDecoration(
          color:
              isSelected ? primaryColor.withValues(alpha: 0.12) : BeeTokens.surfaceElevated(context),
          border: Border.all(
            color: isSelected ? primaryColor : BeeTokens.border(context),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AccountTypeIcon(
              type: type,
              size: 28.0.scaled(context, ref),
            ),
            SizedBox(height: 8.0.scaled(context, ref)),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? primaryColor : BeeTokens.textSecondary(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
