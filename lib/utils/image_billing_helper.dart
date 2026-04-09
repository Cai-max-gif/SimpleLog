import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../services/billing/ocr_service.dart';
import '../services/billing/bill_creation_service.dart';
import '../services/billing/post_processor.dart';
import '../services/data/tag_seed_service.dart';
import '../services/attachment_service.dart';
import '../widgets/ui/ui.dart';

/// 图片识别记账帮助类
class ImageBillingHelper {
  /// 从相册选择图片并自动记账
  static Future<void> pickImageForBilling(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await _processImageBilling(
      context,
      ref,
      ImageSource.gallery,
    );
  }

  /// 打开相机拍照并自动记账
  static Future<void> openCameraForBilling(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await _processImageBilling(
      context,
      ref,
      ImageSource.camera,
    );
  }

  /// 处理图片识别记账（统一逻辑）
  static Future<void> _processImageBilling(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final l10n = AppLocalizations.of(context);

    try {
      // 选择图片
      final imagePicker = ImagePicker();
      final pickedFile = await imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        // 用户取消
        return;
      }

      if (!context.mounted) return;

      // 显示加载提示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.aiOcrRecognizing),
                ],
              ),
            ),
          ),
        ),
      );

      // OCR识别
      final ocrService = OcrService();
      final imageFile = File(pickedFile.path);
      final ocrResult = await ocrService.recognizePaymentImage(imageFile);

      if (!context.mounted) return;

      // 关闭加载提示
      Navigator.of(context).pop();

      // 验证识别结果
      if (ocrResult.amount == null || ocrResult.amount!.abs() <= 0) {
        showToast(context, l10n.aiOcrNoAmount);
        return;
      }

      // 获取当前账本
      final currentLedger = await ref.read(currentLedgerProvider.future);
      if (currentLedger == null) {
        if (!context.mounted) return;
        showToast(context, l10n.aiOcrNoLedger);
        return;
      }

      // 读取智能记账设置
      final autoAddTags = ref.read(smartBillingAutoTagsProvider);
      final autoAddAttachment = ref.read(smartBillingAutoAttachmentProvider);

      // 使用BillCreationService创建交易
      final repo = ref.read(repositoryProvider);
      final billCreationService = BillCreationService(repo);

      // 确定记账方式标签
      final billingTypes = <String>[];
      if (source == ImageSource.gallery) {
        billingTypes.add(TagSeedService.billingTypeImage);
      } else {
        billingTypes.add(TagSeedService.billingTypeCamera);
      }
      // 如果使用了AI增强，添加AI标签
      if (ocrResult.aiEnhanced) {
        billingTypes.add(TagSeedService.billingTypeAi);
      }

      final note = ocrResult.note ?? '';
      final transactionId = await billCreationService.createBillTransaction(
        result: ocrResult,
        ledgerId: currentLedger.id,
        note: note.isNotEmpty ? note : null,
        billingTypes: billingTypes,
        l10n: l10n,
        autoAddTags: autoAddTags,
      );

      if (!context.mounted) return;

      if (transactionId != null) {
        // 自动保存图片附件（根据设置开关）
        if (autoAddAttachment) {
          final attachmentService = ref.read(attachmentServiceProvider);
          await attachmentService.saveAttachment(
            transactionId: transactionId,
            sourceFile: imageFile,
            index: 0,
          );
        }

        // 统一后处理：刷新UI + 触发云同步
        await PostProcessor.run(ref, ledgerId: currentLedger.id, tags: true, attachments: autoAddAttachment);

        if (context.mounted) {
          final transactionType = (ocrResult.aiType == 'income') ? 'income' : 'expense';
          final typeText = transactionType == 'income' ? l10n.aiTypeIncome : l10n.aiTypeExpense;
          final amount = ocrResult.amount!.abs().toStringAsFixed(2);
          showToast(context, l10n.aiOcrSuccess(typeText, amount));
        }
      } else {
        showToast(context, l10n.aiOcrCreateFailed);
      }
    } catch (e) {
      if (!context.mounted) return;
      // 尝试关闭可能还在显示的加载对话框
      Navigator.of(context).popUntil((route) => route.isFirst);
      showToast(context, l10n.aiOcrFailed(e.toString()));
    }
  }
}
