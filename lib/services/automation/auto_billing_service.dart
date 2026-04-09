import 'dart:io';
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../billing/ocr_service.dart';
import '../billing/category_matcher.dart';
import '../billing/bill_creation_service.dart';
import '../billing/post_processor.dart';
import '../attachment_service.dart';
import '../data/tag_seed_service.dart';
import 'auto_billing_config.dart';
import '../../providers.dart';
import '../../data/db.dart';
import '../../data/category_node.dart';
import '../../l10n/app_localizations.dart';
import '../system/logger_service.dart';

/// 自动记账服务 - 通用核心逻辑
/// Android和iOS共用的OCR识别和自动记账逻辑
class AutoBillingService {
  static const _ledgerIdKey = 'current_ledger_id';
  static const _processedScreenshotsKey = 'processed_screenshots';

  final ProviderContainer _container;
  final OcrService _ocrService = OcrService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 防重复处理
  final Set<String> _processedPaths = {};
  String? _lastProcessedPath;
  int _lastProcessedTime = 0;

  AutoBillingService(this._container) {
    _initNotifications();
    _loadProcessedScreenshots();
  }

  /// 初始化通知
  Future<void> _initNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(initSettings);
  }

  /// 加载已处理的截图列表
  Future<void> _loadProcessedScreenshots() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_processedScreenshotsKey) ?? [];
    _processedPaths.addAll(list);

    // 只保留最近N个，避免内存占用过大
    if (_processedPaths.length > AutoBillingConfig.maxProcessedCache) {
      final toRemove =
          _processedPaths.length - AutoBillingConfig.maxProcessedCache;
      _processedPaths.removeAll(_processedPaths.take(toRemove));
      await _saveProcessedScreenshots();
      logger.debug('AutoBilling', '清理已处理缓存',
          '移除=$toRemove, 保留=${AutoBillingConfig.maxProcessedCache}');
    }
  }

  /// 保存已处理的截图列表
  Future<void> _saveProcessedScreenshots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _processedScreenshotsKey, _processedPaths.toList());
  }

  /// 标记截图已处理
  Future<void> _markAsProcessed(String path) async {
    _processedPaths.add(path);
    await _saveProcessedScreenshots();
  }

  /// 检查截图是否已处理
  bool _isProcessed(String path) {
    return _processedPaths.contains(path);
  }

  /// 核心：处理截图并自动记账
  /// [imagePath] 截图文件路径
  /// [showNotification] 是否显示通知（默认true）
  /// 返回：交易记录ID，失败返回null
  Future<int?> processScreenshot(
    String imagePath, {
    bool showNotification = true,
  }) async {
    final totalStartTime = DateTime.now().millisecondsSinceEpoch;
    print('📸 [AutoBilling] 开始处理截图: $imagePath');
    logger.info('AutoBilling', '开始处理截图', imagePath);

    // 防重复处理: 已处理过的跳过
    if (_isProcessed(imagePath)) {
      print('⚠️ [AutoBilling] 截图已处理过，跳过');
      logger.warning('AutoBilling', '截图已处理过，跳过', imagePath);
      return null;
    }

    // 防重复处理: 配置时间窗口内相同路径只处理一次
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastProcessedPath == imagePath &&
        (now - _lastProcessedTime) < AutoBillingConfig.duplicateCheckWindow) {
      final timeDiff = now - _lastProcessedTime;
      print('⚠️ [AutoBilling] 重复截图，跳过处理 (${timeDiff}ms前已处理)');
      logger.warning('AutoBilling', '重复截图，跳过处理', '${timeDiff}ms前已处理');
      return null;
    }

    _lastProcessedPath = imagePath;
    _lastProcessedTime = now;

    try {
      const notificationId = 1001;

      // 检查文件是否存在
      final file = File(imagePath);

      // 如果文件不存在,可能需要短暂等待
      // (无障碍服务直接截图时文件已就绪,ContentObserver 可能需要等待)
      if (!await file.exists()) {
        print('⏳ 文件尚未就绪,等待最多${AutoBillingConfig.fileWaitTimeout}ms...');
        logger.info('AutoBilling', '文件尚未就绪，开始等待',
            '路径=$imagePath, 超时=${AutoBillingConfig.fileWaitTimeout}ms');

        if (showNotification) {
          await _showNotification(
            id: notificationId,
            title: '✅ 检测到截图',
            body: '正在等待文件写入...',
          );
        }

        final waitStartTime = DateTime.now().millisecondsSinceEpoch;
        var waitTime = 0;
        final maxWait = AutoBillingConfig.fileWaitTimeout;

        while (waitTime < maxWait) {
          if (await file.exists() && await file.length() > 0) {
            print('✅ 文件已就绪，等待时间=${waitTime}ms');
            logger.info('AutoBilling', '文件就绪', '等待时间=${waitTime}ms');
            break;
          }
          await Future.delayed(Duration(milliseconds: AutoBillingConfig.fileCheckInterval));
          waitTime = DateTime.now().millisecondsSinceEpoch - waitStartTime;
        }

        if (!await file.exists() || await file.length() == 0) {
          print('❌ 截图文件等待超时 (${waitTime}ms)');
          logger.error('AutoBilling', '截图文件等待超时',
              '路径=$imagePath, 等待时间=${waitTime}ms, 文件存在=${await file.exists()}');
          if (showNotification) {
            await _showNotification(
              id: notificationId,
              title: '识别失败',
              body: '截图文件不可用',
            );
          }
          return null;
        }
      } else {
        print('✅ 文件已就绪,无需等待');
        logger.debug('AutoBilling', '文件已就绪，无需等待');
      }

      // 更新通知：开始识别
      if (showNotification) {
        await _showNotification(
          id: notificationId,
          title: '正在识别截图...',
          body: '正在分析支付信息,请稍候',
        );
      }

      // OCR 识别
      final ocrStartTime = DateTime.now().millisecondsSinceEpoch;
      print('⏱️ [性能] 开始OCR识别');
      logger.info('AutoBilling', '开始OCR识别');

      // 获取Repository实例用于账户识别
      final repo = _container.read(repositoryProvider);
      final result = await _ocrService.recognizePaymentImage(file, repo: repo);

      final ocrElapsed = DateTime.now().millisecondsSinceEpoch - ocrStartTime;
      print('⏱️ [性能] OCR识别完成, 耗时=${ocrElapsed}ms');
      logger.info('AutoBilling', 'OCR识别完成', '耗时=${ocrElapsed}ms');

      // 打印识别结果用于调试
      print('📋 OCR识别原始文本: ${result.rawText}');
      print('💰 识别到的金额: ${result.amount}');
      print('📝 识别到的备注: ${result.note}');
      print('⏰ 识别到的时间: ${result.time}');
      print('🔢 所有数字: ${result.allNumbers}');
      logger.info('AutoBilling', 'OCR识别结果', {
        'rawText': result.rawText,
        'amount': result.amount,
        'note': result.note,
        'time': result.time,
        'allNumbers': result.allNumbers,
      }.toString());

      // 标记为已处理
      await _markAsProcessed(imagePath);

      // 根据识别结果处理
      if (result.amount != null && result.amount!.abs() > 0) {
        // 识别成功，自动创建记账记录（支持负数金额）
        print('✅ OCR识别成功: 金额=${result.amount}, 备注=${result.note}');

        try {
          final dbStartTime = DateTime.now().millisecondsSinceEpoch;
          print('⏱️ [性能] 开始创建交易记录');
          // 读取智能记账设置
          final autoAddTags = _container.read(smartBillingAutoTagsProvider);
          final autoAddAttachment = _container.read(smartBillingAutoAttachmentProvider);

          // 确定记账方式标签：图片记账 + AI（如果使用了AI增强）
          final billingTypes = <String>[TagSeedService.billingTypeImage];
          if (result.aiEnhanced) {
            billingTypes.add(TagSeedService.billingTypeAi);
          }
          final transactionId = await _createTransaction(
            result,
            billingTypes: billingTypes,
            autoAddTags: autoAddTags,
          );
          final dbElapsed = DateTime.now().millisecondsSinceEpoch - dbStartTime;
          print('⏱️ [性能] 交易记录创建完成, 耗时=${dbElapsed}ms');

          if (transactionId != null) {
            // 记账成功
            // 保存图片附件（根据设置开关）
            if (autoAddAttachment) {
              try {
                final attachmentService = _container.read(attachmentServiceProvider);
                await attachmentService.saveAttachment(
                  transactionId: transactionId,
                  sourceFile: file,
                  index: 0,
                );
                logger.info('AutoBilling', '截图附件保存成功', 'transactionId=$transactionId');
                // 刷新附件列表
                _container.read(attachmentListRefreshProvider.notifier).state++;
              } catch (e, st) {
                logger.error('AutoBilling', '保存截图附件失败', e, st);
                // 附件保存失败不影响交易记录
              }
            }

            // 刷新统计信息
            _container.read(statsRefreshProvider.notifier).state++;
            if (showNotification) {
              await _showNotification(
                id: notificationId,
                title: '✅ 自动记账成功 ¥${result.amount!.toStringAsFixed(2)}',
                body: result.note != null
                    ? '备注: ${result.note}'
                    : '已自动创建支出记录',
              );
            }
            print('✅ 自动记账成功: ID=$transactionId');
            logger.info('AutoBilling', '自动记账成功', 'ID=$transactionId, 金额=${result.amount}');
            return transactionId;
          } else {
            // 记账失败
            if (showNotification) {
              await _showNotification(
                id: notificationId,
                title: '❌ 自动记账失败',
                body: '识别成功但创建记录失败，请手动记账',
              );
            }
            print('❌ 自动记账失败: 创建交易记录返回null');
            logger.error('AutoBilling', '自动记账失败：创建交易记录返回null');
            return null;
          }
        } catch (e, stackTrace) {
          print('❌ 自动记账失败: $e');
          logger.error('AutoBilling', '自动记账失败', {
            'path': imagePath,
            'amount': result.amount,
            'note': result.note,
            'error': e.toString(),
          }, stackTrace);
          if (showNotification) {
            await _showNotification(
              id: notificationId,
              title: '❌ 自动记账失败',
              body: '识别成功但创建记录失败: $e',
            );
          }
          return null;
        }
      } else if (result.allNumbers.isNotEmpty) {
        // 识别到数字但未确定金额
        if (showNotification) {
          await _showNotification(
            id: notificationId,
            title: '⚠️ 识别到金额候选',
            body: '可能的金额: ${result.allNumbers.join(", ")} | 请手动确认',
          );
        }
        print('⚠️ 识别到数字但未确定金额: ${result.allNumbers}');
        logger.warning('AutoBilling', '识别到数字但未确定金额', result.allNumbers.toString());
        return null;
      } else {
        // 完全未识别到
        if (showNotification) {
          await _showNotification(
            id: notificationId,
            title: '❌ 未识别到支付信息',
            body: '可能不是支付截图,或图片质量较差',
          );
        }
        print('⚠️ 未识别到任何有效金额');
        logger.warning('AutoBilling', '未识别到任何有效金额');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ 处理截图失败: $e');
      logger.error('AutoBilling', '处理截图失败', {
        'path': imagePath,
        'error': e.toString(),
        'stage': '未知阶段',
      }, stackTrace);
      return null;
    } finally {
      final totalElapsed =
          DateTime.now().millisecondsSinceEpoch - totalStartTime;
      print('⏱️ [性能] 整个流程完成, 总耗时=${totalElapsed}ms');
    }
  }

  /// 核心：直接处理文本并自动记账(快捷指令推荐方式)
  /// [text] 快捷指令传递的识别文本
  /// [showNotification] 是否显示通知（默认true）
  /// 返回：交易记录ID，失败返回null
  Future<int?> processText(
    String text, {
    bool showNotification = true,
  }) async {
    final totalStartTime = DateTime.now().millisecondsSinceEpoch;
    print('📝 [AutoBilling] 开始处理文本: $text');

    try {
      const notificationId = 1002;

      // 显示"正在识别"通知
      if (showNotification) {
        await _showNotification(
          id: notificationId,
          title: '⏳ 正在识别',
          body: '正在解析支付信息...',
        );
      }

      // 直接解析文本(无需OCR)
      final ocrResult = _ocrService.parsePaymentText(text);

      if (ocrResult.amount == null) {
        print('❌ 未能识别出金额');
        if (showNotification) {
          await _showNotification(
            id: notificationId,
            title: '❌ 识别失败',
            body: '未能识别出金额信息',
          );
        }
        return null;
      }

      print('✅ 识别成功: 金额=${ocrResult.amount}, 备注=${ocrResult.note}');

      // 更新通知状态
      if (showNotification) {
        await _showNotification(
          id: notificationId,
          title: '✅ 识别成功',
          body: '正在创建交易记录...',
        );
      }

      // 获取分类并创建交易
      final repo = _container.read(repositoryProvider);
      final topLevelCategories = await repo.getTopLevelCategories('expense');
      final allCategories = <Category>[];
      allCategories.addAll(topLevelCategories);
      // 获取所有子分类
      for (final category in topLevelCategories) {
        final subCategories = await repo.getSubCategories(category.id);
        allCategories.addAll(subCategories);
      }

      // 过滤出可用分类（排除有子分类的父分类）
      final categories = CategoryHierarchy.getUsableCategories(allCategories);

      final suggestedCategoryId = CategoryMatcher.smartMatch(
        merchant: ocrResult.note,
        fullText: ocrResult.rawText,
        categories: categories,
      );

      final resultWithCategory = OcrResult(
        amount: ocrResult.amount,
        note: ocrResult.note,
        time: ocrResult.time,
        rawText: ocrResult.rawText,
        allNumbers: ocrResult.allNumbers,
        suggestedCategoryId: suggestedCategoryId,
      );

      // 创建交易记录
      final txId = await _createTransaction(resultWithCategory);

      if (txId != null) {
        // 刷新统计信息
        _container.read(statsRefreshProvider.notifier).state++;
        print('✅ 交易创建成功: id=$txId');
        if (showNotification) {
          await _showNotification(
            id: notificationId,
            title: '✅ 记账成功',
            body: '已自动创建支出记录: ¥${ocrResult.amount}',
          );
        }
        return txId;
      } else {
        print('❌ 交易创建失败');
        if (showNotification) {
          await _showNotification(
            id: notificationId,
            title: '❌ 创建失败',
            body: '无法创建交易记录',
          );
        }
        return null;
      }
    } catch (e) {
      print('❌ [AutoBilling] 文本处理失败: $e');
      if (showNotification) {
        await _showNotification(
          id: 1002,
          title: '❌ 处理失败',
          body: '错误: $e',
        );
      }
      return null;
    } finally {
      final totalElapsed =
          DateTime.now().millisecondsSinceEpoch - totalStartTime;
      print('⏱️ [性能] 文本处理完成, 总耗时=${totalElapsed}ms');
    }
  }

  /// 创建交易记录
  /// [billingTypes] 记账方式列表，用于添加标签
  /// [autoAddTags] 是否自动添加标签
  Future<int?> _createTransaction(
    OcrResult result, {
    List<String>? billingTypes,
    bool autoAddTags = true,
  }) async {
    try {
      // 获取当前账本ID（优先从Provider读取，失败则从SharedPreferences读取，最后从数据库获取默认账本）
      int? ledgerId;

      // 方案1: 尝试从Provider读取
      try {
        ledgerId = _container.read(currentLedgerIdProvider);
        print('✅ 从Provider获取账本ID: $ledgerId');
      } catch (e) {
        print('⚠️ 从Provider获取账本ID失败: $e');
      }

      // 方案2: 如果Provider失败，从SharedPreferences读取
      if (ledgerId == null) {
        final prefs = await SharedPreferences.getInstance();
        ledgerId = prefs.getInt(_ledgerIdKey);
        if (ledgerId != null) {
          print('✅ 从SharedPreferences获取账本ID: $ledgerId');
        }
      }

      // 方案3: 如果都失败，从数据库获取第一个账本
      if (ledgerId == null) {
        print('⚠️ 无法从缓存获取账本ID，尝试从数据库获取默认账本');
        final repo = _container.read(repositoryProvider);
        final ledgers = await repo.getAllLedgers();
        if (ledgers.isNotEmpty) {
          ledgerId = ledgers.first.id;
          print('✅ 从数据库获取默认账本ID: $ledgerId');
          // 保存到SharedPreferences供下次使用
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_ledgerIdKey, ledgerId!);
        }
      }

      if (ledgerId == null) {
        print('❌ 无法获取任何账本ID，请先创建账本');
        return null;
      }

      print('📝 准备创建交易: ledgerId=$ledgerId');

      // 使用共享的BillCreationService创建交易
      final repo = _container.read(repositoryProvider);
      final billCreationService = BillCreationService(repo);

      // 准备备注
      String? note;
      if (result.note != null) {
        note = result.note!;
      }

      // 获取 l10n（使用系统语言设置）
      final systemLocale = PlatformDispatcher.instance.locale;
      final l10n = lookupAppLocalizations(systemLocale);

      final transactionId = await billCreationService.createBillTransaction(
        result: result,
        ledgerId: ledgerId,
        note: note,
        billingTypes: billingTypes,
        l10n: l10n,
        autoAddTags: autoAddTags,
      );

      if (transactionId != null) {
        logger.info('AutoBilling', '交易记录已创建', 'ID=$transactionId');
        // 统一后处理：刷新UI + 触发云同步
        await PostProcessor.runC(_container, ledgerId: ledgerId, tags: true);
      } else {
        logger.warning('AutoBilling', '创建交易记录失败');
      }

      return transactionId;
    } catch (e) {
      print('❌ 创建交易记录失败: $e');
      print('❌ 错误堆栈: ${StackTrace.current}');
      rethrow;
    }
  }

  /// 显示通知
  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'screenshot_ocr',
      '截图识别',
      channelDescription: '截图自动识别通知',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(id, title, body, details);
  }

  /// 释放资源
  void dispose() {
    _ocrService.dispose();
  }
}
