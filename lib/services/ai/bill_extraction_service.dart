import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/tasks/bill_extraction_task.dart';
import '../system/logger_service.dart';
import 'ai_constants.dart';
import 'ai_provider_factory.dart';

/// 账单提取服务
///
/// 统一处理账单提取业务逻辑，支持三种输入源：
/// - 文本（OCR 识别结果、手动输入）
/// - 图片（支付截图）
/// - 语音（语音记账）
class BillExtractionService {
  static const String _tag = 'BillExtraction';

  /// 支出分类列表
  final List<String>? expenseCategories;

  /// 收入分类列表
  final List<String>? incomeCategories;

  /// 账户列表
  final List<String>? accounts;

  /// 用户自定义提示词模板
  String? _customPromptTemplate;

  BillExtractionService({
    this.expenseCategories,
    this.incomeCategories,
    this.accounts,
  });

  /// 初始化（加载用户配置）
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _customPromptTemplate = prefs.getString(AIConstants.keyAiCustomPrompt);
  }

  // ============================================================
  // 公开 API
  // ============================================================

  /// 从文本提取账单信息
  ///
  /// [text] OCR 识别文本或用户输入
  Future<BillInfo?> extractFromText(String text) async {
    if (text.trim().isEmpty) {
      logger.warning(_tag, '输入文本为空');
      return null;
    }

    try {
      final prompt = _buildPrompt(
        inputSource: '从以下支付账单文本中',
        ocrText: text,
      );

      logger.debug(_tag, '提取文本账单，prompt长度: ${prompt.length}');

      final response = await AIProviderFactory.chat(
        prompt,
        temperature: 0.3,
        logTag: _tag,
      );

      return _parseResponse(response);
    } on AIException catch (e) {
      logger.warning(_tag, '文本账单提取失败: ${e.message}');
      return null;
    } catch (e, st) {
      logger.error(_tag, '文本账单提取异常', e, st);
      return null;
    }
  }

  /// 从图片提取账单信息
  ///
  /// [image] 支付截图文件
  Future<BillInfo?> extractFromImage(File image) async {
    if (!await image.exists()) {
      logger.warning(_tag, '图片文件不存在');
      return null;
    }

    try {
      final prompt = _buildPrompt(
        inputSource: '分析支付账单截图，从中',
        ocrText: '',
      );

      logger.debug(_tag, '提取图片账单，prompt长度: ${prompt.length}');

      final response = await AIProviderFactory.vision(
        image,
        prompt,
        logTag: _tag,
      );

      return _parseResponse(response);
    } on AIException catch (e) {
      logger.warning(_tag, '图片账单提取失败: ${e.message}');
      return null;
    } catch (e, st) {
      logger.error(_tag, '图片账单提取异常', e, st);
      return null;
    }
  }

  /// 从语音提取账单信息
  ///
  /// [audio] 录音文件
  /// 两步流程：语音转文字 → 文本提取账单
  Future<(BillInfo? bill, String? recognizedText)> extractFromVoice(
    File audio,
  ) async {
    if (!await audio.exists()) {
      logger.warning(_tag, '音频文件不存在');
      return (null, null);
    }

    try {
      // 步骤1：语音转文字
      logger.info(_tag, '步骤1: 语音转文字');
      final recognizedText = await AIProviderFactory.speechToText(
        audio,
        logTag: _tag,
      );
      logger.info(_tag, '识别结果: $recognizedText');

      if (recognizedText.trim().isEmpty) {
        logger.warning(_tag, '语音识别结果为空');
        return (null, null);
      }

      // 步骤2：从文字提取账单
      logger.info(_tag, '步骤2: 提取账单信息');
      final billInfo = await extractFromText(recognizedText);

      return (billInfo, recognizedText);
    } on AIException catch (e) {
      logger.warning(_tag, '语音账单提取失败: ${e.message}');
      return (null, null);
    } catch (e, st) {
      logger.error(_tag, '语音账单提取异常', e, st);
      return (null, null);
    }
  }

  /// 仅语音转文字（不提取账单）
  ///
  /// [audio] 录音文件
  Future<String?> speechToText(File audio) async {
    if (!await audio.exists()) {
      logger.warning(_tag, '音频文件不存在');
      return null;
    }

    try {
      final text = await AIProviderFactory.speechToText(audio, logTag: _tag);
      return text.trim().isEmpty ? null : text;
    } on AIException catch (e) {
      logger.warning(_tag, '语音转文字失败: ${e.message}');
      return null;
    } catch (e, st) {
      logger.error(_tag, '语音转文字异常', e, st);
      return null;
    }
  }

  // ============================================================
  // 常量
  // ============================================================

  /// 默认提示词模板（供外部使用，如提示词编辑页面）
  static const String defaultPromptTemplate = '''{{INPUT_SOURCE}}提取记账信息，返回JSON。

当前时间：{{CURRENT_TIME}}

{{OCR_TEXT}}

{{CATEGORIES}}{{ACCOUNTS}}

字段说明：
1. amount: 金额（支出负数，收入正数）
2. time: ISO8601格式，尽量推断时间：
   - 明确时间（如"14:30"、"2025-11-25"）→直接使用
   - 相对日期（昨天、前天、上周）→推算具体日期
   - 时间段（早上、中午、晚上）→使用合理时刻（早上09:00、中午12:00、晚上19:00）
   - 完全没提时间→使用当前时间
3. note: 备注（必须≤15字，超过则精简），提取优先级：
   - 商家/店铺名（如"星巴克"、"肯德基"）
   - 商品名称（长标题需简化，如"2025春季新款黑色斜纹格纹半身裙"→"黑色半身裙"）
   - 用户描述（如"给女儿买"）
   - 没有则留空
4. category: 从分类列表选择（转账可填"转账"）
5. type: income、expense 或 transfer
6. account: 支付账户（收入/支出可用）
7. from_account: 转出账户（仅转账可用）
8. to_account: 转入账户（仅转账可用）
9. tag/tags: 标签（可选，单个字符串或字符串数组）

示例：
输入"昨天中午吃饭50" → {"amount":-50,"time":"2025-11-24T12:00:00","category":"餐饮","type":"expense"}
输入"早上在星巴克买咖啡30" → {"amount":-30,"time":"{{CURRENT_DATE}}T09:00:00","note":"星巴克","category":"咖啡","type":"expense"}
输入"商品:2025春季新款黑色半身裙 金额:￥299" → {"amount":-299,"note":"黑色半身裙","category":"服装","type":"expense"}
输入"从建行转800到零钱包" → {"amount":800,"category":"转账","type":"transfer","from_account":"建行","to_account":"零钱包","tag":"自己"}

注意：只返回JSON，尽量推断时间不要返回null，note必须≤15字（长标题要精简）''';

  /// 构建提示词
  String _buildPrompt({
    required String inputSource,
    required String ocrText,
  }) {
    final categoryHint = _buildCategoryHint();
    final accountHint = _buildAccountHint();

    // 获取当前日期时间
    final now = DateTime.now();
    final currentDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final currentHour = now.hour.toString().padLeft(2, '0');
    final currentMinute = now.minute.toString().padLeft(2, '0');
    final currentTime = '$currentDate $currentHour:$currentMinute';

    // 使用用户自定义模板或默认模板
    final template = _customPromptTemplate ?? defaultPromptTemplate;

    // 替换变量
    return template
        .replaceAll('{{INPUT_SOURCE}}', inputSource)
        .replaceAll('{{CURRENT_TIME}}', currentTime)
        .replaceAll('{{CURRENT_DATE}}', currentDate)
        .replaceAll('{{OCR_TEXT}}', ocrText)
        .replaceAll('{{CATEGORIES}}', categoryHint)
        .replaceAll('{{ACCOUNTS}}', accountHint);
  }

  /// 构建分类提示
  String _buildCategoryHint() {
    if ((expenseCategories != null && expenseCategories!.isNotEmpty) ||
        (incomeCategories != null && incomeCategories!.isNotEmpty)) {
      final parts = <String>[];
      if (expenseCategories != null && expenseCategories!.isNotEmpty) {
        parts.add('支出：${expenseCategories!.join('、')}');
      }
      if (incomeCategories != null && incomeCategories!.isNotEmpty) {
        parts.add('收入：${incomeCategories!.join('、')}');
      }
      return '分类列表：\n${parts.join('\n')}';
    } else {
      return '分类列表：\n支出：餐饮、交通、购物、娱乐、居家、通讯、水电、医疗、教育\n收入：工资、理财、红包、奖金、报销、兼职';
    }
  }

  /// 构建账户提示
  String _buildAccountHint() {
    if (accounts != null && accounts!.isNotEmpty) {
      return '\n账户列表：${accounts!.join('、')}';
    }
    return '';
  }

  /// 解析 AI 响应
  BillInfo? _parseResponse(String response) {
    logger.debug(_tag, '原始响应: $response');

    // 提取 JSON（可能包含 ```json 包裹）
    final jsonMatch = RegExp(r'\{[\s\S]*?\}').firstMatch(response);
    if (jsonMatch == null) {
      logger.warning(_tag, '响应中没有找到JSON: $response');
      return null;
    }

    try {
      final jsonStr = jsonMatch.group(0)!;
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final billInfo = BillInfo.fromJson(json);
      logger.info(_tag, '账单提取成功: $billInfo');
      return billInfo;
    } catch (e) {
      logger.warning(_tag, 'JSON解析失败: $e');
      return null;
    }
  }
}
