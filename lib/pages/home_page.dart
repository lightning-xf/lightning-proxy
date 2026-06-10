import 'dart:ui';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/widgets/animated_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightning/core/config_generator.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/utils/format_utils.dart';
import 'package:lightning/core/traffic_monitor.dart';
import 'package:lightning/pages/nodes_page.dart';
import 'package:lightning/pages/subscriptions_page.dart';
import 'package:lightning/pages/logs_page.dart';
import 'package:lightning/pages/settings_page.dart';
import 'package:window_manager/window_manager.dart';

import 'package:lightning/core/app_visibility_provider.dart';

class PageIndexState {
  final int index;
  final bool animate;
  PageIndexState(this.index, {this.animate = false});
}

class PageIndexNotifier extends StateNotifier<PageIndexState> {
  PageIndexNotifier() : super(PageIndexState(0)) {
    _load();
  }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('page_index') ?? 0;
    state = PageIndexState(index);
  }

  Future<void> setIndex(int index, {bool animate = false}) async {
    state = PageIndexState(index, animate: animate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('page_index', index);
  }
}

final pageIndexProvider =
    StateNotifierProvider<PageIndexNotifier, PageIndexState>((ref) {
  return PageIndexNotifier();
});

class SidebarExpandedNotifier extends StateNotifier<bool> {
  SidebarExpandedNotifier() : super(true) {
    _load();
  }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('sidebar_expanded') ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sidebar_expanded', state);
  }

  Future<void> setExpanded(bool expanded) async {
    if (state == expanded) return;
    state = expanded;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sidebar_expanded', state);
  }
}

final sidebarExpandedProvider =
    StateNotifierProvider<SidebarExpandedNotifier, bool>((ref) {
  return SidebarExpandedNotifier();
});

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  double? _lastScreenWidth;

  @override
  Widget build(BuildContext context) {
    final pageIndexState = ref.watch(pageIndexProvider);
    final vpnState = ref.watch(vpnProvider);
    final isVisible = ref.watch(appVisibilityProvider);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        // 🚀 响应式策略优化：仅在跨越阈值时自动调整
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final notifier = ref.read(sidebarExpandedProvider.notifier);
          final isExpanded = ref.read(sidebarExpandedProvider);

          if (_lastScreenWidth == null) {
            // 首次加载
            if (screenWidth > 1100 && !isExpanded) {
              notifier.setExpanded(true);
            } else if (screenWidth < 900 && isExpanded) {
              notifier.setExpanded(false);
            }
          } else {
            // 💡 只有当宽度发生显著变化且跨越阈值时才触发状态变更，防止微小抖动触发重绘
            if ((_lastScreenWidth! - screenWidth).abs() > 5) {
              if (_lastScreenWidth! <= 1100 &&
                  screenWidth > 1100 &&
                  !isExpanded) {
                notifier.setExpanded(true);
              } else if (_lastScreenWidth! >= 900 &&
                  screenWidth < 900 &&
                  isExpanded) {
                notifier.setExpanded(false);
              }
            }
          }
          _lastScreenWidth = screenWidth;
        });

        // [P1] 监听内核错误并弹出引导式诊断 UI
        ref.listen<VpnState>(vpnProvider, (previous, next) {
          if (next.lastError != null && next.lastError != previous?.lastError) {
            _showDiagnosticDialog(context, next.lastError!);
          }
        });

        if (!isVisible) {
          return const SizedBox.shrink();
        }

        return _buildWindowsLayout(
            context, ref, pageIndexState, vpnState, isVisible, screenWidth);
      },
    );
  }

  void _showDiagnosticDialog(BuildContext context, String message) {
    final s = S.of(context, ref);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.healing_rounded,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(s.get('failure_diagnosis'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.1)),
              ),
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.get('diagnostic_suggestion'),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(vpnProvider.notifier).clearError();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(s.get('got_it'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowsLayout(
    BuildContext context,
    WidgetRef ref,
    PageIndexState pageIndexState,
    VpnState vpnState,
    bool isVisible,
    double screenWidth,
  ) {
    final theme = Theme.of(context);
    final isExpanded = ref.watch(sidebarExpandedProvider);
    final currentIndex = pageIndexState.index;

    // 🚀 响应式内容宽度：全屏时撑开，不留大白边
    // 如果屏幕宽度 > 1200px，内容区最大宽度也随之增大
    final double contentMaxWidth =
        screenWidth > 1400 ? screenWidth * 0.85 : 1200;

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // 🚀 【极致性能优化】移除所有渐变背景，彻底降低 GPU 负载
          Padding(
            padding: EdgeInsets.only(top: Platform.isWindows ? 32 : 0),
            child: Row(
              children: [
                RepaintBoundary(
                  child: _buildSidebar(
                      context, ref, currentIndex, isExpanded, isVisible),
                ),
                Expanded(
                  child: RepaintBoundary(
                    child: ClipRect(
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: contentMaxWidth),
                            child: _buildMainContent(
                              context,
                              ref,
                              pageIndexState,
                              vpnState,
                              contentMaxWidth,
                              isVisible,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 🚀 无边框自定义标题栏 - 移动到 Stack 最后，确保处于绝对顶层
          if (Platform.isWindows)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: _buildCustomTitleBar(context, theme),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomTitleBar(BuildContext context, ThemeData theme) {
    return Container(
      height: 32,
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // 🚀 垂直居中
        children: [
          // 🚀 拖拽区域
          const Expanded(
            child: DragToMoveArea(
              child: SizedBox.expand(),
            ),
          ),
          // 🚀 按钮区域
          _buildCustomWindowButtons(theme),
        ],
      ),
    );
  }

  Widget _buildCustomWindowButtons(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    // 🚀 使用带一点阴影或发光效果的颜色，确保在渐变色背景下清晰可见
    final Color iconColor = isDark ? Colors.white : Colors.black;
    final Color hoverBg =
        isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.1);

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 缩小按钮
          _TitleBarButton(
            customIcon: Container(
              width: 12,
              height: 1.5,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            onTap: () {
              // 🛡️ 统一使用 Provider 驱动，确保触发完整的物理挂起逻辑
              ref.read(appVisibilityProvider.notifier).state = false;
              windowManager.minimize();
            },
            hoverColor: hoverBg,
            iconColor: iconColor,
          ),
          // 全屏/非全屏按钮
          FutureBuilder<bool>(
            future: windowManager.isMaximized(),
            builder: (context, snapshot) {
              final isMaximized = snapshot.data ?? false;
              return _TitleBarButton(
                icon: isMaximized
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                onTap: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                  setState(() {});
                },
                hoverColor: hoverBg,
                iconColor: iconColor,
              );
            },
          ),
          // 关闭按钮
          _TitleBarButton(
            icon: Icons.close_rounded,
            onTap: () async {
              final vpnSettings = ref.read(vpnSettingsProvider);
              if (vpnSettings.hideToTray) {
                // 🛡️ 统一使用 Provider 驱动，确保触发完整的物理挂起逻辑
                ref.read(appVisibilityProvider.notifier).state = false;
                await windowManager.hide();
              } else {
                final vpnNotifier = ref.read(vpnProvider.notifier);
                await vpnNotifier.stopProxy();
                await windowManager.destroy();
                exit(0);
              }
            },
            hoverColor: Colors.red.withOpacity(0.9),
            iconColor: iconColor,
            hoverIconColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(
      BuildContext context, WidgetRef ref, int currentIndex, bool isVisible) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final s = S.of(context, ref);

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      width: MediaQuery.of(context).size.width * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 80, 32, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AnimatedLogo(size: 72),
                const SizedBox(height: 28),
                const Text(
                  'Lightning',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.get('app_subtitle'),
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildDrawerItem(
                  ref,
                  context,
                  0,
                  Icons.grid_view_rounded,
                  s.get('control_panel'),
                  currentIndex,
                  accentColor,
                ),
                _buildDrawerItem(
                  ref,
                  context,
                  1,
                  Icons.dns_rounded,
                  s.get('nodes_manage'),
                  currentIndex,
                  accentColor,
                ),
                _buildDrawerItem(
                  ref,
                  context,
                  2,
                  Icons.rss_feed_rounded,
                  s.get('sub_settings'),
                  currentIndex,
                  accentColor,
                ),
                _buildDrawerItem(
                  ref,
                  context,
                  3,
                  Icons.terminal_rounded,
                  s.get('realtime_logs'),
                  currentIndex,
                  accentColor,
                ),
                _buildDrawerItem(
                  ref,
                  context,
                  4,
                  Icons.settings_rounded,
                  s.get('advanced_config'),
                  currentIndex,
                  accentColor,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(color: Colors.white.withOpacity(0.05)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 16,
                      color: accentColor.withOpacity(0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.get('app_version'),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    WidgetRef ref,
    BuildContext context,
    int index,
    IconData icon,
    String label,
    int currentIndex,
    Color accentColor,
  ) {
    final isSelected = currentIndex == index;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: () {
          HapticFeedback.lightImpact();
          ref.read(pageIndexProvider.notifier).setIndex(index);
          Navigator.pop(context);
        },
        leading: Icon(
          icon,
          color: isSelected ? accentColor : theme.textTheme.bodySmall?.color,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? accentColor : theme.textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 15,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        selected: isSelected,
        selectedTileColor: accentColor.withValues(alpha: 0.1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    WidgetRef ref,
    int currentIndex,
    bool isExpanded,
    bool isVisible,
  ) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final s = S.of(context, ref);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: isExpanded ? 260 : 88,
      decoration: BoxDecoration(
        // 🚀 【性能重构】移除 BackdropFilter 依赖
        // 使用更高不透明度的纯色，在不牺牲质感的前提下，将 GPU 消耗降至 0
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF1E293B).withOpacity(0.95)
            : Colors.white.withOpacity(0.98),
        border: Border(
          right: BorderSide(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 32), // 🚀 对齐标题栏高度 32
          // Logo 区域
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? 16 : 0), // 🚀 收缩时取消水平边距
            child: InkWell(
              onTap: () async {
                HapticFeedback.selectionClick();
                await ref.read(sidebarExpandedProvider.notifier).toggle();
              },
              hoverColor: theme.brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isExpanded ? null : 88, // 🚀 固定收缩时宽度 88
                padding: EdgeInsets.symmetric(
                  horizontal: isExpanded ? 16 : 0,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.transparent,
                ),
                child: Row(
                  mainAxisAlignment: isExpanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    AnimatedLogo(
                        size: isExpanded ? 52 : 36), // 🚀 使用统一的 AnimatedLogo
                    if (isExpanded) ...[
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Lightning',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: isExpanded ? 14 : 0), // 🚀 收缩时取消水平边距
              children: [
                _buildSidebarItem(
                  context,
                  ref,
                  0,
                  Icons.dashboard_customize_rounded,
                  s.get('control_panel'),
                  currentIndex,
                  isExpanded,
                  accentColor,
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  1,
                  Icons.lan_rounded,
                  s.get('nodes_manage'),
                  currentIndex,
                  isExpanded,
                  accentColor,
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  2,
                  Icons.hub_rounded,
                  s.get('sub_settings'),
                  currentIndex,
                  isExpanded,
                  accentColor,
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  3,
                  Icons.terminal_rounded,
                  s.get('realtime_logs'),
                  currentIndex,
                  isExpanded,
                  accentColor,
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  4,
                  Icons.tune_rounded,
                  s.get('advanced_config'),
                  currentIndex,
                  isExpanded,
                  accentColor,
                ),
              ],
            ),
          ),
          _buildSidebarFooter(isExpanded, theme),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter(bool isExpanded, ThemeData theme) {
    final s = S.of(context, ref);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (isExpanded)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.get('app_status_stable'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              HapticFeedback.selectionClick();
              await ref.read(sidebarExpandedProvider.notifier).toggle();
            },
            hoverColor: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 44,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Icon(
                isExpanded
                    ? Icons.keyboard_double_arrow_left_rounded
                    : Icons.keyboard_double_arrow_right_rounded,
                color: Colors.grey.shade500,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context,
    WidgetRef ref,
    int index,
    IconData icon,
    String label,
    int currentIndex,
    bool isExpanded,
    Color accentColor,
  ) {
    final isSelected = currentIndex == index;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            ref.read(pageIndexProvider.notifier).setIndex(index);
          },
          hoverColor: theme.brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            width: isExpanded ? null : 88,
            padding: EdgeInsets.symmetric(horizontal: isExpanded ? 16 : 0),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.2)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isSelected
                      ? accentColor
                      : theme.textTheme.bodySmall?.color,
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.visible,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected
                            ? accentColor
                            : theme.textTheme.bodyMedium?.color,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    WidgetRef ref,
    PageIndexState pageIndexState,
    VpnState vpnState,
    double maxWidth,
    bool isVisible,
  ) {
    final pageIndex = pageIndexState.index;
    Widget child;
    switch (pageIndex) {
      case 0:
        child = _HomeContent(
          vpnState: vpnState,
          maxWidth: maxWidth,
          isVisible: isVisible,
          key: const ValueKey(0),
        );
        break;
      case 1:
        child = const NodesPage(key: ValueKey(1));
        break;
      case 2:
        child = const SubscriptionsPage(key: ValueKey(2));
        break;
      case 3:
        child = const LogsPage(key: ValueKey(3));
        break;
      case 4:
        child = const SettingsPage(key: ValueKey(4));
        break;
      default:
        child = _HomeContent(
          vpnState: vpnState,
          maxWidth: maxWidth,
          isVisible: isVisible,
          key: const ValueKey(0),
    );
  }

    if (!pageIndexState.animate) return child;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: child,
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1.0;

    const spacing = 40.0;
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _HomeContent extends ConsumerWidget {
  final VpnState vpnState;
  final double maxWidth;
  final bool isVisible;
  const _HomeContent({
    super.key,
    required this.vpnState,
    required this.maxWidth,
    required this.isVisible,
  });

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context, ref);
    final selectedNodeRaw = ref.watch(selectedNodeProvider);
    final nodes = ref.watch(nodeProvider);

    ref.listen<VpnState>(vpnProvider, (previous, next) {
      if (next.lastError != null && next.lastError != previous?.lastError) {
        _showErrorDialog(context, ref, next.lastError!);
      }
    });

    final selectedNode = selectedNodeRaw == null
        ? null
        : nodes.where((n) => n.id == selectedNodeRaw.id).firstOrNull;
    final theme = Theme.of(context);
    final bool isMobile = maxWidth < 720;
    final bool isLargeScreen = maxWidth > 900;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: isMobile
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Icon(
                  Icons.menu_rounded,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Scaffold.of(context).openDrawer();
                },
              ),
              title: Text(
                s.get('control_panel'),
                style: TextStyle(
                  color: theme.textTheme.titleLarge?.color,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              centerTitle: true,
            )
          : null,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          maxWidth > 1200 ? 40 : 16,
          isMobile ? 8 : 20,
          maxWidth > 1200 ? 40 : 16,
          24,
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMainStatusCard(context, ref, selectedNode, isVisible),
                const SizedBox(height: 16),

                _buildSectionHeader(
                  context,
                  ref,
                  theme,
                  s.get('traffic_and_mode'),
                  helpText: s.get('traffic_and_mode_help'),
                ),
                _buildHorizontalDataPanel(context, ref, s, isVisible),

                const SizedBox(height: 16),

                _buildSectionHeader(
                  context,
                  ref,
                  theme,
                  s.get('tunnel_details'),
                  helpText: s.get('tunnel_details_help'), // 🚀 增加详情说明
                ),
                LayoutBuilder(
                  builder: (context, box) {
                    // 🚀 响应式卡片布局：超宽屏时三列显示，普通屏双列
                    if (box.maxWidth > 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: _buildCurrentNodeCard(
                                  context, ref, selectedNode)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildModeSelector(context, ref)),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: _buildCurrentNodeCard(
                                context, ref, selectedNode)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildModeSelector(context, ref)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, WidgetRef ref, ThemeData theme, String title,
      {String? helpText}) {
    final s = S.of(context, ref);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary.withOpacity(0.8),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.0,
            ),
          ),
          if (helpText != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _showHelpDialog(context, s, title, helpText),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.primary.withOpacity(0.4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showHelpDialog(
      BuildContext context, S s, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: Text(
          content,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('got_it'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(BuildContext context, WidgetRef ref, String error) {
    final s = S.of(context, ref);
    String displayError = error;
    if (error.contains('TUN_ELEVATION_FAILED')) {
      displayError = s.get('tun_uac_prompt');
    } else if (error.contains('wintun.dll')) {
      displayError = s.get('wintun_missing');
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ErrorDialog(
        error: displayError,
        onClose: () => ref.read(vpnProvider.notifier).clearError(),
      ),
    );
  }

  Widget _buildMainStatusCard(
    BuildContext context,
    WidgetRef ref,
    NodeModel? selectedNode,
    bool isVisible,
  ) {
    final s = S.of(context, ref);
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isRunning = ref.watch(vpnProvider.select((state) => state.isRunning));
    final isStarting =
        ref.watch(vpnProvider.select((state) => state.isStarting));

    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : theme.dividerTheme.color ?? Colors.black.withOpacity(0.12),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            ref.read(vpnProvider.notifier).toggleVpn(selectedNode);
          },
          hoverColor: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              // 🚀 【性能重构】移除昂贵的 BackdropFilter，改用纯色/渐变叠加
              // 这样可以减少 GPU 每一帧的像素混合计算
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.02)
                  : Colors.black.withOpacity(0.01),
              gradient: LinearGradient(
                colors: isRunning
                    ? [
                        primaryColor.withOpacity(0.15),
                        primaryColor.withOpacity(0.05),
                      ]
                    : [
                        theme.brightness == Brightness.dark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.03),
                        theme.brightness == Brightness.dark
                            ? Colors.white.withOpacity(0.02)
                            : Colors.black.withOpacity(0.01),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: isRunning
                                    ? [
                                        primaryColor,
                                        primaryColor.withOpacity(0.8),
                                      ]
                                    : [
                                        Colors.grey.shade700,
                                        Colors.grey.shade800,
                                      ],
                              ),
                              boxShadow: isRunning
                                  ? [
                                      BoxShadow(
                                        color:
                                            primaryColor.withOpacity(0.4),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isStarting
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    isRunning
                                        ? Icons.bolt_rounded
                                        : Icons.power_settings_new_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Consumer(
                                builder: (context, ref, child) {
                                  final stage = ref.watch(
                                    vpnProvider.select(
                                        (state) => state.connectionStage),
                                  );
                                  return Text(
                                    stage == 1
                                        ? s.get('connecting_to_network')
                                        : stage == 2
                                            ? s.get('encrypting_tunnel')
                                            : stage == 3
                                                ? s.get('vpn_running')
                                                : s.get('vpn_stopped'),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color:
                                          theme.textTheme.headlineSmall?.color,
                                      letterSpacing: -0.5,
                                    ),
                                    maxLines: 1,
                                  );
                                },
                              ),
                              const SizedBox(height: 1),
                              Text(
                                isRunning
                                    ? s.get('vpn_connected_success')
                                    : (isStarting
                                        ? s.get('initializing_protocol')
                                        : s.get('click_switch_to_start')),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.5),
                                  height: 1.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Transform.scale(
                          scale: 0.8,
                          child: CupertinoSwitch(
                            value: isRunning || isStarting,
                            activeColor: primaryColor,
                            onChanged: (v) {
                              HapticFeedback.heavyImpact();
                              if (v) {
                                if (selectedNode == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(s.get('select_node_first')),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }
                                ref
                                    .read(vpnProvider.notifier)
                                    .toggleVpn(selectedNode);
                              } else {
                                ref.read(vpnProvider.notifier).toggleVpn(null);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      color: theme.brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.04)
                          : Colors.black.withOpacity(0.04),
                      height: 1),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          child: Consumer(
                            builder: (context, ref, child) {
                              final duration = ref.watch(
                                vpnProvider.select((state) => state.duration),
                              );
                              return _buildInfoItem(
                                context,
                                s.get('duration'),
                                _formatDuration(duration),
                                Icons.timer_outlined,
                                s: s,
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: _buildInfoItem(
                            context,
                            s.get('protocol'),
                            isRunning
                                ? (selectedNode?.protocol.toUpperCase() ??
                                    'UNKNOWN')
                                : s.get('unknown'),
                            Icons.security_rounded,
                            s: s,
                          ),
                        ),
                        Expanded(
                          child: _buildInfoItem(
                            context,
                            s.get('status'),
                            isRunning ? s.get('stable') : s.get('standby'),
                            Icons.check_circle_outline_rounded,
                            color: isRunning ? const Color(0xFF00C853) : null,
                            s: s,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildInfoItem(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? color,
    required S s,
  }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
      crossAxisAlignment: CrossAxisAlignment.center, // 水平居中
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 10,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.3),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: color ?? theme.textTheme.bodyLarge?.color,
            fontFamily: label == s.get('duration') ? 'monospace' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalDataPanel(
      BuildContext context, WidgetRef ref, S s, bool isVisible) {
    final theme = Theme.of(context);
    final isRunning = ref.watch(vpnProvider.select((state) => state.isRunning));
    final traffic = ref.watch(trafficMonitorProvider);

    return Row(
      children: [
        Expanded(
          child: _buildStatBox(
            context,
            Icons.arrow_upward_rounded,
            s.get('upload'),
            FormatUtils.formatBytes(traffic.uploadSpeed).split(' ')[0],
            '${FormatUtils.formatBytes(traffic.uploadSpeed).split(' ')[1]}/s',
            Colors.orangeAccent,
            isRunning,
            traffic.totalUplink,
            traffic.uploadSpeed,
            isVisible,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatBox(
            context,
            Icons.arrow_downward_rounded,
            s.get('download'),
            FormatUtils.formatBytes(traffic.downloadSpeed).split(' ')[0],
            '${FormatUtils.formatBytes(traffic.downloadSpeed).split(' ')[1]}/s',
            theme.colorScheme.primary,
            isRunning,
            traffic.totalDownlink,
            traffic.downloadSpeed,
            isVisible,
          ),
        ),
      ],
    );
  }

  Widget _buildStatBox(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    String unit,
    Color iconColor,
    bool isRunning,
    int totalBytes,
    int speed,
    bool isVisible,
  ) {
    final theme = Theme.of(context);
    String formatTotal(int bytes) {
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withOpacity(0.02)
            : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : theme.dividerTheme.color ?? Colors.black.withOpacity(0.12),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Background Wave Pattern
            if (isVisible) // 🧊 P0级休眠优化：后台时不渲染波浪动画
              Positioned.fill(
                child: Opacity(
                  opacity: isRunning ? 0.25 : 0.05,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: speed.toDouble()),
                    duration: const Duration(milliseconds: 2000),
                    curve: Curves.easeOutCubic,
                    builder: (context, animSpeed, child) {
                      return _SpeedWave(
                        color: iconColor,
                        isRunning: isRunning,
                        isVisible: isVisible,
                        speed: animSpeed.toInt(),
                      );
                    },
                  ),
                ),
              ),
            // Foreground Content Layer (Numbers & Labels)
            Positioned.fill(
              child: RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: iconColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 20, color: iconColor),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: theme.textTheme.bodySmall?.color
                                  ?.withOpacity(0.6),
                            ),
                          ),
                          const Spacer(),
                          if (isRunning)
                            Text(
                              'TOTAL: ${formatTotal(totalBytes)}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: theme.textTheme.bodySmall?.color
                                    ?.withOpacity(0.4),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      // 🚀 UI 动效解耦：文本数值采用“瞬时跳变”，图形波浪采用“平滑缓动”
                      // 消除老虎机式滚动效应，提升数值可读性
                      Builder(
                        builder: (context) {
                          final formatted = FormatUtils.formatBytes(speed);
                          final parts = formatted.split(' ');
                          final valueText = parts[0];
                          final unitText = '${parts[1]}/s';

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                valueText,
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: theme.textTheme.bodyLarge?.color,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withOpacity(0.1),
                                      offset: const Offset(0, 1),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                unitText,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: iconColor.withOpacity(0.9),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentNodeCard(
    BuildContext context,
    WidgetRef ref,
    NodeModel? node,
  ) {
    final s = S.of(context, ref);
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isRunning = ref.watch(vpnProvider.select((state) => state.isRunning));

    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withOpacity(0.02)
            : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.05)
              : theme.dividerTheme.color ?? Colors.black.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            ref.read(pageIndexProvider.notifier).setIndex(1, animate: true);
          },
          hoverColor: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isRunning
                          ? [primaryColor, primaryColor.withOpacity(0.7)]
                          : [Colors.grey.shade700, Colors.grey.shade800],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.lan_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node?.name ?? s.get('no_node_selected'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _buildNodeTag(node?.protocol.toUpperCase() ?? 'NONE',
                              primaryColor.withOpacity(0.1), primaryColor),
                          if (node?.latency != null && node!.latency! > 0) ...[
                            const SizedBox(width: 8),
                            _buildNodeTag(
                                '${node.latency}ms',
                                Colors.greenAccent.withOpacity(0.1),
                                Colors.greenAccent),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodeTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final settings = ref.watch(vpnSettingsProvider);
    final s = S.of(context, ref);

    String getModeLabel(VpnMode mode) {
      switch (mode) {
        case VpnMode.global:
          return s.get('global_mode');
        case VpnMode.rule:
          return s.get('rule_mode');
        case VpnMode.direct:
          return s.get('direct_mode');
      }
    }

    IconData getModeIcon(VpnMode mode) {
      switch (mode) {
        case VpnMode.global:
          return Icons.public_rounded;
        case VpnMode.rule:
          return Icons.auto_awesome_rounded;
        case VpnMode.direct:
          return Icons.directions_run_rounded;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withOpacity(0.02)
            : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.05)
              : theme.dividerTheme.color ?? Colors.black.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showModeSwitchDialog(context, ref, settings);
          },
          hoverColor: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(getModeIcon(settings.mode),
                      color: primaryColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        getModeLabel(settings.mode),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.get('click_to_change_routing'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.unfold_more_rounded,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showModeSwitchDialog(
    BuildContext context,
    WidgetRef ref,
    VpnSettings settings,
  ) {
    final s = S.of(context, ref);
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    String getModeLabel(VpnMode mode) {
      switch (mode) {
        case VpnMode.global:
          return s.get('global_mode');
        case VpnMode.rule:
          return s.get('rule_mode');
        case VpnMode.direct:
          return s.get('direct_mode');
      }
    }

    IconData getModeIcon(VpnMode mode) {
      switch (mode) {
        case VpnMode.global:
          return Icons.public_rounded;
        case VpnMode.rule:
          return Icons.auto_awesome_rounded;
        case VpnMode.direct:
          return Icons.directions_run_rounded;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          s.get('routing_strategy'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: VpnMode.values.map((mode) {
            final isSelected = settings.mode == mode;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? primaryColor.withOpacity(0.2)
                      : Colors.transparent,
                ),
              ),
              child: ListTile(
                leading: Icon(
                  getModeIcon(mode),
                  color: isSelected
                      ? primaryColor
                      : theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                ),
                title: Text(
                  getModeLabel(mode),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected
                        ? primaryColor
                        : theme.textTheme.bodyLarge?.color,
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: primaryColor,
                        size: 20,
                      )
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref
                      .read(vpnSettingsProvider.notifier)
                      .update(settings.copyWith(mode: mode));
                  Navigator.pop(context);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ErrorDialog extends StatefulWidget {
  final String error;
  final VoidCallback onClose;
  const _ErrorDialog({required this.error, required this.onClose});
  @override
  State<_ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<_ErrorDialog> {
  bool _isExpanded = false;
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.error,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(s.get('connection_failed'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.get('connection_failed_desc'),
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error.withOpacity(0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isExpanded
                        ? s.get('hide_details')
                        : s.get('view_error_details'),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.maxFinite,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: SelectableText(
                widget.error,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.error));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(s.get('error_log_copied')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(s.get('copy_log')),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.grey,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onClose();
            Navigator.pop(context);
          },
          child: Text(
            s.get('confirm'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _BlinkingDot extends StatelessWidget {
  const _BlinkingDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _SpeedWave extends StatefulWidget {
  final Color color;
  final bool isRunning;
  final int speed; // 实时速率（字节/秒）
  final bool isVisible;

  const _SpeedWave({
    required this.color,
    required this.isRunning,
    required this.isVisible,
    this.speed = 0,
  });

  @override
  State<_SpeedWave> createState() => _SpeedWaveState();
}

class _SpeedWaveState extends State<_SpeedWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.isRunning && widget.isVisible) _controller.repeat();
  }

  @override
  void didUpdateWidget(_SpeedWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🛡️ 审计加固：增加 mounted 判定，确保生命周期安全
    if (!mounted) return;

    // 🧊 P0级休眠优化：双重判定（运行状态 + 窗口可见性）
    final shouldAnimate = widget.isRunning && widget.isVisible;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _WavePainter(
              color: widget.color,
              progress: _controller.value,
              isRunning: widget.isRunning,
              speed: widget.speed,
            ),
          );
        },
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double progress;
  final bool isRunning;
  final int speed;

  _WavePainter({
    required this.color,
    required this.progress,
    required this.isRunning,
    required this.speed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final yCenter = size.height * 0.7;

    // 动态计算振幅：根据网速对数增长
    double dynamicAmplitude = 6.0;
    if (isRunning) {
      final speedMB = speed / (1024 * 1024);
      final factor =
          (math.log(speedMB * 10 + 1) / math.log(100)).clamp(0.0, 1.0);
      dynamicAmplitude = 8.0 + (24.0 * factor); // 振幅范围 8 ~ 32
    }

    final amplitude = dynamicAmplitude;
    final wavelength = size.width / 1.2;

    // 优化一：增加采样步长 (x += 4)，大幅降低 CPU 计算正弦值的次数
    const double step = 4.0;

    // First wave with advanced gradient and fill
    final paint1 = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.0),
          color.withOpacity(0.6),
          color.withOpacity(0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final path1 = Path();
    path1.moveTo(0, yCenter);

    // 优化二：固定相位增长，移除 animationSpeedFactor 导致的瞬时视觉跳变
    // 之前乘以倍率会导致每秒网速更新时，sin 函数内部数值突变，产生“瞬移”感
    for (double x = 0; x <= size.width; x += step) {
      final y = yCenter +
          amplitude *
              math.sin(
                  (x / wavelength * 2 * math.pi) - (progress * 2 * math.pi));
      path1.lineTo(x, y);
    }
    canvas.drawPath(path1, paint1);

    // Bottom Fill (belowBarData effect)
    if (isRunning) {
      final fillPath = Path.from(path1);
      fillPath.lineTo(size.width, size.height);
      fillPath.lineTo(0, size.height);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withOpacity(0.25),
            color.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, yCenter - amplitude, size.width,
            size.height - (yCenter - amplitude)))
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);
    }

    // Second offset wave for depth
    final paint2 = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final path2 = Path();
    path2.moveTo(0, yCenter + 8);
    for (double x = 0; x <= size.width; x += step) {
      final y = yCenter +
          8 +
          (amplitude * 0.6) *
              math.sin((x / (wavelength * 1.4) * 2 * math.pi) -
                  (progress * 1.5 * math.pi) +
                  1.5);
      path2.lineTo(x, y);
    }
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isRunning != isRunning;
}

class _BreathingRing extends StatefulWidget {
  final double size;
  final Color color;
  final bool isVisible;
  const _BreathingRing({
    this.size = 64,
    required this.color,
    required this.isVisible,
  });
  @override
  State<_BreathingRing> createState() => _BreathingRingState();
}

class _BreathingRingState extends State<_BreathingRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.isVisible) _controller.repeat();

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.8), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 0.0), weight: 70),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(_BreathingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🛡️ 审计加固：增加 mounted 判定
    if (!mounted) return;

    // 🧊 P0级休眠优化：强杀 Ticker
    if (widget.isVisible && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isVisible && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final opacity = _opacityAnimation.value;
          final scale = _scaleAnimation.value;
          final scale2 = ((scale + 0.4) > 1.8) ? 0.8 : (scale + 0.4);

          return Stack(
            alignment: Alignment.center,
            children: [
              // 第一层波纹 - 移除 Opacity Widget 改用 Color.withOpacity
              Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withOpacity(opacity),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withOpacity(opacity * 0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
              // 第二层波纹
              Transform.scale(
                scale: scale2,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withOpacity(opacity * 0.5),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TitleBarButton extends ConsumerStatefulWidget {
  final IconData? icon; // 🚀 改为可选
  final Widget? customIcon; // 🚀 支持自定义 Widget
  final VoidCallback onTap;
  final Color hoverColor;
  final Color iconColor;
  final Color? hoverIconColor;
  final EdgeInsets? padding;

  const _TitleBarButton({
    this.icon,
    this.customIcon,
    required this.onTap,
    required this.hoverColor,
    required this.iconColor,
    this.hoverIconColor,
    this.padding,
  });

  @override
  ConsumerState<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends ConsumerState<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 46,
          height: 32,
          alignment: Alignment.center,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          child: Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: widget.customIcon ??
                Icon(
                  widget.icon,
                  size: 18,
                  color: _isHovered
                      ? (widget.hoverIconColor ?? widget.iconColor)
                      : widget.iconColor,
                ),
          ),
        ),
      ),
    );
  }
}
