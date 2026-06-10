import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightning/core/log_provider.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/pages/home_page.dart';
import 'package:lightning/pages/splash_screen.dart';
import 'package:lightning/theme/app_theme.dart';
import 'package:lightning/pages/settings_page.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:lightning/core/vpn_manager_provider.dart';
import 'package:lightning/core/windows_vpn_manager.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/traffic_monitor.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:lightning/core/app_visibility_provider.dart';

// Provider for showing splash screen
class SplashNotifier extends StateNotifier<bool> {
  static bool _hasShownSplash = false;
  SplashNotifier() : super(!_hasShownSplash) {
    if (!_hasShownSplash) {
      _hasShownSplash = true;
    }
  }

  void finish() {
    state = false;
  }
}

final showSplashProvider = StateNotifierProvider<SplashNotifier, bool>((ref) {
  return SplashNotifier();
});

// Provider for theme mode
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(bool? isDark)
      : super(
          isDark == null
              ? ThemeMode.system
              : (isDark ? ThemeMode.dark : ThemeMode.light),
        );

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', state == ThemeMode.dark);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return throw UnimplementedError();
});

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isSilent = args.contains('--silent') || args.contains('-s');

  // Desktop initialization
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await hotKeyManager.unregisterAll(); // [P2] 清理全局快捷键
    // 🛡️ 核心防线一：在初始化后立即开启阻止默认关闭，由 WindowListener 接管
    await windowManager.setPreventClose(true);

    // [P0] 单例运行锁与唤醒机制
    await WindowsSingleInstance.ensureSingleInstance(
        args, "lightning_vpn_instance_lock", onSecondWindow: (args) async {
      // 当试图启动第二个实例时，唤醒并置顶第一个实例
      await windowManager.show();
      await windowManager.focus();
    });

    // Setup launch at startup
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    LaunchAtStartup.instance.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      args: ['--silent'],
    );

    WindowOptions windowOptions = const WindowOptions(
      size: Size(900, 650),
      minimumSize: Size(900, 650),
      center: true,
      title: 'Lightning',
      titleBarStyle: TitleBarStyle.hidden, // 🚀 无边框优化：隐藏原生标题栏
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (!isSilent) {
        await windowManager.show();
        await windowManager.focus();
      } else {
        debugPrint('Windows: Silent startup detected, skipping show window.');
        await windowManager.hide(); // 确保彻底隐藏
      }
    });
  }

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode');
  final langCode = prefs.getString('language_code');
  final countryCode = prefs.getString('country_code');

  final container = ProviderContainer(
    overrides: [
      themeModeProvider.overrideWith((ref) => ThemeModeNotifier(isDark)),
      localizationProvider.overrideWith(
        (ref) => LocaleNotifier(langCode, countryCode),
      ),
      if (isSilent) appVisibilityProvider.overrideWith((ref) => false),
    ],
  );

  // 初始化日志容器引用，以便在 LogNotifier 中访问 vpnProvider
  container.read(logProvider.notifier).setContainer(container);

  // Capture Flutter framework errors
  FlutterError.onError = (details) {
    if (Platform.isWindows) {
      // 🧹 终极防线：崩溃时强制执行网络环境自愈
      WindowsVpnManager.forceCleanupSync();
    }
    FlutterError.presentError(details);
    container
        .read(logProvider.notifier)
        .addLog('error', 'Flutter Error: ${details.exceptionAsString()}');
  };

  // Capture platform-level errors (e.g. from async tasks)
  PlatformDispatcher.instance.onError = (error, stack) {
    if (Platform.isWindows) {
      // 🛡️ 环境安全兜底：异步崩溃时同步清理代理
      WindowsVpnManager.forceCleanupSync();
    }
    container
        .read(logProvider.notifier)
        .addLog('error', 'Platform Error: $error');
    return true;
  };

  // 🔔 进程信号监听：处理正常退出或意外终止信号 (Ctrl+C 等)
  if (Platform.isWindows) {
    ProcessSignal.sigint.watch().listen((signal) {
      WindowsVpnManager.forceCleanupSync();
      exit(0);
    });
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LightningApp(),
    ),
  );
}

class LightningApp extends ConsumerStatefulWidget {
  const LightningApp({super.key});

  @override
  ConsumerState<LightningApp> createState() => _LightningAppState();
}

class _LightningAppState extends ConsumerState<LightningApp>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  Timer? _visibilityCheckTimer;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      WidgetsBinding.instance.addObserver(this);
      _initTray();
      _setupTrayListeners();
      _handleAutoReconnect(); // [P0] 启动重连逻辑
      _setupHotkeyListener(); // [P2] 初始化全局快捷键

      // 🛡️ 【全量功耗守护】监听可见性状态变化，强制同步物理窗口状态
      // 确保无论通过何种途径（Provider 变更或原生事件）修改了可见性，
      // 物理窗口、引擎状态、流量雷达都能完美同步。
      Future.microtask(() {
        ref.listenManual(appVisibilityProvider, (previous, next) {
          if (next == false) {
            // 状态变为不可见，执行物理挂起
            _ensurePhysicalHide();
          } else if (next == true) {
            // 状态变为可见，执行物理唤醒
            _ensurePhysicalShow();
          }
        });
      });

      // 🛡️ 【P0级功耗兜底】定时自检可见性
      // 每 10 秒强制同步一次窗口状态，防止监听器遗漏导致的 GPU 持续占用
      _visibilityCheckTimer =
          Timer.periodic(const Duration(seconds: 10), (timer) async {
        if (!mounted) return;
        final isVisibleReal = await windowManager.isVisible();
        final isMinimized = await windowManager.isMinimized();
        final isVisibleState = ref.read(appVisibilityProvider);

        // 如果物理状态已隐藏/最小化，但逻辑状态仍为可见，则强制修正
        if ((!isVisibleReal || isMinimized) && isVisibleState) {
          debugPrint('Windows: Visibility mismatch detected, forcing sleep...');
          onWindowHide();
        }
      });
    }
  }

  /// 物理层强制隐藏（深睡眠）
  void _ensurePhysicalHide() async {
    final isVisibleReal = await windowManager.isVisible();
    final isMinimized = await windowManager.isMinimized();
    
    // 如果物理上已经是隐藏/最小化状态，且引擎已暂停，则不再重复操作
    if (!isVisibleReal || isMinimized) {
      // 仍然确保引擎是暂停的
      WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      return;
    }

    onWindowHide();
  }

  /// 物理层强制唤醒
  void _ensurePhysicalShow() async {
    final isVisibleReal = await windowManager.isVisible();
    if (isVisibleReal) return;
    
    onWindowShow();
  }

  void _setupHotkeyListener() {
    // 初次初始化
    _updateHotKey(ref.read(vpnSettingsProvider).showHideHotkey);

    // 监听设置变更
    ref.listenManual(vpnSettingsProvider, (previous, next) {
      if (previous?.showHideHotkey != next.showHideHotkey) {
        _updateHotKey(next.showHideHotkey);
      }
    });
  }

  void _updateHotKey(String hotkeyStr) async {
    try {
      await hotKeyManager.unregisterAll();

      // 解析字符串，例如 "Alt+Q" 或 "Ctrl+Shift+S"
      final parts = hotkeyStr.split('+');
      LogicalKeyboardKey? targetKey;
      List<HotKeyModifier> modifiers = [];

      for (var part in parts) {
        final p = part.trim().toLowerCase();
        if (p == 'alt') {
          modifiers.add(HotKeyModifier.alt);
        } else if (p == 'ctrl' || p == 'control') {
          modifiers.add(HotKeyModifier.control);
        } else if (p == 'shift') {
          modifiers.add(HotKeyModifier.shift);
        } else if (p == 'meta' || p == 'win' || p == 'cmd') {
          modifiers.add(HotKeyModifier.meta);
        } else {
          // 假设最后一部分是字母/按键
          final keyName = 'key${p.toUpperCase()}';
          // 简单映射常用字母键
          targetKey = _mapStringToKey(p);
        }
      }

      if (targetKey != null) {
        HotKey hotKey = HotKey(
          key: targetKey,
          modifiers: modifiers,
          scope: HotKeyScope.system,
        );
        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (_) async {
            bool isVisible = await windowManager.isVisible();
            if (isVisible) {
              await windowManager.hide();
            } else {
              await windowManager.show();
              await windowManager.focus();
            }
          },
        );
        debugPrint('Hotkey registered: $hotkeyStr');
      }
    } catch (e) {
      debugPrint('Failed to register hotkey: $e');
    }
  }

  LogicalKeyboardKey? _mapStringToKey(String key) {
    final k = key.toLowerCase();
    if (k.length == 1) {
      final charCode = k.codeUnitAt(0);
      if (charCode >= 97 && charCode <= 122) {
        // a-z
        return LogicalKeyboardKey(k.codeUnitAt(0));
      }
    }
    // 常用功能键映射
    switch (k) {
      case 'f1':
        return LogicalKeyboardKey.f1;
      case 'f2':
        return LogicalKeyboardKey.f2;
      case 'f3':
        return LogicalKeyboardKey.f3;
      case 'f4':
        return LogicalKeyboardKey.f4;
      case 'f5':
        return LogicalKeyboardKey.f5;
      case 'f6':
        return LogicalKeyboardKey.f6;
      case 'f7':
        return LogicalKeyboardKey.f7;
      case 'f8':
        return LogicalKeyboardKey.f8;
      case 'f9':
        return LogicalKeyboardKey.f9;
      case 'f10':
        return LogicalKeyboardKey.f10;
      case 'f11':
        return LogicalKeyboardKey.f11;
      case 'f12':
        return LogicalKeyboardKey.f12;
      case 'space':
        return LogicalKeyboardKey.space;
      case 'enter':
        return LogicalKeyboardKey.enter;
      case 'escape':
        return LogicalKeyboardKey.escape;
    }
    return null;
  }

  // 移除旧的静态注册函数
  void _initHotKeys() async {}

  Future<void> _handleAutoReconnect() async {
    // 延迟一秒，确保所有 Provider 已就绪且资源已加载
    await Future.delayed(const Duration(milliseconds: 1500));

    final vpnSettings = ref.read(vpnSettingsProvider);
    final prefs = await SharedPreferences.getInstance();
    final wasRunning = prefs.getBool('vpn_was_running') ?? false;

    // [P0] 仅当设置开启了自动重连且上次处于运行状态时触发
    if (vpnSettings.autoReconnect && wasRunning) {
      debugPrint('Windows: Auto-reconnect triggered, restoring VPN state.');
      final vpnNotifier = ref.read(vpnProvider.notifier);
      final selectedNode = ref.read(selectedNodeProvider);

      if (selectedNode != null) {
        vpnNotifier.toggleVpn(selectedNode);
      } else {
        debugPrint('Windows: Auto-reconnect failed, no selected node found.');
      }
    }
  }

  void _setupTrayListeners() {
    // 监听设置变化以同步更新托盘状态（如路由模式勾选、系统代理状态）
    ref.listenManual(vpnSettingsProvider, (previous, next) {
      _refreshTrayMenu();
    });

    // 监听 VPN 运行状态以更新托盘图标和 Tooltip
    ref.listenManual(vpnProvider, (previous, next) {
      if (previous?.isRunning != next.isRunning) {
        _refreshTrayMenu();
      }
    });
  }

  Future<void> _initTray() async {
    // 延迟确保原生插件加载完成
    await Future.delayed(const Duration(milliseconds: 1000));
    _refreshTrayMenu();
  }

  Future<void> _refreshTrayMenu() async {
    if (!Platform.isWindows) return;

    try {
      final locale = ref.read(localizationProvider);
      final s = S(locale);
      final vpnSettings = ref.read(vpnSettingsProvider);
      final isRunning = ref.read(vpnProvider).isRunning;

      String iconPath = 'assets/windows/app_icon.ico';
      await trayManager.setIcon(iconPath);

      final Menu menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: s.get('show_main_window'),
          ),
          MenuItem.separator(),
          MenuItem.checkbox(
            key: 'system_proxy',
            label: s.get('take_over_system_proxy'),
            checked: vpnSettings.systemProxyEnabled,
          ),
          MenuItem.submenu(
            key: 'routing_mode',
            label: s.get('routing_mode'),
            submenu: Menu(
              items: [
                MenuItem.checkbox(
                  key: 'mode_rule',
                  label: s.get('rule_mode'),
                  checked: vpnSettings.mode == VpnMode.rule,
                ),
                MenuItem.checkbox(
                  key: 'mode_global',
                  label: s.get('global_mode'),
                  checked: vpnSettings.mode == VpnMode.global,
                ),
                MenuItem.checkbox(
                  key: 'mode_direct',
                  label: s.get('direct_mode'),
                  checked: vpnSettings.mode == VpnMode.direct,
                ),
              ],
            ),
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'toggle_vpn',
            label: isRunning ? s.get('disconnect_vpn') : s.get('connect_vpn'),
          ),
          MenuItem(
            key: 'exit_app',
            label: s.get('exit_app'),
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
      String tooltip = s.get('tray_tooltip_disconnected');
      if (isRunning) {
        tooltip = s.get('tray_tooltip_connected');
      }
      await trayManager.setToolTip(tooltip);
    } catch (e) {
      debugPrint('Tray update error: $e');
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      _visibilityCheckTimer?.cancel();
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isWindows) {
      debugPrint('Windows Lifecycle: $state');

      // 🚀 核心加固：明确排除 hidden/paused 状态下的清理逻辑
      // 在 Windows 桌面端，当窗口隐藏到托盘时，状态会变为 hidden 或 paused。
      // 我们必须确保在这种状态下绝对不要调用任何 stopProxy 或清理逻辑。
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused) {
        debugPrint(
            'Windows Lifecycle: App is hidden/paused (tray mode), keeping VPN alive.');
        return;
      }

      if (state == AppLifecycleState.resumed) {
        // 触发 VPN 重启逻辑以应对休眠唤醒后的 Socket 假死
        debugPrint(
            'Windows Lifecycle: App resumed, checking for network recovery...');
        ref.read(vpnProvider.notifier).refreshOnWake();
      }
    }
  }

  @override
  void onWindowHide() async {
    // 🛡️ 防御式检查：如果已经是不可见状态，则跳过，避免重复触发导致的 DWM 抖动
    if (ref.read(appVisibilityProvider) == false) return;

    debugPrint('Windows: 💤 Window hidden, entering ultra deep sleep...');

    // 1. 物理隐藏并移出任务栏，切断 DWM 渲染路径
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);

    // 🚀 【加固优化】强制失去焦点并透明化，双重确保 DWM 不再对其进行合成渲染
    await windowManager.blur();
    await windowManager.setOpacity(0);

    // 2. 状态通知：停止流量雷达和 Xray IO
    ref.read(appVisibilityProvider.notifier).state = false;
    ref.read(trafficMonitorProvider.notifier).pause();
    ref.read(vpnProvider.notifier).goToBackground();

    // 3. 强制通知 Flutter 引擎进入暂停状态，物理停止 Scheduler 和 Rasterizer
    // 💡 额外延迟 50ms 确保最后一帧渲染完成后再挂起
    Future.delayed(const Duration(milliseconds: 50), () {
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // 🛡️ 释放图像资源
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  @override
  void onWindowShow() async {
    // 🛡️ 防御式检查：如果已经是可见状态，则跳过
    if (ref.read(appVisibilityProvider) == true) return;

    debugPrint('Windows: ☀️ Window restored, waking up...');

    // 1. 物理恢复窗口
    await windowManager.setOpacity(1); // 先恢复透明度
    await windowManager.show();
    await windowManager.setSkipTaskbar(false);
    await windowManager.focus();

    // 2. 状态通知：唤醒流量雷达和 Xray IO
    ref.read(appVisibilityProvider.notifier).state = true;
    ref.read(trafficMonitorProvider.notifier).resume();
    ref.read(vpnProvider.notifier).refreshOnWake();

    // 3. 恢复 Flutter 引擎调度
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  @override
  void onWindowMinimize() {
    debugPrint('Windows: Window minimized, entering ultra deep sleep...');
    onWindowHide();
  }

  @override
  void onWindowRestore() {
    debugPrint('Windows: Window restored, waking up...');
    onWindowShow();
  }

  @override
  void onWindowClose() async {
    if (Platform.isWindows) {
      bool isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose) {
        final vpnSettings = ref.read(vpnSettingsProvider);
        if (vpnSettings.hideToTray) {
          debugPrint('Windows: Intercepting close, hiding to tray instead.');
          onWindowHide(); // 🛡️ 使用统一的隐藏逻辑
        } else {
          debugPrint(
              'Windows: Intercepting close, user disabled "hideToTray", quitting gracefully.');
          // 如果用户关闭了“隐藏到托盘”，则点击关闭按钮执行优雅退出逻辑
          if (vpnSettings.cleanProxyOnExit) {
            debugPrint('Windows: Clean proxy on exit triggered.');
            final vpnNotifier = ref.read(vpnProvider.notifier);
            await vpnNotifier.stopProxy();
          }
          await windowManager.destroy();
          exit(0);
        }
      }
    }
  }

  @override
  void onTrayIconMouseDown() {
    // 某些平台依赖 MouseDown 唤起
  }

  @override
  void onTrayIconRightMouseDown() {
    _refreshTrayMenu();
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconMouseUp() {
    // 左键单击也可以唤醒
    _toggleWindowVisibility();
  }

  @override
  void onTrayIconRightMouseUp() {}

  @override
  void onTrayIconDoubleMouseDown() {
    _toggleWindowVisibility();
  }

  Future<void> _toggleWindowVisibility() async {
    bool isVisible = await windowManager.isVisible();
    if (isVisible) {
      onWindowHide(); // 🛡️ 使用统一的隐藏逻辑
    } else {
      onWindowShow(); // 🛡️ 使用统一的显示逻辑
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final vpnSettings = ref.read(vpnSettingsProvider);
    if (menuItem.key == 'show_window') {
      _toggleWindowVisibility();
    } else if (menuItem.key == 'system_proxy') {
      // 🛡️ 审计优化：托盘静默操作，绝不触发 UI 重绘
      final vpnSettingsNotifier = ref.read(vpnSettingsProvider.notifier);
      await vpnSettingsNotifier.update(
        vpnSettings.copyWith(systemProxyEnabled: !(menuItem.checked ?? true)),
      );
      _refreshTrayMenu();
    } else if (menuItem.key?.startsWith('mode_') ?? false) {
      // 🛡️ 审计优化：托盘静默操作
      final vpnSettingsNotifier = ref.read(vpnSettingsProvider.notifier);
      VpnMode newMode = VpnMode.rule;
      if (menuItem.key == 'mode_global') newMode = VpnMode.global;
      if (menuItem.key == 'mode_direct') newMode = VpnMode.direct;

      await vpnSettingsNotifier.update(vpnSettings.copyWith(mode: newMode));
      _refreshTrayMenu();
    } else if (menuItem.key == 'toggle_vpn') {
      // 🛡️ 审计优化：托盘静默操作
      final vpnNotifier = ref.read(vpnProvider.notifier);
      final isRunning = ref.read(vpnProvider).isRunning;
      if (isRunning) {
        await vpnNotifier.stopProxy();
      } else {
        final selectedNode = ref.read(selectedNodeProvider);
        if (selectedNode != null) {
          await vpnNotifier.toggleVpn(selectedNode);
        } else {
          // 只有在没节点时才唤醒窗口引导用户
          onWindowShow();
        }
      }
      _refreshTrayMenu();
    } else if (menuItem.key == 'exit_app') {
      if (vpnSettings.cleanProxyOnExit) {
        debugPrint('Windows Tray: Clean proxy on exit triggered.');
        final vpnNotifier = ref.read(vpnProvider.notifier);
        await vpnNotifier.stopProxy();
      }
      await windowManager.destroy();
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localizationProvider);
    final showSplash = ref.watch(showSplashProvider);
    final isVisible = ref.watch(appVisibilityProvider);

    // 🚀 【核弹级 GPU 优化】极致架构
    // 当窗口隐藏到托盘时，我们不仅要停止 Ticker，还要物理销毁整个 MaterialApp。
    // 这将强制 Flutter 引擎释放所有渲染 Layer、纹理和 GPU 上下文。
    // 由于核心状态（VPN连接、设置、页面索引）都在 ProviderContainer 中，
    // 销毁 UI 树不会导致业务中断。
    if (!isVisible) {
      return const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      );
    }

    return TickerMode(
      enabled: isVisible,
      child: MaterialApp(
        title: 'Lightning',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        locale: locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: showSplash
            ? SplashScreen(
                onFinish: () => ref.read(showSplashProvider.notifier).finish(),
              )
            : const HomePage(),
      ),
    );
  }
}

class _DesktopScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
