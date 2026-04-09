import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:simplelog/widgets/biz/bee_icon.dart';

import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../services/system/update_service.dart';
import '../../services/system/logger_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/website_urls.dart';
import 'log_center_page.dart';

/// 是否为 Google Play 版本（通过 CI 构建时 --dart-define=GOOGLE_PLAY=true 注入）
const _isGooglePlayBuild =
    bool.fromEnvironment('GOOGLE_PLAY', defaultValue: false);

/// 关于页面
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  String _version = '';
  String _versionDisplay = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await _getAppInfo();
    final versionText = info.version.startsWith('dev-')
        ? '${info.version} (${info.buildNumber})'
        : info.version;
    setState(() {
      _version = info.version;
      _versionDisplay = versionText;
    });
  }

  void _showDeveloperStory(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aboutDeveloperStoryTitle),
        content: SingleChildScrollView(
          child: Text(
            l10n.aboutDeveloperStory,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: BeeTokens.textSecondary(context),
                  height: 1.7,
                ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: AppLocalizations.of(context).aboutPageTitle,
            subtitle: AppLocalizations.of(context).aboutPageSubtitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 顶部：图标 + 应用名称 + 版本号
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 24.0.scaled(context, ref),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.account_balance_wallet,
                        color: Theme.of(context).colorScheme.primary,
                        size: 80.0.scaled(context, ref),
                      ),
                      SizedBox(height: 16.0.scaled(context, ref)),
                      GestureDetector(
                        onTap: () => _showDeveloperStory(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppLocalizations.of(context).appName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                            ),
                            SizedBox(width: 4.0.scaled(context, ref)),
                            Icon(
                              Icons.help_outline_rounded,
                              size: 18.0.scaled(context, ref),
                              color: BeeTokens.textTertiary(context),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 8.0.scaled(context, ref)),
                      Text(
                        _versionDisplay.isEmpty
                            ? AppLocalizations.of(context)
                                .aboutPageLoadingVersion
                            : _versionDisplay,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: BeeTokens.textSecondary(context),
                            ),
                      ),
                    ],
                  ),
                ),
                // 联系方式
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      AppListTile(
                        leading: Icons.language_outlined,
                        title: AppLocalizations.of(context).aboutWebsite,
                        onTap: () async {
                          final locale = Localizations.localeOf(context);
                          final url = Uri.parse(WebsiteUrls.home(locale));
                          await _tryOpenUrl(url);
                        },
                      ),
                      const Divider(height: 1, thickness: 0.5),
                      AppListTile(
                        leading: Icons.code_outlined,
                        title: AppLocalizations.of(context).aboutGitHubRepo,
                        subtitle: 'github.com/TNT-Likely/BeeCount',
                        onTap: () async {
                          final url = Uri.parse(
                              'https://github.com/TNT-Likely/BeeCount');
                          await _tryOpenUrl(url);
                        },
                      ),
                      // 小红书号（仅简体中文显示）
                      if (Localizations.localeOf(context).languageCode ==
                          'zh') ...[
                        const Divider(height: 1, thickness: 0.5),
                        AppListTile(
                          leading: Icons.favorite_outline,
                          title: AppLocalizations.of(context).aboutXiaohongshu,
                          subtitle: '278979339',
                          onTap: () async {
                            final url =
                                Uri.parse('https://xhslink.com/m/8K1ekg7EFOq');
                            await _tryOpenUrl(url);
                          },
                        ),
                        const Divider(height: 1, thickness: 0.5),
                        AppListTile(
                          leading: Icons.music_note_outlined,
                          title: AppLocalizations.of(context).aboutDouyin,
                          subtitle: '75639334477',
                          onTap: () async {
                            final url =
                                Uri.parse('https://v.douyin.com/YG7tUweYYyQ/');
                            await _tryOpenUrl(url);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 8.0.scaled(context, ref)),
                // 功能
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      AppListTile(
                        leading: Icons.favorite_border,
                        title: AppLocalizations.of(context)
                            .aboutSupportDevelopment,
                        subtitle: AppLocalizations.of(context)
                            .aboutSupportDevelopmentSubtitle,
                        onTap: () async {
                          final locale =
                              Localizations.localeOf(context).languageCode;
                          final docUrl = locale == 'zh'
                              ? 'https://github.com/TNT-Likely/BeeCount/blob/main/docs/donate/README_ZH.md'
                              : 'https://github.com/TNT-Likely/BeeCount/blob/main/docs/donate/README_EN.md';
                          final url = Uri.parse(docUrl);
                          await _tryOpenUrl(url);
                        },
                      ),
                      const Divider(height: 1, thickness: 0.5),
                      AppListTile(
                        leading: Icons.feedback_outlined,
                        title: AppLocalizations.of(context).mineFeedback,
                        subtitle:
                            AppLocalizations.of(context).mineFeedbackSubtitle,
                        onTap: () async {
                          final url = Uri.parse(
                              'https://github.com/TNT-Likely/BeeCount/issues');
                          await _tryOpenUrl(url);
                        },
                      ),
                      const Divider(height: 1, thickness: 0.5),
                      AppListTile(
                        leading: Icons.bug_report_outlined,
                        title: AppLocalizations.of(context).logCenterTitle,
                        subtitle:
                            AppLocalizations.of(context).logCenterSubtitle,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LogCenterPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // 相关产品
                SizedBox(height: 32.0.scaled(context, ref)),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    AppLocalizations.of(context).aboutRelatedProducts,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: BeeTokens.textSecondary(context),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                // BeeDNS 推广卡片
                _BeeDNSCard(onTap: () async {
                  // iOS 跳转 App Store，Android 跳转官网
                  final url = Platform.isIOS
                      ? 'https://apps.apple.com/app/id6757992815'
                      : 'https://beedns.youths.cc';
                  await _tryOpenUrl(Uri.parse(url));
                }),
                // ICP 备案号（仅简体中文显示）
                if (Localizations.localeOf(context).languageCode == 'zh' &&
                    Localizations.localeOf(context).countryCode != 'TW') ...[
                  SizedBox(height: 24.0.scaled(context, ref)),
                  Center(
                    child: Text(
                      '浙ICP备2025214907号-2A',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: BeeTokens.textTertiary(context),
                            fontSize: 11,
                          ),
                    ),
                  ),
                  SizedBox(height: 16.0.scaled(context, ref)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------- 工具方法：关于与更新 --------
class _AppInfo {
  final String version;
  final String buildNumber;
  final String? commit;
  final String? buildTime;
  const _AppInfo(this.version, this.buildNumber, {this.commit, this.buildTime});
}

// 优先读取 CI 注入的 dart-define（CI_VERSION/GIT_COMMIT/BUILD_TIME），否则回退 PackageInfo
Future<_AppInfo> _getAppInfo() async {
  final p = await PackageInfo.fromPlatform();
  final commit = const String.fromEnvironment('GIT_COMMIT');
  final buildTime = const String.fromEnvironment('BUILD_TIME');
  final ciVersion = const String.fromEnvironment('CI_VERSION');

  // 版本号策略：CI版本优先，本地开发显示 "dev-{pubspec版本}"
  final version =
      ciVersion.isNotEmpty ? ciVersion : 'dev-${p.version}'; // 本地开发版本标识

  return _AppInfo(version, p.buildNumber,
      commit: commit.isEmpty ? null : commit,
      buildTime: buildTime.isEmpty ? null : buildTime);
}

/// BeeDNS 推广卡片组件（带动画）
class _BeeDNSCard extends StatefulWidget {
  final VoidCallback onTap;
  const _BeeDNSCard({required this.onTap});

  @override
  State<_BeeDNSCard> createState() => _BeeDNSCardState();
}

class _BeeDNSCardState extends State<_BeeDNSCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    // 入场动画
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // BeeDNS 品牌色（琥珀橙）
    const beeDNSColor = Color(0xFFF59E0B);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  beeDNSColor.withValues(alpha: 0.12),
                  beeDNSColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: beeDNSColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Logo - BeeDNS 图标
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/beedns_logo.png',
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                // 文字内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).aboutBeeDNS,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: beeDNSColor,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context).aboutBeeDNSSubtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: BeeTokens.textSecondary(context),
                            ),
                      ),
                    ],
                  ),
                ),
                // 箭头
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: beeDNSColor.withValues(alpha: 0.6),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 尝试使用多种方式打开URL，提供更好的兼容性
Future<bool> _tryOpenUrl(Uri url) async {
  try {
    // 方式1: 默认外部应用打开
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return true;
    }

    // 方式2: 浏览器内打开
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalNonBrowserApplication);
      return true;
    }

    // 方式3: 平台默认方式
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
      return true;
    }

    logger.error('AboutPage', '无法打开URL: $url');
    return false;
  } catch (e) {
    logger.error('AboutPage', '打开URL失败: $url', e);
    return false;
  }
}
