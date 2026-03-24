import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/main/home_page.dart';
import 'pages/main/analytics_page.dart';
import 'pages/main/discover_page.dart';
import 'pages/main/mine_page.dart';
import 'pages/transaction/transaction_editor_page.dart';
import 'providers.dart';
import 'l10n/app_localizations.dart';
import 'widget/widget_manager.dart';
import 'widgets/ui/ui.dart';
import 'widgets/ui/speed_dial_fab.dart';
import 'cloud/transactions_sync_manager.dart';
import 'utils/voice_billing_helper.dart';
import 'utils/image_billing_helper.dart';
import 'services/ai/ai_constants.dart';
import 'pages/ai/ai_chat_page.dart';
import 'services/platform/app_link_service.dart';
import 'services/platform/quick_actions_service.dart';
import 'services/system/logger_service.dart';
import 'services/security/app_lock_service.dart';
import 'providers/security_providers.dart';

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
    DiscoverPage(),
    MinePage(),
  ];

  // 双击检测：记录最后一次点击的时间和索引
  DateTime? _lastTapTime;
  int? _lastTappedIndex;

  // 双击返回退出：记录最后一次返回键按下时间
  DateTime? _lastBackPressTime;

  // AppLink 监听订阅
  ProviderSubscription<AppLinkAction?>? _appLinkSubscription;

  // 快捷操作服务
  final QuickActionsService _quickActionsService = QuickActionsService();

  // 防止 AppLink 动作重复执行（使用静态变量，跨实例共享）
  static bool _isHandlingAppLink = false;
  static DateTime? _lastAppLinkHandleTime;

  // 记账按钮相关状态
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  bool _isOpen = false;
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
    // 延迟监听 AppLink，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAppLinkListener();
      _setupQuickActions();
    });
  }

  /// 设置快捷操作
  void _setupQuickActions() {
    logger.info('QuickActions', 'BeeApp: 设置快捷操作服务...');
    _quickActionsService.onNavigate = (action) {
      if (mounted) {
        logger.info('QuickActions', 'BeeApp: 执行快捷操作 $action');
        _handleAppLinkAction(context, action);
      }
    };
    _quickActionsService.initialize();
    // 处理可能在初始化前就触发的快捷操作
    _quickActionsService.processPendingAction();
    logger.info('QuickActions', 'BeeApp: 快捷操作服务已设置');
  }

  /// 设置 AppLink 监听
  void _setupAppLinkListener() {
    logger.info('AppLink', 'BeeApp: 设置 AppLink 监听...');
    _appLinkSubscription = ref.listenManual<AppLinkAction?>(
      pendingAppLinkActionProvider,
      (previous, next) {
        logger.info('AppLink',
            'BeeApp: 监听触发 previous=$previous, next=$next, mounted=$mounted');
        if (next != null && mounted) {
          logger.info('AppLink', 'BeeApp: 执行动作 $next');
          _handleAppLinkAction(context, next);
          // 清除待处理动作
          ref.read(pendingAppLinkActionProvider.notifier).state = null;
        }
      },
      fireImmediately: true,
    );
    logger.info('AppLink', 'BeeApp: AppLink 监听已设置');
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

  /// 处理 AppLink 动作
  void _handleAppLinkAction(BuildContext context, AppLinkAction action) {
    // 防止重复执行（使用时间戳和标志双重检查）
    final now = DateTime.now();
    if (_isHandlingAppLink ||
        (_lastAppLinkHandleTime != null &&
            now.difference(_lastAppLinkHandleTime!) <
                const Duration(seconds: 1))) {
      logger.info('AppLink', 'BeeApp: 忽略重复的动作 $action');
      return;
    }
    _isHandlingAppLink = true;
    _lastAppLinkHandleTime = now;

    // 延迟重置标志，允许下一次动作
    Future.delayed(const Duration(seconds: 1), () {
      _isHandlingAppLink = false;
    });

    switch (action) {
      case AppLinkAction.voice:
        // 打开语音记账
        VoiceBillingHelper.startVoiceBilling(context, ref);
        break;
      case AppLinkAction.image:
        // 打开图片记账（从相册）
        ImageBillingHelper.pickImageForBilling(context, ref);
        break;
      case AppLinkAction.camera:
        // 打开拍照记账
        ImageBillingHelper.openCameraForBilling(context, ref);
        break;
      case AppLinkAction.aiChat:
        // 打开 AI 小助手
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AIChatPage()),
        );
        break;
      default:
        // 其他动作在 AppLinkService 中已处理
        break;
    }
  }

  /// 检查语音识别是否可用（需要开启AI智能识别并配置GLM API Key）
  Future<bool> _checkGlmApiKeyConfigured() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final aiEnabled =
          prefs.getBool(AIConstants.keyAiBillExtractionEnabled) ?? false;
      final apiKey = prefs.getString(AIConstants.keyGlmApiKey) ?? '';
      return aiEnabled && apiKey.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _appLinkSubscription?.close();
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
    setState(() {
      _isOpen = true;
      _expandController.forward();
    });
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

    setState(() {
      _isOpen = false;
      _hoveredIndex = null;
      _expandController.reverse();
    });
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

  /// 构建记账按钮（独立在 Stack 最上层，防止点击穿透）
  Widget _buildCenterButton(Color primaryColor, double bottomPadding) {
    const barHeight = 56.0;
    const buttonSize = 64.0;
    const buttonOverhang = buttonSize - (barHeight - 8);

    return Positioned(
      left: 0,
      right: 0,
      bottom: barHeight + bottomPadding - buttonOverhang - 52, // 往下移12像素
      child: Center(
        child: GestureDetector(
          key: _centerButtonKey,
          behavior: HitTestBehavior.opaque, // 防止点击穿透
          onTap: () {
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
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMoveUpdate,
          onLongPressEnd: _onLongPressEnd,
          child: Container(
            // 扩大点击区域，防止误触交易记录
            padding: const EdgeInsets.all(20),
            child: AnimatedBuilder(
              animation: _expandAnimation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _expandAnimation.value * 3.14159265359 / 4,
                  child: Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isOpen ? Icons.close : Icons.add,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(bottomTabIndexProvider);
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

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
            ),
          ),
          // 记账按钮（提升到 Stack 最上层，防止点击穿透）
          _buildCenterButton(primaryColor, bottomPadding),
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

/// FAB 长按提示气泡组件（带箭头和呼吸动画）
class _FabTipBubble extends StatefulWidget {
  final String text;
  final Color primaryColor;
  final VoidCallback onDismiss;

  const _FabTipBubble({
    required this.text,
    required this.primaryColor,
    required this.onDismiss,
  });

  @override
  State<_FabTipBubble> createState() => _FabTipBubbleState();
}

class _FabTipBubbleState extends State<_FabTipBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor;

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 气泡主体
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.touch_app,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
            // 箭头指向 FAB
            CustomPaint(
              size: const Size(16, 10),
              painter: _ArrowPainter(color: primaryColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// 箭头绘制器
class _ArrowPainter extends CustomPainter {
  final Color color;

  _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 闲鱼风格底部导航栏（带圆滑凸起，记账按钮已独立）
class _BeeBottomBar extends StatelessWidget {
  final int currentIndex;
  final Color primaryColor;
  final bool isDark;
  final double bottomPadding;
  final AppLocalizations l10n;
  final ValueChanged<int> onTabTap;

  const _BeeBottomBar({
    required this.currentIndex,
    required this.primaryColor,
    required this.isDark,
    required this.bottomPadding,
    required this.l10n,
    required this.onTabTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final inactiveColor = isDark ? Colors.white70 : Colors.black54;

    const barHeight = 56.0;
    const buttonSize = 64.0; // 按钮大小
    const bumpHeight = 20.0; // 凸起背景的高度
    const bumpExtraWidth = 2.0; // 凸起比按钮宽多少（每侧）

    return SizedBox(
      height: barHeight + bottomPadding,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 背景（使用 CustomPaint 绘制圆滑凸起）
          Positioned.fill(
            child: CustomPaint(
              painter: _SmoothBumpPainter(
                color: bgColor,
                bumpHalfWidth: buttonSize / 2 + bumpExtraWidth, // 凸起的半宽度
                bumpHeight: bumpHeight, // 凸起高度
              ),
            ),
          ),

          // Tab 项
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: barHeight,
            child: Row(
              children: [
                _buildTabItem(
                    0, Icons.list_alt_outlined, l10n.tabHome, inactiveColor),
                _buildTabItem(1, Icons.pie_chart_outline_rounded,
                    l10n.tabAnalytics, inactiveColor),
                // 中间占位（记账按钮已独立到外层 Stack）
                const Expanded(child: SizedBox()),
                _buildTabItem(
                    2, Icons.explore_outlined, l10n.tabDiscover, inactiveColor),
                _buildTabItem(3, Icons.person_outline_rounded, l10n.tabMine,
                    inactiveColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(
      int index, IconData icon, String label, Color inactiveColor) {
    final isActive = index == currentIndex;
    final iconColor = isActive ? primaryColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTabTap(index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: inactiveColor, // 文字颜色不变
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆滑凸起背景绘制器 - 闲鱼风格
class _SmoothBumpPainter extends CustomPainter {
  final Color color;
  final double bumpHalfWidth; // 凸起的半宽度（从中心到起点的距离）
  final double bumpHeight; // 凸起的高度

  _SmoothBumpPainter({
    required this.color,
    required this.bumpHalfWidth,
    required this.bumpHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    // 计算圆弧半径，使圆弧顶点刚好到达 bumpHeight 高度
    // 公式：r = (h^2 + w^2) / (2*h)
    final arcRadius =
        (bumpHeight * bumpHeight + bumpHalfWidth * bumpHalfWidth) /
            (2 * bumpHeight);

    final path = Path();

    // 从左下角开始
    path.moveTo(0, size.height);
    path.lineTo(0, 0);

    // 左边平直部分到凸起开始
    path.lineTo(centerX - bumpHalfWidth, 0);

    // 使用圆弧绘制凸起（向上凸出，顺时针方向）
    path.arcToPoint(
      Offset(centerX + bumpHalfWidth, 0),
      radius: Radius.circular(arcRadius),
      clockwise: true,
    );

    // 右边平直部分
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.close();

    // 绘制背景
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SmoothBumpPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.bumpHalfWidth != bumpHalfWidth ||
        oldDelegate.bumpHeight != bumpHeight;
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
