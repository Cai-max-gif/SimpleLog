import 'dart:io';

import '../../ai/tasks/bill_extraction_task.dart';
import '../system/logger_service.dart';
import 'bill_extraction_service.dart';

/// AI账单提取服务
///
/// 简化版，使用 BillExtractionService 处理所有账单提取逻辑。
class AIBillService {
  BillExtractionService? _service;
  bool _initialized = false;

  /// 初始化AI服务
  ///
  /// [expenseCategories] 支出分类列表（可选）
  /// [incomeCategories] 收入分类列表（可选）
  /// [accounts] 账户列表（可选）
  /// [imageFile] 图片文件（可选，用于Vision模型）
  Future<void> initialize({
    List<String>? expenseCategories,
    List<String>? incomeCategories,
    List<String>? accounts,
    File? imageFile,
  }) async {
    if (_initialized) return;

    _service = BillExtractionService(
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
      accounts: accounts,
    );
    await _service!.init();

    _initialized = true;
    logger.info('AIBillService', '初始化完成');
  }

  /// 提取账单信息
  ///
  /// [ocrText] OCR识别的文本
  /// [expenseCategories] 支出分类列表（可选）
  /// [incomeCategories] 收入分类列表（可选）
  /// [accounts] 账户列表（可选）
  /// [imageFile] 图片文件（可选，用于Vision模型）
  /// 返回 [BillInfo] 或 null（提取失败）
  Future<BillInfo?> extractBillInfo(
    String ocrText, {
    List<String>? expenseCategories,
    List<String>? incomeCategories,
    List<String>? accounts,
    File? imageFile,
  }) async {
    // 如果传入了新的分类/账户，重新初始化
    if (!_initialized ||
        expenseCategories != null ||
        incomeCategories != null ||
        accounts != null) {
      _initialized = false;
      await initialize(
        expenseCategories: expenseCategories,
        incomeCategories: incomeCategories,
        accounts: accounts,
        imageFile: imageFile,
      );
    }

    // 如果有图片，使用视觉模型
    if (imageFile != null) {
      return _service!.extractFromImage(imageFile);
    }

    // 否则使用文本模型
    return _service!.extractFromText(ocrText);
  }

  /// 是否已初始化
  bool get isInitialized => _initialized;
}
