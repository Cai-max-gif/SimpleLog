import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../../providers/credit_card_reminder_providers.dart';

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
  late final TextEditingController _creditLimitController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _cardLastFourController;
  late final TextEditingController _noteController;
  late String _selectedType;
  late String _selectedCurrency;
  int? _billingDay;
  int? _paymentDueDay;
  bool _reminderEnabled = false;
  int _reminderDaysBefore = 3;
  bool _saving = false;
  bool _isNameDuplicate = false;
  String? _nameErrorText;

  // 可交易账户类型
  static const List<String> tradableAccountTypes = [
    'cash',
    'bank_card',
    'credit_card',
    'alipay',
    'wechat',
    'other',
  ];

  // 估值账户类型
  static const List<String> valuationAccountTypes = [
    'real_estate',
    'vehicle',
    'investment',
    'insurance',
    'social_fund',
    'loan',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account?.name ?? '');
    _initialBalanceController = TextEditingController(
      text: widget.account?.initialBalance != null &&
              widget.account!.initialBalance != 0.0
          ? widget.account!.initialBalance.abs().toStringAsFixed(2)
          : '',
    );
    _creditLimitController = TextEditingController(
      text: widget.account?.creditLimit != null
          ? widget.account!.creditLimit!.toStringAsFixed(2)
          : '',
    );
    _bankNameController = TextEditingController(text: widget.account?.bankName ?? '');
    _cardLastFourController = TextEditingController(text: widget.account?.cardLastFour ?? '');
    _noteController = TextEditingController(text: widget.account?.note ?? '');
    _selectedType = widget.account?.type ?? 'cash';
    _selectedCurrency = widget.account?.currency ?? 'CNY';
    _billingDay = widget.account?.billingDay;
    _paymentDueDay = widget.account?.paymentDueDay;
    _loadReminderSettings();
  }

  Future<void> _loadReminderSettings() async {
    if (widget.account != null) {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('cc_reminder_enabled_${widget.account!.id}') ?? false;
      final daysBefore = prefs.getInt('cc_reminder_days_${widget.account!.id}') ?? 3;
      if (mounted) {
        setState(() {
          _reminderEnabled = enabled;
          _reminderDaysBefore = daysBefore;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _initialBalanceController.dispose();
    _creditLimitController.dispose();
    _bankNameController.dispose();
    _cardLastFourController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get isEditing => widget.account != null;

  String _getInitialBalanceLabel(AppLocalizations l10n) {
    if (isValuationOnlyType(_selectedType)) {
      return isLiabilityType(_selectedType)
          ? l10n.valuationCurrentDebt
          : l10n.valuationCurrentValue;
    }
    return l10n.accountInitialBalance;
  }

  String _getInitialBalanceHint(AppLocalizations l10n) {
    if (isValuationOnlyType(_selectedType)) {
      return isLiabilityType(_selectedType)
          ? l10n.valuationDebtHint
          : l10n.valuationAccountHint;
    }
    switch (_selectedType) {
      case 'credit_card':
        return l10n.creditCardInitialBalanceHint;
      default:
        return l10n.accountInitialBalanceHint;
    }
  }

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
                padding: EdgeInsets.only(
                  left: 12.0.scaled(context, ref),
                  right: 12.0.scaled(context, ref),
                  top: 8.0.scaled(context, ref),
                  bottom: 8.0.scaled(context, ref) + MediaQuery.of(context).padding.bottom,
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
                            l10n.accountGroupTradable,
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
                            children: tradableAccountTypes.map((type) {
                              final isSelected = _selectedType == type;
                              // 编辑模式下，如果当前是估值账户则禁止选择可交易类型
                              final disabled = isEditing && isValuationOnlyType(widget.account!.type);
                              return _AccountTypeCard(
                                type: type,
                                label: getAccountTypeLabel(context, type),
                                isSelected: isSelected,
                                primaryColor: primaryColor,
                                disabled: disabled,
                                onTap: disabled ? () {} : () {
                                  setState(() {
                                    final oldType = _selectedType;
                                    _selectedType = type;
                                    // 离开信用卡类型时清空信用卡字段
                                    if (oldType == 'credit_card' && type != 'credit_card') {
                                      _creditLimitController.clear();
                                      _billingDay = null;
                                      _paymentDueDay = null;
                                      _reminderEnabled = false;
                                    }
                                    // 离开银行卡/信用卡类型时清空元信息字段
                                    final wasBankOrCredit = oldType == 'bank_card' || oldType == 'credit_card';
                                    final isBankOrCredit = type == 'bank_card' || type == 'credit_card';
                                    if (wasBankOrCredit && !isBankOrCredit) {
                                      _bankNameController.clear();
                                      _cardLastFourController.clear();
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          SizedBox(height: 20.0.scaled(context, ref)),
                          Text(
                            l10n.accountGroupValuation,
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
                            children: valuationAccountTypes.map((type) {
                              final isSelected = _selectedType == type;
                              // 编辑模式下，如果当前是可交易账户则禁止选择估值类型
                              final disabled = isEditing && isTradableType(widget.account!.type);
                              return _AccountTypeCard(
                                type: type,
                                label: getAccountTypeLabel(context, type),
                                isSelected: isSelected,
                                primaryColor: primaryColor,
                                disabled: disabled,
                                onTap: disabled ? () {} : () {
                                  setState(() {
                                    _selectedType = type;
                                    // 清空不相关字段
                                    _creditLimitController.clear();
                                    _billingDay = null;
                                    _paymentDueDay = null;
                                    _reminderEnabled = false;
                                    _bankNameController.clear();
                                    _cardLastFourController.clear();
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
                            _getInitialBalanceLabel(l10n),
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
                              hintText: _getInitialBalanceHint(l10n),
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
                                decimal: true, signed: true),
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

                  // 信用卡设置（仅信用卡类型显示）
                  if (_selectedType == 'credit_card') ...[
                    SizedBox(height: 8.0.scaled(context, ref)),
                    SectionCard(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(16.0.scaled(context, ref)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.creditCardSettings,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                            SizedBox(height: 12.0.scaled(context, ref)),
                            // 信用额度
                            TextFormField(
                              controller: _creditLimitController,
                              decoration: InputDecoration(
                                labelText: l10n.creditLimit,
                                hintText: l10n.creditLimitHint,
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                prefixText: '${getCurrencySymbol(_selectedCurrency)} ',
                                prefixStyle: TextStyle(
                                  fontSize: 16,
                                  color: BeeTokens.textPrimary(context),
                                ),
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: primaryColor, width: 2),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8.0.scaled(context, ref),
                                ),
                              ),
                              style: const TextStyle(fontSize: 16),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                if (value != null && value.trim().isNotEmpty) {
                                  final parsed = double.tryParse(value.trim());
                                  if (parsed == null || parsed < 0) {
                                    return '请输入有效的额度';
                                  }
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 16.0.scaled(context, ref)),
                            // 账单日
                            _DayPickerTile(
                              label: l10n.billingDay,
                              value: _billingDay,
                              primaryColor: primaryColor,
                              onChanged: (day) => setState(() => _billingDay = day),
                            ),
                            SizedBox(height: 8.0.scaled(context, ref)),
                            // 还款日
                            _DayPickerTile(
                              label: l10n.paymentDueDay,
                              value: _paymentDueDay,
                              primaryColor: primaryColor,
                              onChanged: (day) => setState(() => _paymentDueDay = day),
                            ),
                            SizedBox(height: 12.0.scaled(context, ref)),
                            // 还款提醒
                            Divider(color: BeeTokens.divider(context)),
                            SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                l10n.creditCardReminderTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: BeeTokens.textPrimary(context),
                                ),
                              ),
                              subtitle: Text(
                                l10n.creditCardReminderDesc,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: BeeTokens.textTertiary(context),
                                ),
                              ),
                              value: _reminderEnabled,
                              activeColor: primaryColor,
                              onChanged: (value) => setState(() => _reminderEnabled = value),
                            ),
                            if (_reminderEnabled) ...[
                              SizedBox(height: 4.0.scaled(context, ref)),
                              Wrap(
                                spacing: 8.0.scaled(context, ref),
                                children: [1, 3, 5, 7].map((days) {
                                  final isSelected = _reminderDaysBefore == days;
                                  return ChoiceChip(
                                    label: Text(l10n.creditCardReminderDaysBefore(days)),
                                    selected: isSelected,
                                    selectedColor: primaryColor.withValues(alpha: 0.15),
                                    labelStyle: TextStyle(
                                      fontSize: 12,
                                      color: isSelected ? primaryColor : BeeTokens.textSecondary(context),
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                    onSelected: (_) => setState(() => _reminderDaysBefore = days),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 元信息（银行卡/信用卡：开户行+卡号后四位；所有类型：备注）
                  if (_selectedType == 'bank_card' || _selectedType == 'credit_card') ...[
                    SizedBox(height: 8.0.scaled(context, ref)),
                    SectionCard(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(16.0.scaled(context, ref)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.accountMetaInfo,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                            SizedBox(height: 12.0.scaled(context, ref)),
                            TextFormField(
                              controller: _bankNameController,
                              decoration: InputDecoration(
                                labelText: l10n.accountBankName,
                                hintText: l10n.accountBankNameHint,
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: primaryColor, width: 2),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8.0.scaled(context, ref),
                                ),
                              ),
                              style: const TextStyle(fontSize: 16),
                            ),
                            SizedBox(height: 12.0.scaled(context, ref)),
                            TextFormField(
                              controller: _cardLastFourController,
                              decoration: InputDecoration(
                                labelText: l10n.accountCardLastFour,
                                hintText: l10n.accountCardLastFourHint,
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: primaryColor, width: 2),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8.0.scaled(context, ref),
                                ),
                              ),
                              style: const TextStyle(fontSize: 16),
                              maxLength: 4,
                              keyboardType: TextInputType.number,
                            ),
                            SizedBox(height: 8.0.scaled(context, ref)),
                            TextFormField(
                              controller: _noteController,
                              decoration: InputDecoration(
                                labelText: l10n.accountNote,
                                hintText: l10n.accountNoteHint,
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: primaryColor, width: 2),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8.0.scaled(context, ref),
                                ),
                              ),
                              style: const TextStyle(fontSize: 16),
                              maxLines: 3,
                              minLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // 非银行卡/信用卡类型：仅备注
                    SizedBox(height: 8.0.scaled(context, ref)),
                    SectionCard(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(16.0.scaled(context, ref)),
                        child: TextFormField(
                          controller: _noteController,
                          decoration: InputDecoration(
                            labelText: l10n.accountNote,
                            hintText: l10n.accountNoteHint,
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: primaryColor, width: 2),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 8.0.scaled(context, ref),
                            ),
                          ),
                          style: const TextStyle(fontSize: 16),
                          maxLines: 3,
                          minLines: 1,
                        ),
                      ),
                    ),
                  ],

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
      var initialBalance =
          initialBalanceText.isEmpty ? 0.0 : double.parse(initialBalanceText);

      // 贷款类型：用户输入正数，存储为负数
      if (_selectedType == 'loan' && initialBalance > 0) {
        initialBalance = -initialBalance;
      }

      // 信用卡字段
      final isCreditCard = _selectedType == 'credit_card';
      final creditLimitText = _creditLimitController.text.trim();
      final creditLimit = isCreditCard && creditLimitText.isNotEmpty
          ? double.parse(creditLimitText)
          : null;

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

        // 如果从信用卡切换到其他类型，清空信用卡字段
        final wasCreditCard = widget.account!.type == 'credit_card';
        final clearCreditCardFields = wasCreditCard && !isCreditCard;

        // 元信息字段
        final isBankOrCredit = _selectedType == 'bank_card' || _selectedType == 'credit_card';
        final wasBankOrCredit = widget.account!.type == 'bank_card' || widget.account!.type == 'credit_card';
        final clearMetadataFields = wasBankOrCredit && !isBankOrCredit;
        final bankName = isBankOrCredit ? _bankNameController.text.trim() : null;
        final cardLastFour = isBankOrCredit ? _cardLastFourController.text.trim() : null;
        final noteText = _noteController.text.trim();

        await repo.updateAccount(
          widget.account!.id,
          name: name,
          type: _selectedType,
          currency: currencyToUpdate,
          initialBalance: initialBalance,
          creditLimit: isCreditCard ? creditLimit : null,
          billingDay: isCreditCard ? _billingDay : null,
          paymentDueDay: isCreditCard ? _paymentDueDay : null,
          clearCreditCardFields: clearCreditCardFields,
          bankName: bankName != null && bankName.isNotEmpty ? bankName : null,
          cardLastFour: cardLastFour != null && cardLastFour.isNotEmpty ? cardLastFour : null,
          note: noteText.isNotEmpty ? noteText : null,
          clearMetadataFields: clearMetadataFields,
        );

        // 保存还款提醒设置
        if (isCreditCard) {
          await _saveReminderSettings(widget.account!.id);
        }
      } else {
        final isBankOrCredit = _selectedType == 'bank_card' || _selectedType == 'credit_card';
        final bankNameText = isBankOrCredit ? _bankNameController.text.trim() : null;
        final cardLastFourText = isBankOrCredit ? _cardLastFourController.text.trim() : null;
        final noteText = _noteController.text.trim();

        final id = await repo.createAccount(
          ledgerId: widget.ledgerId,
          name: name,
          type: _selectedType,
          currency: _selectedCurrency,
          initialBalance: initialBalance,
          creditLimit: creditLimit,
          billingDay: isCreditCard ? _billingDay : null,
          paymentDueDay: isCreditCard ? _paymentDueDay : null,
          bankName: bankNameText != null && bankNameText.isNotEmpty ? bankNameText : null,
          cardLastFour: cardLastFourText != null && cardLastFourText.isNotEmpty ? cardLastFourText : null,
          note: noteText.isNotEmpty ? noteText : null,
        );

        // 保存还款提醒设置
        if (isCreditCard) {
          await _saveReminderSettings(id);
        }
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

  Future<void> _saveReminderSettings(int accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cc_reminder_enabled_$accountId', _reminderEnabled);
    await prefs.setInt('cc_reminder_days_$accountId', _reminderDaysBefore);

    // 调度或取消提醒
    if (_reminderEnabled && _paymentDueDay != null) {
      await CreditCardReminderService.scheduleReminder(
        accountId: accountId,
        accountName: _nameController.text.trim(),
        paymentDueDay: _paymentDueDay!,
        daysBefore: _reminderDaysBefore,
      );
    } else {
      await CreditCardReminderService.cancelReminder(accountId);
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

/// 日期选择行（1-28）
class _DayPickerTile extends ConsumerWidget {
  final String label;
  final int? value;
  final Color primaryColor;
  final ValueChanged<int?> onChanged;

  const _DayPickerTile({
    required this.label,
    required this.value,
    required this.primaryColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: () => _showDayPicker(context, l10n),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0.scaled(context, ref)),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: BeeTokens.textPrimary(context),
              ),
            ),
            const Spacer(),
            Text(
              value != null ? l10n.dayOfMonth(value!) : l10n.selectDay,
              style: TextStyle(
                fontSize: 14,
                color: value != null
                    ? BeeTokens.textPrimary(context)
                    : BeeTokens.textTertiary(context),
              ),
            ),
            SizedBox(width: 4.0.scaled(context, ref)),
            Icon(
              Icons.chevron_right,
              size: 18.0.scaled(context, ref),
              color: BeeTokens.iconTertiary(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showDayPicker(BuildContext context, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: BeeTokens.surfaceElevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  label,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: 28,
                  itemBuilder: (_, index) {
                    final day = index + 1;
                    final isSelected = day == value;
                    return GestureDetector(
                      onTap: () {
                        onChanged(day);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? primaryColor
                                : BeeTokens.border(ctx),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : BeeTokens.textPrimary(ctx),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
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
  final bool disabled;

  const _AccountTypeCard({
    required this.type,
    required this.label,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveOpacity = disabled ? 0.4 : 1.0;
    return Opacity(
      opacity: effectiveOpacity,
      child: InkWell(
        onTap: disabled ? null : onTap,
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
      ),
    );
  }
}
