import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart' hide SyncStatus;

import '../../providers.dart';
import '../../providers/theme_providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../cloud/sync_service.dart';
import '../cloud/cloud_service_page.dart';
import '../../l10n/app_localizations.dart';
import '../budget/budget_page.dart';
import '../cloud/cloud_sync_page.dart';
import '../../pages/settings/data_management_page.dart';
import '../../pages/settings/appearance_settings_page.dart';
import '../../pages/settings/smart_billing_page.dart';
import '../../pages/settings/automation_page.dart';
import '../../services/system/update_service.dart';
import '../../utils/ui_scale_extensions.dart';

/// 是否为 Google Play 版本（通过 CI 构建时 --dart-define=GOOGLE_PLAY=true 注入）
const _isGooglePlayBuild =
    bool.fromEnvironment('GOOGLE_PLAY', defaultValue: false);

class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authServiceProvider);
    final ledgerId = ref.watch(currentLedgerIdProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context), // ⭐ 使用 Token
      body: Column(
        children: [
          PrimaryHeader(
            showBack: false,
            title: AppLocalizations.of(context).mineTitle,
            compact: true,
            showTitleSection: false,
            content: _MinePageHeader(),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                BeeTokens.cardDivider(context),
                SizedBox(height: 8.0.scaled(context, ref)),
                // 云同步与备份
                Consumer(builder: (sectionContext, sectionRef, _) {
                  final activeCfg = sectionRef.watch(activeCloudConfigProvider);

                  return SectionCard(
                    margin: EdgeInsets.fromLTRB(
                        12.0.scaled(sectionContext, sectionRef),
                        0,
                        12.0.scaled(sectionContext, sectionRef),
                        0),
                    child: Column(
                      children: [
                        // 云服务
                        AppListTile(
                          leading: Icons.cloud_queue_outlined,
                          title: AppLocalizations.of(sectionContext)
                              .mineCloudService,
                          subtitle: activeCfg.when(
                            loading: () => AppLocalizations.of(sectionContext)
                                .mineCloudServiceLoading,
                            error: (e, _) =>
                                '${AppLocalizations.of(sectionContext).commonError}: $e',
                            data: (cfg) {
                              switch (cfg.type) {
                                case CloudBackendType.local:
                                  return AppLocalizations.of(sectionContext)
                                      .mineCloudServiceOffline;
                                case CloudBackendType.webdav:
                                  return AppLocalizations.of(sectionContext)
                                      .mineCloudServiceWebDAV;
                                case CloudBackendType.icloud:
                                  return 'iCloud';
                                case CloudBackendType.supabase:
                                  return AppLocalizations.of(sectionContext)
                                      .mineCloudServiceCustom;
                                case CloudBackendType.s3:
                                  return 'S3';
                              }
                            },
                          ),
                          onTap: () async {
                            await Navigator.of(sectionContext).push(
                              MaterialPageRoute(
                                  builder: (_) => const CloudServicePage()),
                            );
                          },
                        ),
                        // 同步状态
                        Builder(
                          builder: (ctx) {
                            return authAsync.when(
                              loading: () => const Padding(
                                padding: EdgeInsets.all(16.0),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              ),
                              error: (e, _) => Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  '${AppLocalizations.of(sectionContext).commonError}: $e',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                              data: (auth) => FutureBuilder<CloudUser?>(
                                future: auth.currentUser,
                                builder: (ctx, snap) {
                                  if (snap.hasError) {
                                    return Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Text(
                                        '${AppLocalizations.of(sectionContext).commonError}: ${snap.error}',
                                        style:
                                            const TextStyle(color: Colors.red),
                                      ),
                                    );
                                  }

                                  final user = snap.data;
                                  final cloudConfig = sectionRef
                                      .watch(activeCloudConfigProvider);
                                  final isLocalMode = cloudConfig.hasValue &&
                                      cloudConfig.value!.type ==
                                          CloudBackendType.local;
                                  final isICloudMode = cloudConfig.hasValue &&
                                      cloudConfig.value!.type ==
                                          CloudBackendType.icloud;
                                  // iCloud 使用系统账号，不需要登录；其他云服务需要登录
                                  final canUseCloud = !isLocalMode &&
                                      (isICloudMode || user != null);
                                  final asyncSt = sectionRef
                                      .watch(syncStatusProvider(ledgerId));
                                  final cached = sectionRef
                                      .watch(lastSyncStatusProvider(ledgerId));
                                  final st = asyncSt.asData?.value ?? cached;

                                  // 计算简化的同步状态显示
                                  String subtitle = '';
                                  bool showCheckIcon = false;
                                  final isFirstLoad = st == null;
                                  final refreshing = asyncSt.isLoading;

                                  if (!isFirstLoad) {
                                    switch (st.diff) {
                                      case SyncDiff.notLoggedIn:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncNotLoggedIn;
                                        break;
                                      case SyncDiff.notConfigured:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncNotConfigured;
                                        break;
                                      case SyncDiff.noRemote:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncNoRemote;
                                        break;
                                      case SyncDiff.inSync:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncInSyncSimple;
                                        showCheckIcon = true;
                                        break;
                                      case SyncDiff.localNewer:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncLocalNewerSimple;
                                        break;
                                      case SyncDiff.cloudNewer:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncCloudNewerSimple;
                                        break;
                                      case SyncDiff.different:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncDifferent;
                                        break;
                                      case SyncDiff.error:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncError;
                                        break;
                                    }
                                  }

                                  return Column(
                                    children: [
                                      BeeTokens.cardDivider(sectionContext),
                                      AppListTile(
                                        leading: Icons.cloud_sync_outlined,
                                        title:
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncTitle,
                                        subtitle: isFirstLoad ? null : subtitle,
                                        enabled: !isLocalMode,
                                        trailing: (canUseCloud &&
                                                (isFirstLoad || refreshing))
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : showCheckIcon
                                                ? Icon(Icons.check_circle,
                                                    color: sectionRef.watch(
                                                        primaryColorProvider),
                                                    size: 20)
                                                : Icon(Icons.chevron_right,
                                                    color: BeeTokens.iconTertiary(
                                                        context), // ⭐ 使用 Token
                                                    size: 20),
                                        onTap: () async {
                                          await Navigator.of(sectionContext)
                                              .push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const CloudSyncPage()),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }),
                // 功能管理
                SizedBox(height: 8.0.scaled(context, ref)),
                SectionCard(
                  margin: EdgeInsets.fromLTRB(12.0.scaled(context, ref), 0,
                      12.0.scaled(context, ref), 0),
                  child: Column(
                    children: [
                      // 智能记账
                      AppListTile(
                        leading: Icons.auto_awesome_outlined,
                        title: AppLocalizations.of(context).smartBilling,
                        subtitle: AppLocalizations.of(context).smartBillingDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const SmartBillingPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      // 数据管理
                      AppListTile(
                        leading: Icons.storage_outlined,
                        title: AppLocalizations.of(context).dataManagement,
                        subtitle:
                            AppLocalizations.of(context).dataManagementDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const DataManagementPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      // 预算管理
                      AppListTile(
                        leading: Icons.pie_chart_outline_rounded,
                        title: AppLocalizations.of(context).budgetManagement,
                        subtitle:
                            AppLocalizations.of(context).budgetManagementDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const BudgetPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      // 自动化功能
                      AppListTile(
                        leading: Icons.schedule_outlined,
                        title: AppLocalizations.of(context).automation,
                        subtitle: AppLocalizations.of(context).automationDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AutomationPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      // 外观设置
                      AppListTile(
                        leading: Icons.palette_outlined,
                        title: AppLocalizations.of(context).appearanceSettings,
                        subtitle:
                            AppLocalizations.of(context).appearanceSettingsDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AppearanceSettingsPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // 帮助与信息
                SizedBox(height: 8.0.scaled(context, ref)),
                SectionCard(
                  margin: EdgeInsets.fromLTRB(12.0.scaled(context, ref), 0,
                      12.0.scaled(context, ref), 0),
                  child: Column(
                    children: [
                      // 检查更新
                      if (!Platform.isIOS && !_isGooglePlayBuild) ...[
                        Consumer(builder: (context, ref2, child) {
                          final isLoading =
                              ref2.watch(checkUpdateLoadingProvider);
                          final downloadProgress =
                              ref2.watch(updateProgressProvider);

                          // 确定显示状态
                          bool showProgress = false;
                          String title =
                              AppLocalizations.of(context).mineCheckUpdate;
                          String? subtitle;
                          IconData icon = Icons.system_update_alt_outlined;
                          Widget? trailing;

                          if (isLoading) {
                            title = AppLocalizations.of(context)
                                .mineCheckUpdateDetecting;
                            subtitle = AppLocalizations.of(context)
                                .mineCheckUpdateSubtitleDetecting;
                            icon = Icons.hourglass_empty;
                            trailing = const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2));
                          } else if (downloadProgress.isActive) {
                            showProgress = true;
                            title = AppLocalizations.of(context)
                                .mineUpdateDownloadTitle;
                            icon = Icons.download_outlined;
                            trailing = SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: downloadProgress.progress,
                                ));
                          }

                          return AppListTile(
                            leading: icon,
                            title: title,
                            subtitle: showProgress
                                ? downloadProgress.status
                                : subtitle,
                            trailing: trailing,
                            onTap: (isLoading || showProgress)
                                ? null
                                : () async {
                                    await UpdateService.checkUpdateWithUI(
                                      context,
                                      setLoading: (loading) => ref2
                                          .read(checkUpdateLoadingProvider
                                              .notifier)
                                          .state = loading,
                                      setProgress: (progress, status) {
                                        if (status.isEmpty) {
                                          ref2
                                              .read(updateProgressProvider
                                                  .notifier)
                                              .state = UpdateProgress.idle();
                                        } else {
                                          ref2
                                                  .read(updateProgressProvider
                                                      .notifier)
                                                  .state =
                                              UpdateProgress.active(
                                                  progress, status);
                                        }
                                      },
                                    );
                                  },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: BeeDimens.p16.scaled(context, ref)),
                // 底部留白，避免被悬浮 Tab 栏遮挡
                SizedBox(
                    height: 56 +
                        12 +
                        MediaQuery.of(context).viewPadding.bottom +
                        16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends ConsumerWidget {
  final String label;
  final dynamic value; // 可以是 String 或 double
  final TextStyle? labelStyle;
  final TextStyle? numStyle;
  final bool isAmount; // 是否为金额类型
  final String? currencyCode; // 币种代码
  final bool centered; // 是否居中对齐

  const _StatCell({
    required this.label,
    required this.value,
    this.labelStyle,
    this.numStyle,
    this.isAmount = false,
    this.currencyCode,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget valueWidget;
    if (isAmount && value is double) {
      // 金额类型,使用 AmountText
      valueWidget = AmountText(
        value: value as double,
        signed: false,
        showCurrency: true,
        useCompactFormat: ref.watch(compactAmountProvider),
        currencyCode: currencyCode,
        style: numStyle,
      );
    } else {
      // 其他类型,直接显示字符串
      valueWidget = Text(value.toString(), style: numStyle);
    }

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        valueWidget,
        SizedBox(height: 4.0.scaled(context, ref)), // 数字与标签间距增大
        Text(label,
            style: labelStyle,
            textAlign: centered ? TextAlign.center : TextAlign.start),
      ],
    );
  }
}

/// 我的页面头部
class _MinePageHeader extends ConsumerStatefulWidget {
  const _MinePageHeader();

  @override
  ConsumerState<_MinePageHeader> createState() => _MinePageHeaderState();
}

class _MinePageHeaderState extends ConsumerState<_MinePageHeader> {
  @override
  Widget build(BuildContext context) {
    // 获取当前账本信息
    final currentLedgerId = ref.watch(currentLedgerIdProvider);
    final countsAsync = ref.watch(countsForLedgerProvider(currentLedgerId));
    final balanceAsync = ref.watch(currentBalanceProvider(currentLedgerId));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);

    final day = countsAsync.asData?.value.dayCount ?? 0;
    final tx = countsAsync.asData?.value.txCount ?? 0;
    final balance = balanceAsync.asData?.value ?? 0.0;
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';

    // 统计信息文字颜色
    final labelStyle = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: BeeTokens.textSecondary(context));
    final numStyle = BeeTextTokens.strongTitle(context)
        .copyWith(fontSize: 20, color: BeeTokens.textPrimary(context));

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12.0.scaled(context, ref),
        12.0.scaled(context, ref),
        12.0.scaled(context, ref),
        10.0.scaled(context, ref),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // 统计数据
              Row(
                children: [
                  Expanded(
                    child: _StatCell(
                      label: AppLocalizations.of(context).mineDaysCount,
                      value: day.toString(),
                      labelStyle: labelStyle,
                      numStyle: numStyle,
                      centered: true,
                    ),
                  ),
                  Expanded(
                    child: _StatCell(
                      label: AppLocalizations.of(context).mineTotalRecords,
                      value: tx.toString(),
                      labelStyle: labelStyle,
                      numStyle: numStyle,
                      centered: true,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final cur = ref.read(hideAmountsProvider);
                        ref.read(hideAmountsProvider.notifier).state = !cur;
                      },
                      child: _StatCell(
                        label: AppLocalizations.of(context).mineCurrentBalance,
                        value: balance,
                        isAmount: true,
                        currencyCode: currencyCode,
                        labelStyle: labelStyle,
                        numStyle: numStyle.copyWith(
                          color: balance >= 0
                              ? BeeTokens.textPrimary(context)
                              : BeeTokens.error(context),
                        ),
                        centered: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
