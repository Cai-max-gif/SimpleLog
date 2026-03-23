import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_localizations.dart';

/// 账户类型常量
const accountTypeOrder = ['cash', 'bank_card', 'credit_card', 'alipay', 'wechat', 'other'];

/// 获取账户类型的 Material 图标（备用，用于无 SVG 的场景）
IconData getIconForAccountType(String type) {
  switch (type) {
    case 'cash':
      return Icons.payments_outlined;
    case 'bank_card':
      return Icons.credit_card;
    case 'credit_card':
      return Icons.credit_score;
    case 'alipay':
      return Icons.currency_yuan;
    case 'wechat':
      return Icons.chat;
    case 'other':
      return Icons.account_balance_outlined;
    default:
      return Icons.account_balance_wallet_outlined;
  }
}

/// 获取账户类型名称
String getAccountTypeLabel(BuildContext context, String type) {
  final l10n = AppLocalizations.of(context);
  switch (type) {
    case 'cash':
      return l10n.accountTypeCash;
    case 'bank_card':
      return l10n.accountTypeBankCard;
    case 'credit_card':
      return l10n.accountTypeCreditCard;
    case 'alipay':
      return l10n.accountTypeAlipay;
    case 'wechat':
      return l10n.accountTypeWechat;
    case 'other':
      return l10n.accountTypeOther;
    default:
      return type;
  }
}

/// 获取账户类型的品牌颜色
Color getColorForAccountType(String type, Color primaryColor) {
  switch (type) {
    case 'alipay':
      return const Color(0xFF1677FF);
    case 'wechat':
      return const Color(0xFF07C160);
    case 'cash':
      return Colors.orange;
    case 'bank_card':
      return const Color(0xFF1890FF);
    case 'credit_card':
      return Colors.purple;
    default:
      return primaryColor;
  }
}

/// 获取 SVG 路径（所有类型均有彩色 SVG）
String _getSvgPath(String type) {
  switch (type) {
    case 'cash':
      return 'assets/icons/cash.svg';
    case 'bank_card':
      return 'assets/icons/bank_card.svg';
    case 'credit_card':
      return 'assets/icons/credit_card.svg';
    case 'alipay':
      return 'assets/icons/alipay.svg';
    case 'wechat':
      return 'assets/icons/wechat.svg';
    case 'other':
      return 'assets/icons/other_account.svg';
    default:
      return 'assets/icons/other_account.svg';
  }
}

/// 统一的账户类型图标 Widget
/// 所有类型均使用彩色 SVG 图标
/// 设置 [monochrome] 为 true + [color] 可将图标渲染为单色（用于渐变卡片上的白色图标）
class AccountTypeIcon extends StatelessWidget {
  final String type;
  final double size;
  final Color? color;
  /// 是否以单色模式渲染（忽略 SVG 原始颜色，统一用 [color] 着色）
  final bool monochrome;

  const AccountTypeIcon({
    super.key,
    required this.type,
    this.size = 20,
    this.color,
    this.monochrome = false,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _getSvgPath(type),
      width: size,
      height: size,
      colorFilter: monochrome && color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
    );
  }
}
