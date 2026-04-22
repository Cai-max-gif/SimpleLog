import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/main/home_page.dart';
import 'pages/main/analytics_page.dart';
import 'pages/account/accounts_page.dart';
import 'pages/main/mine_page.dart';
import 'pages/transaction/transaction_editor_page.dart';
import 'pages/ai/ai_chat_page.dart';
import 'providers.dart';
import 'l10n/app_localizations.dart';
import 'widget/widget_manager.dart';
import 'widgets/ui/ui.dart';
import 'widgets/ui/speed_dial_fab.dart';
import 'cloud/transactions_sync_manager.dart';
import 'utils/voice_billing_helper.dart';
import 'utils/image_billing_helper.dart';

import 'services/security/app_lock_service.dart';
import 'providers/security_providers.dart';
import 'styles/tokens.dart';
import 'providers/avatar_providers.dart';

class BeeApp extends ConsumerStatefulWidget {
  const BeeApp({super.key});

  @override
  ConsumerState<BeeApp> createState() => _BeeAppState();
}

class _BeeAppState extends ConsumerState<BeeApp>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _pages = const [
    HomePage(),
    AnalyticsPage(),
    AccountsPage(asTab: true),
    MinePage(),
  ];

  // 双击检测：记录最后一次点击的时间和索引
  DateTime? _lastTapTime;
  int? _lastTappedIndex;

  // 双击返回退出：记录最后一次返回键按下时间
  DateTime? _lastBackPressTime;

  // 记账按钮相关状态
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  int? _hoveredIndex;
  OverlayEntry? _overlayEntry;
  final GlobalKey _centerButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 初始化记账按钮动画控制器
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOut,
    );

    // 后台刷新账本同步状态
    _refreshLedgersStatusInBackground();

    // 监听语言变化，更新快捷方式
    ref.listen(languageProvider, (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateQuickActions();
      });
    });

    // 设置快捷方式
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateQuickActions();
    });
  }

  /// 更新快捷方式
  Future<void> _updateQuickActions() async {
    try {
      final quickActions = QuickActions();
      final l10n = AppLocalizations.of(context);

      // 设置快捷方式
      await quickActions.setShortcutItems([
        ShortcutItem(
          type: 'action_album',
          localizedTitle: l10n.quickActionImage,
          icon: Platform.isAndroid ? 'ic_quick_image' : 'ic_quick_image',
        ),
        ShortcutItem(
          type: 'action_camera',
          localizedTitle: l10n.quickActionCamera,
          icon: Platform.isAndroid ? 'ic_quick_camera' : 'ic_quick_camera',
        ),
        ShortcutItem(
          type: 'action_voice',
          localizedTitle: l10n.quickActionVoice,
          icon: Platform.isAndroid ? 'ic_quick_voice' : 'ic_quick_voice',
        ),
        ShortcutItem(
          type: 'action_ai',
          localizedTitle: l10n.quickActionAI,
          icon: Platform.isAndroid ? 'ic_quick_ai' : 'ic_quick_ai',
        ),
      ]);

      print('✅ 快捷方式已更新');
    } catch (e) {
      print('⚠️  快捷方式更新失败（可能在不支持的平台上运行）: $e');
    }
  }

  /// 后台刷新账本同步状态
  void _refreshLedgersStatusInBackground() {
    Future.microtask(() async {
      try {
        final syncService = ref.read(syncServiceProvider);
        if (syncService is TransactionsSyncManager) {
          await syncService.refreshAllLedgersStatus();
          // 刷新完成后触发账本列表更新
          ref.read(ledgerListRefreshProvider.notifier).state++;
        }
      } catch (e) {
        // 静默失败，不影响App启动
      }
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    _expandController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _expandController.forward();
    _showOverlay();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _updateHoveredIndex(details.globalPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final centerActions = [
      SpeedDialAction(
        icon: Icons.camera_alt_rounded,
        label: AppLocalizations.of(context).fabActionCamera,
        onTap: () => ImageBillingHelper.openCameraForBilling(context, ref),
      ),
      SpeedDialAction(
        icon: Icons.photo_library_rounded,
        label: AppLocalizations.of(context).fabActionGallery,
        onTap: () => ImageBillingHelper.pickImageForBilling(context, ref),
      ),
      SpeedDialAction(
        icon: Icons.mic_rounded,
        label: AppLocalizations.of(context).fabActionVoice,
        onTap: () => VoiceBillingHelper.startVoiceBilling(context, ref),
      ),
    ];

    if (_hoveredIndex != null && _hoveredIndex! < centerActions.length) {
      final action = centerActions[_hoveredIndex!];
      if (action.enabled && action.onTap != null) {
        action.onTap!();
      }
    }

    _hoveredIndex = null;
    _expandController.reverse();
    _removeOverlay();
  }

  void _showOverlay() {
    final RenderBox? renderBox =
        _centerButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _SpeedDialOverlay(
        buttonPosition: position,
        buttonSize: size,
        actions: [
          SpeedDialAction(
            icon: Icons.camera_alt_rounded,
            label: AppLocalizations.of(context).fabActionCamera,
            onTap: () => ImageBillingHelper.openCameraForBilling(context, ref),
          ),
          SpeedDialAction(
            icon: Icons.photo_library_rounded,
            label: AppLocalizations.of(context).fabActionGallery,
            onTap: () => ImageBillingHelper.pickImageForBilling(context, ref),
          ),
          SpeedDialAction(
            icon: Icons.mic_rounded,
            label: AppLocalizations.of(context).fabActionVoice,
            onTap: () => VoiceBillingHelper.startVoiceBilling(context, ref),
          ),
        ],
        animation: _expandAnimation,
        hoveredIndex: _hoveredIndex,
        backgroundColor: ref.read(primaryColorProvider),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateHoveredIndex(Offset globalPosition) {
    final RenderBox? renderBox =
        _centerButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;
    final buttonCenter = Offset(
      buttonPosition.dx + buttonSize.width / 2,
      buttonPosition.dy + buttonSize.height / 2,
    );

    final angles = [210.0, 270.0, 330.0];
    const distance = 85.0;
    const buttonRadius = 26.0;

    int? newHoveredIndex;
    for (int i = 0; i < 3 && i < angles.length; i++) {
      final angle = angles[i];
      final radians = angle * 3.14159265359 / 180;
      final offsetX = distance * _cos(radians);
      final offsetY = distance * _sin(radians);

      final actionCenter = Offset(
        buttonCenter.dx + offsetX,
        buttonCenter.dy + offsetY,
      );

      final dx = globalPosition.dx - actionCenter.dx;
      final dy = globalPosition.dy - actionCenter.dy;
      final distanceToButton = _sqrt(dx * dx + dy * dy);

      if (distanceToButton <= buttonRadius) {
        newHoveredIndex = i;
        break;
      }
    }

    if (newHoveredIndex != _hoveredIndex) {
      setState(() {
        _hoveredIndex = newHoveredIndex;
      });
      _overlayEntry?.markNeedsBuild();
    }
  }

  static double _cos(double x) {
    x = x % (2 * 3.14159265359);
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  static double _sin(double x) {
    x = x % (2 * 3.14159265359);
    double result = x;
    double term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  static double _sqrt(double x) {
    if (x < 0) return double.nan;
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive) {
      // 多任务切换时显示隐私模糊屏（仅在应用锁启用时）
      if (ref.read(appLockEnabledProvider)) {
        ref.read(showPrivacyScreenProvider.notifier).state = true;
      }
    } else if (state == AppLifecycleState.paused) {
      // 记录进入后台时间
      AppLockService.recordBackgroundTime();
    } else if (state == AppLifecycleState.resumed) {
      // 移除隐私模糊屏
      ref.read(showPrivacyScreenProvider.notifier).state = false;
      // 检查是否需要锁定
      _checkAppLockOnResume();
      // 当app从后台恢复到前台时，更新小组件数据
      _updateWidget();
    }
  }

  Future<void> _checkAppLockOnResume() async {
    final shouldLock = await AppLockService.shouldLockOnResume();
    if (shouldLock && mounted) {
      ref.read(isAppLockedProvider.notifier).state = true;
    }
  }

  Future<void> _updateWidget() async {
    try {
      final repository = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final primaryColor = ref.read(primaryColorProvider);
      final redForIncome = ref.read(incomeExpenseColorSchemeProvider);

      final widgetManager = WidgetManager();
      await widgetManager.updateWidget(
        repository,
        ledgerId,
        primaryColor,
        redForIncome: redForIncome,
      );
      print('✅ App恢复前台，小组件数据已更新');
    } catch (e) {
      print('❌ 更新小组件失败: $e');
    }
  }

  /// 处理快捷方式事件
  void _handleQuickAction(QuickActionType type) {
    switch (type) {
      case QuickActionType.album:
        // 图片记账（从相册获取图片）
        ImageBillingHelper.pickImageForBilling(context, ref);
        break;
      case QuickActionType.camera:
        // 拍照记账
        ImageBillingHelper.openCameraForBilling(context, ref);
        break;
      case QuickActionType.voice:
        // 语音记账
        VoiceBillingHelper.startVoiceBilling(context, ref);
        break;
      case QuickActionType.ai:
        // AI 助手
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AIChatPage(),
          ),
        );
        break;
      case QuickActionType.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(bottomTabIndexProvider);
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final avatarPath = ref.watch(avatarPathProvider).asData?.value;

    // 监听快捷方式事件
    final quickActionState = ref.watch(quickActionProvider);
    if (!quickActionState.isHandled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleQuickAction(quickActionState.type);
        ref.read(quickActionProvider.notifier).markAsHandled();
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;

        final now = DateTime.now();

        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          showToast(context, l10n.commonPressAgainToExit);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            extendBody: true, // 让页面内容延伸到底部栏后面
            body: IndexedStack(
              index: idx,
              children: _pages,
            ),
            bottomNavigationBar: _BeeBottomBar(
              currentIndex: idx,
              primaryColor: primaryColor,
              isDark: isDark,
              bottomPadding: bottomPadding,
              l10n: l10n,
              avatarPath: avatarPath,
              centerButtonKey: _centerButtonKey,
              onTabTap: (index) {
                final now = DateTime.now();
                if (_lastTappedIndex == index &&
                    _lastTapTime != null &&
                    now.difference(_lastTapTime!) <
                        const Duration(milliseconds: 300)) {
                  if (index == 0) {
                    ref.read(homeScrollToTopProvider.notifier).state++;
                  }
                  _lastTapTime = null;
                  _lastTappedIndex = null;
                } else {
                  _lastTapTime = now;
                  _lastTappedIndex = index;
                  ref.read(bottomTabIndexProvider.notifier).state = index;
                }
              },
              onCenterTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TransactionEditorPage(
                      initialKind: 'expense',
                      quickAdd: true,
                    ),
                  ),
                );
              },
              onCenterLongPressStart: _onLongPressStart,
              onCenterLongPressMoveUpdate: _onLongPressMoveUpdate,
              onCenterLongPressEnd: _onLongPressEnd,
            ),
          ),
          // 开发模式下的主题切换按钮
          if (kDebugMode)
            Positioned(
              right: 16,
              bottom: 100,
              child: FloatingActionButton.small(
                heroTag: 'themeSwitcher',
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
                onPressed: () {
                  final current = ref.read(themeModeProvider);
                  final next = current == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                  ref.read(themeModeProvider.notifier).state = next;
                },
                child: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Telegram 风格悬浮胶囊底部导航栏
class _BeeBottomBar extends StatelessWidget {
  final int currentIndex;
  final Color primaryColor;
  final bool isDark;
  final double bottomPadding;
  final AppLocalizations l10n;
  final String? avatarPath;
  final GlobalKey centerButtonKey;
  final ValueChanged<int> onTabTap;
  final VoidCallback onCenterTap;
  final GestureLongPressStartCallback onCenterLongPressStart;
  final GestureLongPressMoveUpdateCallback onCenterLongPressMoveUpdate;
  final GestureLongPressEndCallback onCenterLongPressEnd;

  const _BeeBottomBar({
    required this.currentIndex,
    required this.primaryColor,
    required this.isDark,
    required this.bottomPadding,
    required this.l10n,
    this.avatarPath,
    required this.centerButtonKey,
    required this.onTabTap,
    required this.onCenterTap,
    required this.onCenterLongPressStart,
    required this.onCenterLongPressMoveUpdate,
    required this.onCenterLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = BeeTokens.tabBarBackground(context);
    final inactiveColor = isDark ? Colors.white70 : Colors.black54;

    const barHeight = 56.0;

    return SizedBox(
      height: barHeight + bottomPadding + 12, // 12dp 浮动间距
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: bottomPadding + 12,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: BeeTokens.tabBarShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Row(
              children: [
                _buildTabItem(0, Icons.receipt_long_outlined,
                    Icons.receipt_long, l10n.tabHome, inactiveColor),
                _buildTabItem(1, Icons.pie_chart_outline_rounded,
                    Icons.pie_chart_rounded, l10n.tabInsights, inactiveColor),
                // 中间记账按钮（作为 Tab 样式）
                _buildCenterTabItem(inactiveColor),
                _buildTabItem(
                    2,
                    Icons.account_balance_wallet_outlined,
                    Icons.account_balance_wallet,
                    l10n.tabAssets,
                    inactiveColor),
                _buildAvatarTabItem(3, l10n.tabMine, inactiveColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, IconData activeIcon,
      String label, Color inactiveColor) {
    final isActive = index == currentIndex;
    final iconColor = isActive ? primaryColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTabTap(index),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? primaryColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isActive ? activeIcon : icon, color: iconColor, size: 22),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? primaryColor : inactiveColor,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterTabItem(Color inactiveColor) {
    return Expanded(
      child: GestureDetector(
        key: centerButtonKey,
        behavior: HitTestBehavior.opaque,
        onTap: onCenterTap,
        onLongPressStart: onCenterLongPressStart,
        onLongPressMoveUpdate: onCenterLongPressMoveUpdate,
        onLongPressEnd: onCenterLongPressEnd,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, color: inactiveColor, size: 22),
              const SizedBox(height: 1),
              Text(
                l10n.tabRecord,
                style: TextStyle(
                  fontSize: 10,
                  color: inactiveColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarTabItem(int index, String label, Color inactiveColor) {
    final isActive = index == currentIndex;
    final hasAvatar = avatarPath != null;

    Widget iconWidget;
    if (hasAvatar) {
      iconWidget = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isActive ? Border.all(color: primaryColor, width: 1.5) : null,
          image: DecorationImage(
            image: FileImage(File(avatarPath!)),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      iconWidget = Icon(
          isActive ? Icons.person_rounded : Icons.person_outline_rounded,
          color: isActive ? primaryColor : inactiveColor,
          size: 24);
    }

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTabTap(index),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? primaryColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconWidget,
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? primaryColor : inactiveColor,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 扇形菜单覆盖层
class _SpeedDialOverlay extends StatelessWidget {
  final Offset buttonPosition;
  final Size buttonSize;
  final List<SpeedDialAction> actions;
  final Animation<double> animation;
  final int? hoveredIndex;
  final Color backgroundColor;

  const _SpeedDialOverlay({
    required this.buttonPosition,
    required this.buttonSize,
    required this.actions,
    required this.animation,
    required this.hoveredIndex,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final buttonCenter = Offset(
      buttonPosition.dx + buttonSize.width / 2,
      buttonPosition.dy + buttonSize.height / 2,
    );

    final angles = [210.0, 270.0, 330.0];
    const distance = 85.0;
    const pi = 3.14159265359;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        if (animation.value == 0) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3 * animation.value),
                ),
              ),
            ),
            for (int i = 0; i < actions.length && i < angles.length; i++)
              Builder(builder: (context) {
                final angle = angles[i];
                final radians = angle * pi / 180;
                final progress = animation.value;
                final offsetX = progress * distance * _cos(radians);
                final offsetY = progress * distance * _sin(radians);

                const btnSize = 48.0;
                final left = buttonCenter.dx + offsetX - btnSize / 2;
                final top = buttonCenter.dy + offsetY - btnSize / 2;

                final isEnabled = actions[i].enabled;
                final bgColor =
                    isEnabled ? backgroundColor : Colors.grey.shade400;
                final isHovered = i == hoveredIndex;

                return Positioned(
                  left: left,
                  top: top,
                  child: Transform.scale(
                    scale: progress,
                    child: Opacity(
                      opacity: progress,
                      child: AnimatedScale(
                        scale: isHovered ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Material(
                          color: bgColor,
                          shape: const CircleBorder(),
                          elevation: isHovered ? 8 : 4,
                          child: Container(
                            width: btnSize,
                            height: btnSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: isHovered
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                            ),
                            child: Icon(
                              actions[i].icon,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  static double _cos(double x) {
    x = x % (2 * 3.14159265359);
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  static double _sin(double x) {
    x = x % (2 * 3.14159265359);
    double result = x;
    double term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }
}
