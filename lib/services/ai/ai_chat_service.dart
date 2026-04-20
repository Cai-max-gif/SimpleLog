import 'package:shared_preferences/shared_preferences.dart';

import 'ai_bill_service.dart';
import 'ai_provider_factory.dart';
import '../billing/bill_creation_service.dart';
import '../billing/ocr_service.dart';
import '../data/tag_seed_service.dart';
import '../../ai/tasks/bill_extraction_task.dart';
import '../../data/repositories/base_repository.dart';
import '../../l10n/app_localizations.dart';
import '../system/logger_service.dart';

/// AI配置验证结果
class AIConfigValidationResult {
  final bool isValid;
  final String? errorMessage;

  AIConfigValidationResult({
    required this.isValid,
    this.errorMessage,
  });

  factory AIConfigValidationResult.valid() {
    return AIConfigValidationResult(isValid: true);
  }

  factory AIConfigValidationResult.invalid(String message) {
    return AIConfigValidationResult(isValid: false, errorMessage: message);
  }
}

/// AI 对话服务
///
/// 支持两种模式:
/// 1. 对话记账 - 复用 AIBillService 和 BillCreationService
/// 2. 自由对话 - 使用 AIProviderFactory 自动选择服务商（智谱GLM/自定义OpenAI兼容）
class AIChatService {
  final AIBillService _aiBillService = AIBillService();
  final BaseRepository _repo;

  AIChatService({required BaseRepository repo}) : _repo = repo;

  /// 验证 API Key 是否有效（静态方法）
  /// 使用 AIProviderFactory 统一验证
  static Future<AIConfigValidationResult> validateApiKey() async {
    final (success, error) = await AIProviderFactory.validateConfig(
      logTag: 'AIChat',
    );

    if (success) {
      return AIConfigValidationResult.valid();
    } else {
      return AIConfigValidationResult.invalid(error ?? '验证失败');
    }
  }

  /// 处理用户消息
  Future<AIResponse> processMessage(
    String userInput, {
    required int ledgerId, // 当前账本ID
    List<String>? expenseCategories,
    List<String>? incomeCategories,
    String? languageCode,
    bool forceChat = false, // 强制为自由对话，跳过意图检测
    AppLocalizations? l10n, // 国际化对象，用于标签名称
  }) async {
    logger.info('AIChat', '收到消息: $userInput (forceChat: $forceChat)');

    try {
      // 判断意图
      if (!forceChat && _isTransactionIntent(userInput)) {
        logger.debug('AIChat', '识别为记账意图');
        return await _handleTransaction(
          userInput,
          ledgerId: ledgerId,
          expenseCategories: expenseCategories,
          incomeCategories: incomeCategories,
          l10n: l10n,
        );
      } else {
        logger.debug('AIChat', '识别为自由对话');
        return await _handleFreeChat(userInput, languageCode: languageCode);
      }
    } catch (e, st) {
      logger.error('AIChat', '处理失败', e, st);
      return AIResponse.error('抱歉,处理失败,请重试');
    }
  }

  /// 判断是否是记账意图
  bool _isTransactionIntent(String input) {
    // 包含金额 → 记账意图
    final hasAmount = RegExp(r'\d+(?:\.\d+)?').hasMatch(input);

    // 或包含记账关键词
    const keywords = ['买', '花', '消费', '支付', '记账', '付', '收入', '赚', '工资'];
    final hasKeyword = keywords.any((k) => input.contains(k));

    return hasAmount || hasKeyword;
  }

  /// 处理记账 - 复用 AIBillService
  Future<AIResponse> _handleTransaction(
    String input, {
    required int ledgerId,
    List<String>? expenseCategories,
    List<String>? incomeCategories,
    AppLocalizations? l10n,
  }) async {
    logger.debug('AIChat', '识别为记账意图');

    // 调用 AIBillService
    var billInfo = await _aiBillService.extractBillInfo(
      input,
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
    );

    if (billInfo != null && billInfo.isComplete) {
      logger.info('AIChat', '账单提取成功: ${billInfo.toJson()}');

      // 将 ledgerId 添加到 billInfo（创建新实例）
      billInfo = BillInfo(
        amount: billInfo.amount,
        time: billInfo.time,
        note: billInfo.note,
        category: billInfo.category,
        type: billInfo.type,
        account: billInfo.account,
        fromAccount: billInfo.fromAccount,
        toAccount: billInfo.toAccount,
        tags: billInfo.tags,
        ledgerId: ledgerId,
        confidence: billInfo.confidence,
      );

      logger.info('AIChat', '附加账本ID到BillInfo: ledgerId=$ledgerId');

      // 保存到数据库并获取实际的分类和账户名称
      final (transactionId, actualCategory, actualAccount) =
          await _saveBill(billInfo, l10n: l10n);

      // 使用实际的分类和账户名称更新 billInfo
      final updatedBillInfo = BillInfo(
        amount: billInfo.amount,
        time: billInfo.time,
        note: billInfo.note,
        category: actualCategory ?? billInfo.category,
        type: billInfo.type,
        account: actualAccount ?? billInfo.account,
        fromAccount: billInfo.fromAccount,
        toAccount: billInfo.toAccount,
        tags: billInfo.tags,
        ledgerId: ledgerId,
        confidence: billInfo.confidence,
      );

      // 返回账单卡片
      return AIResponse.billCard(updatedBillInfo, transactionId);
    } else {
      logger.warning('AIChat', '账单提取失败或信息不完整');

      // 提取失败
      return AIResponse.text(
        '抱歉,未识别到完整的记账信息。\n\n'
        '请这样说:\n'
        '• 买了杯奶茶28块\n'
        '• 今天午餐花了50\n'
        '• 打车回家花了35',
      );
    }
  }

  /// 处理自由对话 - 使用 AIProviderFactory.chat()
  Future<AIResponse> _handleFreeChat(String input,
      {String? languageCode}) async {
    logger.info('AIChat', '开始自由对话 (语言: ${languageCode ?? "默认"})');

    try {
      // 根据语言构建系统提示
      String systemPrompt;
      if (languageCode == 'en') {
        systemPrompt =
            'You are SimpleLog\'s AI assistant, mainly helping users with bookkeeping. '
            'If users ask about statistics, queries and other functions, please inform them that they are not supported yet and guide them to use the bookkeeping function. '
            'Please respond in English.';
      } else {
        systemPrompt = '你是简单记账的AI助手,主要帮助用户记账。'
            '如果用户询问统计、查询等功能,请告知暂不支持,引导用户使用记账功能。'
            '请用中文回复。';
      }

      final response = await AIProviderFactory.chat(
        input,
        systemPrompt: systemPrompt,
        logTag: 'AIChat',
      );

      logger.info('AIChat', '对话响应成功');
      return AIResponse.text(response);
    } on AIException catch (e) {
      logger.warning('AIChat', '对话响应失败: ${e.message}');
      if (e.message.contains('配置无效')) {
        return AIResponse.error(
          '需要配置 API Key 才能使用对话功能。\n\n'
          '前往 设置 > AI设置 进行配置。',
        );
      }
      return AIResponse.error('AI服务暂时不可用,请稍后重试');
    } catch (e, st) {
      logger.error('AIChat', '自由对话失败', e, st);
      return AIResponse.error('网络连接失败,请检查网络');
    }
  }

  /// 保存账单 - 复用 BillCreationService 的逻辑
  /// 返回 (transactionId, actualCategoryName, actualAccountName)
  Future<(int, String?, String?)> _saveBill(BillInfo bill,
      {AppLocalizations? l10n}) async {
    logger.info('AIChat',
        '开始保存账单: amount=${bill.amount}, category=${bill.category}, ledgerId=${bill.ledgerId}');

    // 使用 BillInfo 中的 ledgerId，如果为空则使用第一个账本
    int ledgerId;
    if (bill.ledgerId != null) {
      ledgerId = bill.ledgerId!;
      logger.info('AIChat', '使用指定账本ID: $ledgerId');
    } else {
      final ledgers = await _repo.getAllLedgers();
      ledgerId = ledgers.first.id;
      logger.warning('AIChat', '未指定账本ID，使用第一个账本: $ledgerId');
    }

    // 确定交易类型（修复：type 为空时不再默认收入）
    final transactionType = _resolveTransactionType(bill);

    // 转账场景优先使用 from_account 作为转出账户
    final aiAccountName = transactionType == 'transfer'
        ? (bill.fromAccount ?? bill.account)
        : bill.account;

    // 将 BillInfo 转换为 OcrResult（复用 BillCreationService 的逻辑）
    final ocrResult = OcrResult(
      amount: bill.amount,
      note: bill.note,
      time: bill.time,
      rawText: bill.note ?? '',
      allNumbers: bill.amount != null ? [bill.amount!.abs().toString()] : [],
      aiCategoryName: bill.category,
      aiAccountName: aiAccountName,
      aiType: transactionType,
    );

    // 读取智能记账设置
    final prefs = await SharedPreferences.getInstance();
    final autoAddTags = prefs.getBool('smartBillingAutoTags') ?? true;

    // 使用 BillCreationService 创建交易
    final billCreationService = BillCreationService(_repo);
    final id = await billCreationService.createBillTransaction(
      result: ocrResult,
      ledgerId: ledgerId,
      note: bill.note,
      billingTypes: [TagSeedService.billingTypeAi],
      fromAccountName: bill.fromAccount,
      toAccountName: bill.toAccount,
      customTagNames: bill.tags,
      l10n: l10n,
      autoAddTags: autoAddTags,
    );

    if (id != null) {
      // 查询实际保存的交易，获取实际的分类和账户名称
      final transaction = await _repo.getTransactionById(id);

      String? actualCategoryName;
      String? actualAccountName;

      if (transaction != null) {
        // 获取实际分类名称
        if (transaction.categoryId != null) {
          final category = await _repo.getCategoryById(transaction.categoryId!);
          actualCategoryName = category?.name;
        }

        // 获取实际账户名称
        if (transaction.accountId != null) {
          final account = await _repo.getAccount(transaction.accountId!);
          actualAccountName = account?.name;
        }
      }

      logger.info('AIChat',
          '记账成功: id=$id, category=$actualCategoryName, account=$actualAccountName');
      return (id, actualCategoryName, actualAccountName);
    } else {
      throw Exception('创建交易失败');
    }
  }

  /// 撤销记账
  Future<bool> undoTransaction(int transactionId) async {
    try {
      await _repo.deleteTransaction(transactionId);
      logger.info('AIChat', '撤销记账: id=$transactionId');
      return true;
    } catch (e, st) {
      logger.error('AIChat', '撤销失败', e, st);
      return false;
    }
  }

  String _resolveTransactionType(BillInfo bill) {
    if (bill.type == BillType.transfer) return 'transfer';
    if (bill.type == BillType.expense) return 'expense';
    if (bill.type == BillType.income) return 'income';

    final category = bill.category?.trim();
    if (category == '转账' ||
        category == '轉帳' ||
        category?.toLowerCase() == 'transfer') {
      return 'transfer';
    }

    return 'expense';
  }
}

/// AI 响应模型
class AIResponse {
  final String type; // 'text' | 'bill_card' | 'error'
  final String text;
  final BillInfo? billInfo;
  final int? transactionId;

  AIResponse({
    required this.type,
    required this.text,
    this.billInfo,
    this.transactionId,
  });

  factory AIResponse.text(String text) {
    return AIResponse(type: 'text', text: text);
  }

  factory AIResponse.billCard(BillInfo bill, int transactionId) {
    return AIResponse(
      type: 'bill_card',
      text: '✅ 记账成功',
      billInfo: bill,
      transactionId: transactionId,
    );
  }

  factory AIResponse.error(String message) {
    return AIResponse(type: 'error', text: message);
  }
}
