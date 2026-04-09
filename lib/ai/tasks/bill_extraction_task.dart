import 'package:flutter_ai_kit/flutter_ai_kit.dart';

/// 账单提取任务
///
/// 从OCR文本中提取账单信息
class BillExtractionTask extends AITask<String, BillInfo> {
  @override
  String get taskType => 'bill_extraction';

  @override
  final String input;

  BillExtractionTask(this.input);

  @override
  Map<String, dynamic> toJson() => {
        'task_type': taskType,
        'ocr_text': input,
      };
}

/// 账单信息
class BillInfo {
  /// 金额
  final double? amount;

  /// 时间
  final DateTime? time;

  /// 备注
  final String? note;

  /// 分类
  final String? category;

  /// 类型（收入/支出）
  final BillType? type;

  /// 账户名称
  final String? account;

  /// 转账来源账户名称（可选）
  final String? fromAccount;

  /// 转账目标账户名称（可选）
  final String? toAccount;

  /// 标签列表（可选）
  final List<String>? tags;

  /// 账本ID
  final int? ledgerId;

  /// 置信度 (0.0 - 1.0)
  final double confidence;

  const BillInfo({
    this.amount,
    this.time,
    this.note,
    this.category,
    this.type,
    this.account,
    this.fromAccount,
    this.toAccount,
    this.tags,
    this.ledgerId,
    this.confidence = 0.0,
  });

  /// 是否包含完整信息
  bool get isComplete => amount != null && time != null;

  /// 从JSON创建
  factory BillInfo.fromJson(Map<String, dynamic> json) {
    return BillInfo(
      amount: json['amount']?.toDouble(),
      time: json['time'] != null ? DateTime.tryParse(json['time']) : null,
      note: json['note'] ?? json['merchant'], // 兼容旧数据
      category: json['category'],
      type: json['type'] != null ? _parseBillType(json['type']) : null,
      account: json['account'],
      fromAccount: json['from_account'] ?? json['fromAccount'],
      toAccount: json['to_account'] ?? json['toAccount'],
      tags: _parseTags(json['tags'] ?? json['tag']),
      ledgerId: json['ledgerId'],
      confidence: json['confidence']?.toDouble() ?? 0.8,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() => {
        'amount': amount,
        'time': time?.toIso8601String(),
        'note': note,
        'category': category,
        'type': type?.toString().split('.').last,
        'account': account,
        'from_account': fromAccount,
        'to_account': toAccount,
        'tags': tags,
        'ledgerId': ledgerId,
        'confidence': confidence,
      };

  static BillType? _parseBillType(dynamic value) {
    if (value == null) return null;
    final str = value.toString().toLowerCase();
    if (str.contains('income') || str == '收入') return BillType.income;
    if (str.contains('expense') || str == '支出') return BillType.expense;
    if (str.contains('transfer') || str == '转账' || str == '轉帳') {
      return BillType.transfer;
    }
    return null;
  }

  static List<String>? _parseTags(dynamic value) {
    if (value == null) return null;

    final tags = <String>[];

    if (value is String) {
      tags.addAll(value
          .split(RegExp(r'[,\n，、;；|]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty));
    } else if (value is List) {
      tags.addAll(value
          .map((item) => item.toString().trim())
          .where((s) => s.isNotEmpty));
    }

    return tags.isEmpty ? null : tags;
  }

  @override
  String toString() {
    return 'BillInfo(amount: $amount, time: $time, note: $note, category: $category, type: $type, account: $account, fromAccount: $fromAccount, toAccount: $toAccount, tags: $tags)';
  }
}

/// 账单类型
enum BillType {
  /// 收入
  income,

  /// 支出
  expense,

  /// 转账
  transfer,
}
