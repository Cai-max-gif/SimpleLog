/// 账本展示项模型
///
/// 纯数据模型，不包含同步状态（同步状态通过 syncStatusProvider 单独获取）
library;

/// 账本展示项（纯数据，不含同步状态）
class LedgerDisplayItem {
  /// 账本ID（本地或远程）
  final int id;

  /// 账本名称
  final String name;

  /// 货币代码
  final String currency;

  /// 账单数量
  final int transactionCount;

  /// 账本余额（总收入 - 总支出）
  final double balance;

  /// 最后更新时间
  final DateTime lastUpdated;

  /// 是否为仅远程账本（本地不存在）
  final bool isRemoteOnly;

  const LedgerDisplayItem({
    required this.id,
    required this.name,
    required this.currency,
    required this.transactionCount,
    required this.balance,
    required this.lastUpdated,
    this.isRemoteOnly = false,
  });

  /// 从本地账本创建
  factory LedgerDisplayItem.fromLocal({
    required int id,
    required String name,
    required String currency,
    required DateTime createdAt,
    required int transactionCount,
    required double balance,
  }) {
    return LedgerDisplayItem(
      id: id,
      name: name,
      currency: currency,
      transactionCount: transactionCount,
      balance: balance,
      lastUpdated: createdAt,
      isRemoteOnly: false,
    );
  }

  /// 从远程索引创建
  factory LedgerDisplayItem.fromRemote({
    required int remoteId,
    required String name,
    required String currency,
    required DateTime updatedAt,
    required int transactionCount,
    required double balance,
  }) {
    return LedgerDisplayItem(
      id: remoteId,
      name: name,
      currency: currency,
      transactionCount: transactionCount,
      balance: balance,
      lastUpdated: updatedAt,
      isRemoteOnly: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedgerDisplayItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isRemoteOnly == other.isRemoteOnly;

  @override
  int get hashCode => id.hashCode ^ isRemoteOnly.hashCode;

  @override
  String toString() =>
      'LedgerDisplayItem(id: $id, name: $name, isRemoteOnly: $isRemoteOnly)';
}
