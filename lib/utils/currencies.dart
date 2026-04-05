import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class CurrencyInfo {
  final String code;
  final String name;
  const CurrencyInfo(this.code, this.name);
}

/// 货币定义：code + symbol，单一数据源
class _Def {
  final String code;
  final String symbol;
  const _Def(this.code, this.symbol);
}

/// 所有支持的货币（唯一定义处，新增货币只需在此追加）
const List<_Def> _kCurrencyDefs = [
  // 东亚
  _Def('CNY', '¥'),
  _Def('JPY', '¥'),
  _Def('KRW', '₩'),
  _Def('HKD', 'HK\$'),
  _Def('TWD', 'NT\$'),
  // 东南亚
  _Def('SGD', 'S\$'),
  _Def('MYR', 'RM'),
  _Def('THB', '฿'),
  _Def('IDR', 'Rp'),
  _Def('PHP', '₱'),
  _Def('VND', '₫'),
  _Def('MMK', 'K'),
  // 南亚
  _Def('INR', '₹'),
  _Def('PKR', '₨'),
  _Def('BDT', '৳'),
  _Def('LKR', 'Rs'),
  // 中亚
  _Def('KZT', '₸'),
  // 西亚 / 中东
  _Def('AED', 'د.إ'),
  _Def('SAR', '﷼'),
  _Def('ILS', '₪'),
  _Def('TRY', '₺'),
  // 欧洲
  _Def('EUR', '€'),
  _Def('GBP', '£'),
  _Def('CHF', 'CHF'),
  _Def('SEK', 'kr'),
  _Def('NOK', 'kr'),
  _Def('DKK', 'kr'),
  _Def('PLN', 'zł'),
  _Def('CZK', 'Kč'),
  _Def('HUF', 'Ft'),
  _Def('RUB', '₽'),
  _Def('BYN', 'Br'),
  _Def('UAH', '₴'),
  // 北美
  _Def('USD', '\$'),
  _Def('CAD', 'C\$'),
  _Def('MXN', 'MX\$'),
  // 南美
  _Def('BRL', 'R\$'),
  _Def('ARS', '\$'),
  _Def('CLP', '\$'),
  _Def('COP', '\$'),
  _Def('PEN', 'S/'),
  // 大洋洲
  _Def('AUD', 'A\$'),
  _Def('NZD', 'NZ\$'),
  // 非洲
  _Def('ZAR', 'R'),
  _Def('EGP', 'E£'),
  _Def('NGN', '₦'),
];

/// 货币代码列表（自动派生，无需手动维护）
final List<String> kCurrencyCodes =
    _kCurrencyDefs.map((d) => d.code).toList();

/// symbol 查找表（自动派生）
final Map<String, String> _symbolMap = {
  for (final d in _kCurrencyDefs) d.code: d.symbol,
};

/// 获取本地化的货币信息列表
List<CurrencyInfo> getCurrencies(BuildContext context) {
  final nameMap = _buildNameMap(context);
  return _kCurrencyDefs
      .map((d) => CurrencyInfo(d.code, nameMap[d.code] ?? d.code))
      .toList();
}

String displayCurrency(String code, BuildContext context) {
  final currencies = getCurrencies(context);
  final m = currencies.where((c) => c.code == code).toList();
  if (m.isEmpty) return code;
  return '${m.first.name} (${m.first.code})';
}

/// 获取指定货币代码的本地化名称
String getCurrencyName(String code, BuildContext context) {
  final currencies = getCurrencies(context);
  final m = currencies.where((c) => c.code == code).toList();
  if (m.isEmpty) return code;
  return m.first.name;
}

/// 获取币种符号
String getCurrencySymbol(String code) {
  return _symbolMap[code.toUpperCase()] ?? code;
}

/// l10n 名称映射（新增货币需在此和 arb 文件各加一行）
Map<String, String> _buildNameMap(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return {
    'CNY': l10n.currencyCNY,
    'JPY': l10n.currencyJPY,
    'KRW': l10n.currencyKRW,
    'HKD': l10n.currencyHKD,
    'TWD': l10n.currencyTWD,
    'SGD': l10n.currencySGD,
    'MYR': l10n.currencyMYR,
    'THB': l10n.currencyTHB,
    'IDR': l10n.currencyIDR,
    'PHP': l10n.currencyPHP,
    'VND': l10n.currencyVND,
    'MMK': l10n.currencyMMK,
    'INR': l10n.currencyINR,
    'PKR': l10n.currencyPKR,
    'BDT': l10n.currencyBDT,
    'LKR': l10n.currencyLKR,
    'KZT': l10n.currencyKZT,
    'AED': l10n.currencyAED,
    'SAR': l10n.currencySAR,
    'ILS': l10n.currencyILS,
    'TRY': l10n.currencyTRY,
    'EUR': l10n.currencyEUR,
    'GBP': l10n.currencyGBP,
    'CHF': l10n.currencyCHF,
    'SEK': l10n.currencySEK,
    'NOK': l10n.currencyNOK,
    'DKK': l10n.currencyDKK,
    'PLN': l10n.currencyPLN,
    'CZK': l10n.currencyCZK,
    'HUF': l10n.currencyHUF,
    'RUB': l10n.currencyRUB,
    'BYN': l10n.currencyBYN,
    'UAH': l10n.currencyUAH,
    'USD': l10n.currencyUSD,
    'CAD': l10n.currencyCAD,
    'MXN': l10n.currencyMXN,
    'BRL': l10n.currencyBRL,
    'ARS': l10n.currencyARS,
    'CLP': l10n.currencyCLP,
    'COP': l10n.currencyCOP,
    'PEN': l10n.currencyPEN,
    'AUD': l10n.currencyAUD,
    'NZD': l10n.currencyNZD,
    'ZAR': l10n.currencyZAR,
    'EGP': l10n.currencyEGP,
    'NGN': l10n.currencyNGN,
  };
}
