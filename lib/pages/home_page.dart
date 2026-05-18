import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightning/core/config_generator.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/pages/nodes_page.dart';
import 'package:lightning/pages/subscriptions_page.dart';
import 'package:lightning/pages/logs_page.dart';
import 'package:lightning/pages/settings_page.dart';

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
  late AnimationController _logoAnimationController;

  @override
  void initState() {
    super.initState();
    _logoAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _checkPermissions();
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    try {
      await ref.read(vpnProvider.notifier).requestNotificationPermission();
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageIndexState = ref.watch(pageIndexProvider);
    final pageIndex = pageIndexState.index;
    final vpnState = ref.watch(vpnProvider);
    final isSidebarExpanded = ref.watch(sidebarExpandedProvider);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 720;

        return Scaffold(
          drawer: isMobile ? _buildDrawer(context, ref, pageIndex) : null,
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Row(
            children: [
              if (!isMobile)
                _buildSidebar(context, ref, pageIndex, isSidebarExpanded),
              Expanded(
                child: _buildMainContent(
                  context,
                  ref,
                  pageIndexState,
                  vpnState,
                  constraints.maxWidth,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, WidgetRef ref, int currentIndex) {
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
                _buildAnimatedLogo(72),
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
                  'The Next Gen Proxy Client',
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
                      'Version 1.0.0 • Build 1',
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

  Widget _buildAnimatedLogo(double size) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    return RepaintBoundary(
      child: SizedBox(
        width: size * 1.5,
        height: size * 1.5,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background Glow - Increased intensity and size
            Container(
              width: size * 1.5,
              height: size * 1.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 25,
                    spreadRadius: 2,
                  ),
                ],
                gradient: RadialGradient(
                  colors: [
                    color.withOpacity(0.4),
                    color.withOpacity(0.1),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
            // Logo
            SizedBox(
              width: size,
              height: size,
              child: Image.asset('icon.png', fit: BoxFit.contain),
            ),
          ],
        ),
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
        selectedTileColor: accentColor.withOpacity(0.1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    WidgetRef ref,
    int currentIndex,
    bool isExpanded,
  ) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final s = S.of(context, ref);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: isExpanded ? 240 : 88,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.white.withOpacity(0.04), width: 1),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 48),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(sidebarExpandedProvider.notifier).toggle();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: isExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      _buildAnimatedLogo(44),
                      if (isExpanded) ...[
                        const SizedBox(width: 16),
                        const Flexible(
                          child: Text(
                            'Lightning',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildSidebarItem(
                    context,
                    ref,
                    0,
                    Icons.grid_view_rounded,
                    s.get('control_panel'),
                    currentIndex,
                    isExpanded,
                    accentColor,
                  ),
                  _buildSidebarItem(
                    context,
                    ref,
                    1,
                    Icons.dns_rounded,
                    s.get('nodes_manage'),
                    currentIndex,
                    isExpanded,
                    accentColor,
                  ),
                  _buildSidebarItem(
                    context,
                    ref,
                    2,
                    Icons.rss_feed_rounded,
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
                    Icons.settings_input_component_rounded,
                    s.get('advanced_config'),
                    currentIndex,
                    isExpanded,
                    accentColor,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(sidebarExpandedProvider.notifier).toggle();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 48,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        isExpanded
                            ? Icons.keyboard_double_arrow_left_rounded
                            : Icons.keyboard_double_arrow_right_rounded,
                        color: Colors.grey.shade500,
                        size: 20,
                      ),
                      if (isExpanded)
                        Positioned(
                          right: 12,
                          child: Text(
                            'v1.0.0',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
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
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: isExpanded ? 16 : 0),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withOpacity(0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? accentColor.withOpacity(0.2)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isSelected
                      ? accentColor
                      : theme.textTheme.bodySmall?.color,
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected
                            ? accentColor
                            : theme.textTheme.bodyMedium?.color,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
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
  ) {
    final pageIndex = pageIndexState.index;
    Widget child;
    switch (pageIndex) {
      case 0:
        child = _HomeContent(
          vpnState: vpnState,
          maxWidth: maxWidth,
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

class _HomeContent extends ConsumerWidget {
  final VpnState vpnState;
  final double maxWidth;
  const _HomeContent({
    super.key,
    required this.vpnState,
    required this.maxWidth,
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
        : (nodes.where((n) => n.id == selectedNodeRaw.id).firstOrNull ??
              selectedNodeRaw);
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
                _buildMainStatusCard(context, ref, selectedNode),
                const SizedBox(height: 20),
                if (isLargeScreen)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(theme, '实时数据流'),
                            _buildHorizontalDataPanel(context, ref),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(theme, '节点隧道'),
                            _buildCurrentNodeCard(context, ref, selectedNode),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  _buildSectionHeader(theme, '实时数据流'),
                  _buildHorizontalDataPanel(context, ref),
                  const SizedBox(height: 20),
                  _buildSectionHeader(theme, '节点隧道'),
                  _buildCurrentNodeCard(context, ref, selectedNode),
                ],
                const SizedBox(height: 20),
                _buildSectionHeader(theme, s.get('rule_mode')),
                _buildModeSelector(context, ref),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary.withOpacity(0.8),
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  void _showErrorDialog(BuildContext context, WidgetRef ref, String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ErrorDialog(
        error: error,
        onClose: () => ref.read(vpnProvider.notifier).clearError(),
      ),
    );
  }

  Widget _buildMainStatusCard(
    BuildContext context,
    WidgetRef ref,
    NodeModel? selectedNode,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    // Granular watches to avoid full rebuild
    final isRunning = ref.watch(vpnProvider.select((s) => s.isRunning));
    final isStarting = ref.watch(vpnProvider.select((s) => s.isStarting));

    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isRunning
                ? primaryColor.withOpacity(0.12)
                : Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isRunning
                    ? [
                        primaryColor.withOpacity(0.12),
                        primaryColor.withOpacity(0.04),
                      ]
                    : [
                        theme.cardTheme.color!.withOpacity(0.8),
                        theme.cardTheme.color!.withOpacity(0.4),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isRunning
                    ? primaryColor.withOpacity(0.25)
                    : Colors.white.withOpacity(0.06),
                width: 1.0,
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
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            if (isRunning)
                              Center(
                                child: _BreathingRing(
                                  size: 44,
                                  color: primaryColor,
                                ),
                              ),
                            Container(
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
                                          Colors.grey.shade800,
                                          Colors.grey.shade900,
                                        ],
                                ),
                                boxShadow: isRunning
                                    ? [
                                        BoxShadow(
                                          color: primaryColor.withOpacity(0.4),
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
                          ],
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
                                  vpnProvider.select((s) => s.connectionStage),
                                );
                                return Text(
                                  stage == 1
                                      ? '正在建立网络连接...'
                                      : stage == 2
                                      ? '正在加密VPN隧道'
                                      : stage == 3
                                      ? 'VPN服务运行中'
                                      : '未启用服务',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: theme.textTheme.headlineSmall?.color,
                                    letterSpacing: -0.5,
                                  ),
                                  maxLines: 1,
                                );
                              },
                            ),
                            const SizedBox(height: 1),
                            Text(
                              isRunning
                                  ? '已成功启用加密隧道连接节点'
                                  : (isStarting ? '正在初始化加密协议' : '点击右侧开关开启加速'),
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
                                  const SnackBar(
                                    content: Text('请先选择一个节点'),
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
                Divider(color: Colors.white.withOpacity(0.04), height: 1),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, child) {
                            final duration = ref.watch(
                              vpnProvider.select((s) => s.duration),
                            );
                            return _buildInfoItem(
                              context,
                              '时长',
                              _formatDuration(duration),
                              Icons.timer_outlined,
                            );
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildInfoItem(
                          context,
                          '协议',
                          isRunning
                              ? (selectedNode?.protocol.toUpperCase() ??
                                    'UNKNOWN')
                              : '未知',
                          Icons.security_rounded,
                        ),
                      ),
                      Expanded(
                        child: _buildInfoItem(
                          context,
                          '状态',
                          isRunning ? '稳定' : '待命',
                          Icons.check_circle_outline_rounded,
                          color: isRunning ? const Color(0xFF00C853) : null,
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
            fontFamily: label == '时长' ? 'monospace' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalDataPanel(
    BuildContext context,
    WidgetRef ref,
  ) {
    final s = S.of(context, ref);
    final theme = Theme.of(context);
    final isRunning = ref.watch(vpnProvider.select((s) => s.isRunning));

    return Row(
      children: [
        Expanded(
          child: Consumer(
            builder: (context, ref, child) {
              final speed = ref.watch(vpnProvider.select((s) => s.uploadSpeed));
              final total = ref.watch(vpnProvider.select((s) => s.totalUpload));
              return _buildStatBox(
                context,
                Icons.arrow_upward_rounded,
                s.get('upload'),
                _formatSpeed(speed),
                _getUnit(speed),
                Colors.orangeAccent,
                isRunning,
                total,
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Consumer(
            builder: (context, ref, child) {
              final speed = ref.watch(
                vpnProvider.select((s) => s.downloadSpeed),
              );
              final total = ref.watch(
                vpnProvider.select((s) => s.totalDownload),
              );
              return _buildStatBox(
                context,
                Icons.arrow_downward_rounded,
                s.get('download'),
                _formatSpeed(speed),
                _getUnit(speed),
                theme.colorScheme.primary,
                isRunning,
                total,
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatSpeed(int bytes) {
    if (bytes < 1024) return bytes.toString();
    if (bytes < 1024 * 1024) return (bytes / 1024).toStringAsFixed(1);
    return (bytes / (1024 * 1024)).toStringAsFixed(1);
  }

  String _getUnit(int bytes) {
    if (bytes < 1024) return 'B/s';
    if (bytes < 1024 * 1024) return 'KB/s';
    return 'MB/s';
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
  ) {
    final theme = Theme.of(context);
    String formatTotal(int bytes) {
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024)
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color?.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
        child: InkWell(
          onTap: () {},
          child: Stack(
            children: [
              Positioned(
                right: -10,
                bottom: -10,
                child: Icon(icon, size: 64, color: iconColor.withOpacity(0.03)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: iconColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, size: 18, color: iconColor),
                        ),
                        if (isRunning)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900,
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withOpacity(0.2),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  formatTotal(totalBytes),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.5,
                        ),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: theme.textTheme.bodyLarge?.color,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          unit,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: iconColor.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentNodeCard(
    BuildContext context,
    WidgetRef ref,
    NodeModel? node,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isRunning = ref.watch(vpnProvider.select((s) => s.isRunning));

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color?.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            ref.read(pageIndexProvider.notifier).setIndex(1, animate: true);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isRunning
                          ? [primaryColor, primaryColor.withOpacity(0.7)]
                          : [Colors.grey.shade800, Colors.grey.shade900],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      if (isRunning)
                        BoxShadow(
                          color: primaryColor.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: Icon(Icons.dns_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        node?.name ?? '未选择节点',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              node?.protocol.toUpperCase() ?? 'NONE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: primaryColor,
                              ),
                            ),
                          ),
                          if (node?.latency != null && node!.latency! != 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (node.latency! > 0
                                            ? Colors.greenAccent
                                            : Colors.redAccent)
                                        .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                node.latency! == -1
                                    ? '测试中...'
                                    : (node.latency! == -2
                                          ? '超时'
                                          : '${node.latency}ms'),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: node.latency! > 0
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.2),
                  size: 16,
                ),
              ],
            ),
          ),
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
        color: theme.cardTheme.color?.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showModeSwitchDialog(context, ref, settings);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    getModeIcon(settings.mode),
                    color: primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        getModeLabel(settings.mode),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '当前路由过滤模式',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.2),
                  size: 16,
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
          const Text('连接失败', style: TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '节点连接失败，可能是配置不兼容或节点已失效，请尝试更换节点。',
            style: TextStyle(
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
                    _isExpanded ? '隐藏详情' : '查看错误详情',
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
                  const SnackBar(
                    content: Text('错误日志已复制到剪贴板'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制日志'),
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
          child: const Text(
            '确定',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.2,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
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
      ),
    );
  }
}

class _BreathingRing extends StatefulWidget {
  final double size;
  final Color color;
  const _BreathingRing({this.size = 64, required this.color});
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
    )..repeat();
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
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.color, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: ((_scaleAnimation.value + 0.4) > 1.8)
                    ? 0.8
                    : (_scaleAnimation.value + 0.4),
                child: Opacity(
                  opacity: _opacityAnimation.value * 0.5,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.color.withOpacity(0.5),
                        width: 1.5,
                      ),
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
