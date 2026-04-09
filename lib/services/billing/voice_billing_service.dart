import 'dart:io';
import '../../ai/tasks/bill_extraction_task.dart';
import '../system/logger_service.dart';
import '../ai/bill_extraction_service.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/db.dart';

/// 语音识别结果
class VoiceRecognitionResult {
  final String recognizedText; // 识别的文字
  final BillInfo? billInfo; // 提取的账单信息

  VoiceRecognitionResult({
    required this.recognizedText,
    this.billInfo,
  });
}

/// 语音记账服务
///
/// 使用 AI 从语音提取账单信息
class VoiceBillingService {
  /// 步骤1：将语音转为文字（快速）
  Future<String> convertVoiceToText(File audioFile) async {
    final service = BillExtractionService();
    final text = await service.speechToText(audioFile);

    if (text == null) {
      throw Exception('语音识别失败，请检查 AI 配置');
    }

    return text;
  }

  /// 步骤2：从文字提取账单信息（较慢）
  Future<BillInfo?> extractBillFromText(
    String text, {
    required BaseRepository repository,
    required BeeDatabase db,
    required int ledgerId,
  }) async {
    try {
      // 获取可用分类列表（排除有子分类的父分类，只获取叶子分类）
      final expenseCategories = await repository.getUsableCategories('expense');
      final incomeCategories = await repository.getUsableCategories('income');
      final expenseCategoryNames = expenseCategories.map((c) => c.name).toList();
      final incomeCategoryNames = incomeCategories.map((c) => c.name).toList();

      // 获取账本信息以确定币种
      final ledger = await repository.getLedgerById(ledgerId);

      // 获取与账本币种相同的账户
      List<String> accountNames = [];
      if (ledger != null) {
        final allAccounts = await repository.getAllAccounts();
        final matchingAccounts = allAccounts
            .where((a) => a.currency == ledger.currency)
            .toList();
        accountNames = matchingAccounts.map((a) => a.name).toList();
      }

      // 使用新的 BillExtractionService
      final service = BillExtractionService(
        expenseCategories: expenseCategoryNames,
        incomeCategories: incomeCategoryNames,
        accounts: accountNames,
      );
      await service.init();

      final billInfo = await service.extractFromText(text);

      if (billInfo != null) {
        logger.info('VoiceBilling', '账单提取成功: ${billInfo.category ?? "未识别"}');
      } else {
        logger.warning('VoiceBilling', '账单提取失败');
      }

      return billInfo;
    } catch (e, stackTrace) {
      logger.error('VoiceBilling', '提取账单信息失败', e, stackTrace);
      rethrow;
    }
  }

  /// 识别语音并提取账单信息（完整流程）
  ///
  /// [audioFile] 录音文件
  /// [repository] 数据库仓库（用于查询账户）
  /// [db] 数据库实例
  /// [ledgerId] 账本ID
  ///
  /// 返回包含识别文字和账单信息的结果
  Future<VoiceRecognitionResult> recognizeVoiceForBilling(
    File audioFile, {
    required BaseRepository repository,
    required BeeDatabase db,
    required int ledgerId,
  }) async {
    logger.info('VoiceBilling', '开始语音识别记账');

    try {
      // 步骤1：语音转文字
      final recognizedText = await convertVoiceToText(audioFile);
      logger.info('VoiceBilling', '识别文字: $recognizedText');

      // 步骤2：提取账单信息
      final billInfo = await extractBillFromText(
        recognizedText,
        repository: repository,
        db: db,
        ledgerId: ledgerId,
      );

      return VoiceRecognitionResult(
        recognizedText: recognizedText,
        billInfo: billInfo,
      );
    } catch (e, stackTrace) {
      logger.error('VoiceBilling', '语音识别失败', e, stackTrace);
      rethrow;
    }
  }
}
