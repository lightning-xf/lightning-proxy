import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lightning/core/vpn_manager_provider.dart';
import 'package:lightning/core/vpn_manager_interface.dart';
import 'package:lightning/core/routing_provider.dart';
import 'package:lightning/core/rule_model.dart';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/subscription_provider.dart';
import 'package:lightning/core/config_generator.dart';
import 'package:lightning/core/log_provider.dart';
import 'package:lightning/core/traffic_monitor.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/windows_vpn_manager.dart';
import 'package:lightning/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lightning/core/app_visibility_provider.dart';

enum VpnMode { rule, global, direct }

class VpnState {
  final bool isRunning;
  final bool isStarting;
  final int
      connectionStage; // 0: disconnected, 1: connecting net, 2: encrypting, 3: connected
  final String? currentNodeName;
  final int uploadSpeed;
  final int downloadSpeed;
  final int totalUpload;
  final int totalDownload;
  final DateTime? startTime;
  final Duration duration;
  final String? lastError;

  VpnState({
    this.isRunning = false,
    this.isStarting = false,
    this.connectionStage = 0,
    this.currentNodeName,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.totalUpload = 0,
    this.totalDownload = 0,
    this.startTime,
    this.duration = Duration.zero,
    this.lastError,
  });

  VpnState copyWith({
    bool? isRunning,
    bool? isStarting,
    int? connectionStage,
    String? currentNodeName,
    int? uploadSpeed,
    int? downloadSpeed,
    int? totalUpload,
    int? totalDownload,
    DateTime? startTime,
    Duration? duration,
    String? lastError,
    bool clearError = false,
  }) {
    return VpnState(
      isRunning: isRunning ?? this.isRunning,
      isStarting: isStarting ?? this.isStarting,
      connectionStage: connectionStage ?? this.connectionStage,
      currentNodeName: currentNodeName ?? this.currentNodeName,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      totalUpload: totalUpload ?? this.totalUpload,
      totalDownload: totalDownload ?? this.totalDownload,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class VpnNotifier extends StateNotifier<VpnState> {
  final Ref ref;
  late final IVpnManager _vpnManager;
  StreamSubscription? _connectivitySubscription;
  bool _isRestarting = false;
  DateTime? _lastRestartTime;

  VpnNotifier(this.ref) : super(VpnState()) {
    _vpnManager = ref.read(vpnManagerProvider);
    _initStatusListener();
    _initWindowsLogHandler();
    _syncStatus();
    _listenToSettings();
    _initAutoUpdate();
    _initConnectivityListener();
  }

  void _initWindowsLogHandler() {
    if (_vpnManager is! dynamic) return;
    try {
      (_vpnManager as dynamic)
          .setWindowsLogHandler((String level, String message) {
        ref.read(logProvider.notifier).addLog(level, message);
      });
    } catch (e) {
      debugPrint('Failed to init Windows log handler: $e');
    }
  }

  void _initConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      // 🧊 极致节能：后台模式下挂起网络状态监控
      final isVisible = ref.read(appVisibilityProvider);
      if (!isVisible) return;

      final s = S(ref.read(localizationProvider));
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        ref
            .read(logProvider.notifier)
            .addLog('warning', s.get('net_disconnected'));
        return;
      }

      final settings = ref.read(vpnSettingsProvider);
      // 如果开启了自动重连，且 VPN 处于运行状态（非手动停止），则触发重启
      if (settings.autoReconnect && state.isRunning && !state.isStarting) {
        ref
            .read(logProvider.notifier)
            .addLog('info', s.get('auto_reconnect_triggered'));
        _handleRestart();
      }
    });
  }

  Timer? _durationTimer;
  void _startDurationTimer() {
    _durationTimer?.cancel();

    // 🧊 极致节能：如果窗口不可见，绝对不要开启计时器，从源头切断 CPU 唤醒
    final isVisible = ref.read(appVisibilityProvider);
    if (!isVisible) {
      debugPrint('VPN: Window hidden, skipping duration timer start.');
      return;
    }

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.isRunning && state.startTime != null) {
        state = state.copyWith(
          duration: DateTime.now().difference(state.startTime!),
        );
      } else {
        timer.cancel();
      }
    });
  }

  void _stopDurationTimer() {
    debugPrint('VPN: Stopping duration timer (Deep Sleep).');
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  Timer? _autoUpdateTimer;
  void _initAutoUpdate() {
    _autoUpdateTimer?.cancel();
    // Schedule a check every 15 minutes
    _autoUpdateTimer = Timer.periodic(
      const Duration(minutes: 15),
      (timer) => _runAutoUpdate(),
    );
    // Also run once immediately
    Future.delayed(const Duration(seconds: 5), () => _runAutoUpdate());
  }

  void _runAutoUpdate() {
    final subscriptions = ref.read(subscriptionProvider);
    if (subscriptions.isEmpty) return;

    final now = DateTime.now();
    final s = S(ref.read(localizationProvider));
    for (final sub in subscriptions) {
      if (sub.autoUpdate) {
        // If never updated, or update interval has passed
        final lastUpdate =
            sub.lastUpdate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final nextUpdate = lastUpdate.add(Duration(hours: sub.updateInterval));

        if (now.isAfter(nextUpdate)) {
          ref.read(logProvider.notifier).addLog(
              'info', s.get('sub_sync_start', args: {'name': sub.name}));
          ref.read(subscriptionProvider.notifier).updateSubscription(sub.id);
        }
      }
    }
  }

  void _listenToSettings() {
    // Listen to VPN mode changes
    ref.listen<VpnSettings>(vpnSettingsProvider, (previous, next) async {
      if (state.isRunning && previous != null && previous.mode != next.mode) {
        final s = S(ref.read(localizationProvider));
        ref
            .read(logProvider.notifier)
            .addLog('info', s.get('mode_changed_restarting'));
        _handleRestart();
      }
    });

    // Listen to Routing rules changes
    ref.listen<List<RuleModel>>(routingProvider, (previous, next) async {
      if (state.isRunning && previous != null) {
        final s = S(ref.read(localizationProvider));
        ref
            .read(logProvider.notifier)
            .addLog('info', s.get('rules_changed_restarting'));
        _handleRestart();
      }
    });
  }

  Future<void> _handleRestart() async {
    final s = S(ref.read(localizationProvider));
    ref
        .read(logProvider.notifier)
        .addLog('info', s.get('auto_reconnect_triggered'));

    final now = DateTime.now();
    if (_lastRestartTime != null &&
        now.difference(_lastRestartTime!) < const Duration(seconds: 10)) {
      ref
          .read(logProvider.notifier)
          .addLog('warning', s.get('high_freq_jitter_blocked'));
      return;
    }

    if (_isRestarting) {
      ref
          .read(logProvider.notifier)
          .addLog('warning', s.get('duplicate_restart_ignored'));
      return;
    }

    _isRestarting = true;
    _lastRestartTime = now;

    try {
      ref
          .read(logProvider.notifier)
          .addLog('info', s.get('vpn_disconnected_by_cleanup'));
      await toggleVpn(null); // 先停止
      await Future.delayed(const Duration(milliseconds: 1000));
      final node = ref.read(selectedNodeProvider);
      if (node != null) {
        _startVpn(node); // 再启动
      }
    } finally {
      _isRestarting = false;
    }
  }

  Future<void> stopProxy() async {
    ref
        .read(logProvider.notifier)
        .addLog('info', '[Tracer] 🔌 VPN 状态被修改为断开，触发者: 用户主动停止');
    // 🛑 熄火：主动停止时也需停止雷达
    ref.read(trafficMonitorProvider.notifier).stop();
    await _vpnManager.stopProxy();
    await _syncStatus();

    // [P0] 清除连接状态持久化
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vpn_was_running', false);
  }

  Future<void> _syncStatus() async {
    final bool isRunning = await _vpnManager.getVpnStatus();
    if (isRunning) {
      if (!state.isRunning) {
        // 🚀 点火：状态同步发现运行中，启动流量雷达
        ref.read(trafficMonitorProvider.notifier).start();
        _startDurationTimer();
      }
      final prefs = await SharedPreferences.getInstance();
      final String? lastNodeName = prefs.getString('last_node_name');
      state = state.copyWith(
        isRunning: true,
        connectionStage: 3,
        currentNodeName: lastNodeName,
      );
    } else {
      if (state.isRunning) {
        // 🛑 熄火：状态同步发现已停止，停止流量雷达
        ref.read(trafficMonitorProvider.notifier).stop();
      }
      state = state.copyWith(isRunning: false, connectionStage: 0);
    }
  }

  void _initStatusListener() {
    _vpnManager.setStatusHandler((String method, dynamic arguments) async {
      final s = S(ref.read(localizationProvider));
      debugPrint('[Flutter] 收到原生回调: $method');
      if (method == 'onStatusChanged') {
        final bool isRunning = arguments as bool;
        debugPrint('[Flutter] 状态变更: isRunning=$isRunning');
        if (isRunning) {
          // 🚀 点火：连接成功，启动流量雷达
          ref.read(trafficMonitorProvider.notifier).start();
          _startDurationTimer();
          ref
              .read(logProvider.notifier)
              .addLog('info', s.get('vpn_connected_success_log'));
        } else {
          ref
              .read(logProvider.notifier)
              .addLog('info', s.get('vpn_disconnected_by_kernel'));
          // 🛑 熄火：连接断开，停止流量雷达
          ref.read(trafficMonitorProvider.notifier).stop();
          state = state.copyWith(
            uploadSpeed: 0,
            downloadSpeed: 0,
            totalUpload: 0,
            totalDownload: 0,
            duration: Duration.zero,
            startTime: null,
          );
          ref
              .read(logProvider.notifier)
              .addLog('info', s.get('vpn_disconnected_log'));
        }
        state = state.copyWith(
          isRunning: isRunning,
          isStarting: false,
          connectionStage: isRunning ? 3 : 0,
        );
      } else if (method == 'onError') {
        final String error = arguments as String;
        ref
            .read(logProvider.notifier)
            .addLog('error', s.get('kernel_error_log', args: {'error': error}));
        state = state.copyWith(
          isRunning: false,
          isStarting: false,
          connectionStage: 0,
          lastError: error,
        );
      }
    });
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// 唤醒动作：当窗口重新可见时，强制刷新一次 UI 状态并检查网络连通性
  void refreshOnWake() {
    // ⚡ 唤醒补偿：重启被挂起的计时器和 IO 监听
    _startDurationTimer();
    if (_vpnManager is WindowsVpnManager) {
      (_vpnManager as WindowsVpnManager).refreshOnWake();
    }

    // ⚡ 唤醒补间：在后台期间计时器被挂起，唤醒时立即校准一次时长
    if (state.isRunning && state.startTime != null) {
      state = state.copyWith(
        duration: DateTime.now().difference(state.startTime!),
      );
    } else {
      state = state.copyWith();
    }

    // [P1] 唤醒后静默检查网络状态
    if (state.isRunning && !state.isStarting) {
      _checkConnectivitySilently();
    }
  }

  /// 进入后台动作：挂起所有不必要的定时任务
  void goToBackground() {
    _stopDurationTimer();
    if (_vpnManager is WindowsVpnManager) {
      (_vpnManager as WindowsVpnManager).goToBackground();
    }
  }

  Future<void> _checkConnectivitySilently() async {
    final s = S(ref.read(localizationProvider));
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return;
      }

      // 如果已连接但无法访问 Google (HTTPS)，则触发重启
      final vpnManager = ref.read(vpnManagerProvider);
      ref.read(logProvider.notifier).addLog('debug', s.get('net_recovering'));

      final latency =
          await vpnManager.googlePing().timeout(const Duration(seconds: 5));
      if (latency == -2) {
        debugPrint(
            'VPN: Wake-up check failed (Dead socket), triggering auto-restart.');
        ref.read(logProvider.notifier).addLog('info', s.get('net_recovered'));
        _handleRestart();
      }
    } catch (_) {}
  }

  Future<String> _prepareAssets() async {
    final dir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${dir.path}/data');
    ref
        .read(logProvider.notifier)
        .addLog('debug', '[Flutter] 资源目录路径: ${dataDir.path}');

    if (!await dataDir.exists()) {
      ref
          .read(logProvider.notifier)
          .addLog('debug', '[Flutter] 创建资源目录: ${dataDir.path}');
      await dataDir.create(recursive: true);
    } else {
      ref.read(logProvider.notifier).addLog('debug', '[Flutter] 资源目录已存在');
    }

    final assets = ['geoip.dat', 'geosite.dat'];
    for (final asset in assets) {
      final file = File('${dataDir.path}/$asset');
      if (await file.exists()) {
        final stat = await file.stat();
        ref
            .read(logProvider.notifier)
            .addLog('debug', '[Flutter] $asset 已存在, 大小: ${stat.size} bytes');
        continue;
      }
      ref
          .read(logProvider.notifier)
          .addLog('debug', '[Flutter] 从 Bundle 加载 $asset...');
      final data = await rootBundle.load('assets/data/$asset');
      final bytes = data.buffer.asUint8List();
      ref
          .read(logProvider.notifier)
          .addLog('debug', '[Flutter] 写入 $asset, 大小: ${bytes.length} bytes');
      await file.writeAsBytes(bytes, flush: true);
    }
    ref
        .read(logProvider.notifier)
        .addLog('info', '[Flutter] 资源准备完成, 目录: ${dataDir.path}');
    return dataDir.path;
  }

  Future<int> _findAvailablePort(int startPort, {bool allowLan = false}) async {
    final bindAddr = allowLan ? '0.0.0.0' : '127.0.0.1';
    for (int port = startPort; port < startPort + 100; port++) {
      try {
        // [Audit] 端口探测增强：根据 allowLan 动态切换绑定地址，确保探测结果与 Xray 实际绑定行为一致
        final socket = await ServerSocket.bind(bindAddr, port);
        await socket.close();
        // 额外尝试绑定回环地址，确保双重可用
        if (allowLan) {
          final loopbackSocket = await ServerSocket.bind('127.0.0.1', port);
          await loopbackSocket.close();
        }
        return port;
      } catch (_) {
        continue;
      }
    }
    return startPort; // 如果都失败了，返回原始端口，让内核报错
  }

  void _startVpn(NodeModel node) async {
    final s = S(ref.read(localizationProvider));
    ref.read(trafficMonitorProvider.notifier).stop(); // 重连前清理
    ref
        .read(logProvider.notifier)
        .addLog('info', s.get('preparing_node_log', args: {'name': node.name}));
    debugPrint(
        '[Flutter] 节点信息: address=${node.address}, port=${node.port}, protocol=${node.protocol}');
    state = state.copyWith(isStarting: true, connectionStage: 1);

    try {
      resetStats();
      ref.read(logProvider.notifier).addLog(
            'debug',
            s.get('preparing_resources'),
          );
      final assetDir = await _prepareAssets();

      await Future.delayed(const Duration(milliseconds: 600));
      state = state.copyWith(connectionStage: 2);
      debugPrint('[Flutter] 连接阶段推进到 2 (配置生成)');

      await Future.delayed(const Duration(milliseconds: 800));

      debugPrint('[Flutter] 读取路由规则和设置...');
      final rules = ref.read(routingProvider);
      var settings = ref.read(vpnSettingsProvider);

      // 🛡️ 端口冲突自愈：全量检查 API、SOCKS、HTTP 端口可用性
      final availableApiPort =
          await _findAvailablePort(settings.apiPort); // API 始终是 127.0.0.1
      final availableSocksPort = await _findAvailablePort(settings.socksPort,
          allowLan: settings.allowLan);
      final availableHttpPort = await _findAvailablePort(settings.httpPort,
          allowLan: settings.allowLan);

      bool hasConflict = false;
      if (availableApiPort != settings.apiPort) {
        debugPrint(
            '[Flutter] API 端口冲突! 自动从 ${settings.apiPort} 切换到 $availableApiPort');
        ref
            .read(logProvider.notifier)
            .addLog('warning', 'API 端口冲突，已自动更换为 $availableApiPort');
        hasConflict = true;
      }
      if (availableSocksPort != settings.socksPort) {
        debugPrint(
            '[Flutter] SOCKS 端口冲突! 自动从 ${settings.socksPort} 切换到 $availableSocksPort');
        ref
            .read(logProvider.notifier)
            .addLog('warning', 'SOCKS 端口冲突，已自动更换为 $availableSocksPort');
        hasConflict = true;
      }
      if (availableHttpPort != settings.httpPort) {
        debugPrint(
            '[Flutter] HTTP 端口冲突! 自动从 ${settings.httpPort} 切换到 $availableHttpPort');
        ref
            .read(logProvider.notifier)
            .addLog('warning', 'HTTP 端口冲突，已自动更换为 $availableHttpPort');
        hasConflict = true;
      }

      if (hasConflict) {
        // 更新内存中的设置，确保后续 ConfigGenerator 使用新端口
        // [Audit] 必须使用 await 确保状态变更已落盘，否则 ConfigGenerator 可能读取旧端口导致内核崩溃
        await ref.read(vpnSettingsProvider.notifier).update(settings.copyWith(
              apiPort: availableApiPort,
              socksPort: availableSocksPort,
              httpPort: availableHttpPort,
            ));
        settings = ref.read(vpnSettingsProvider); // 重新获取更新后的设置
      }

      final prefs = await SharedPreferences.getInstance();
      final proxyApps = prefs.getStringList('proxy_apps') ?? [];

      debugPrint(
          '[Flutter] 生成 Xray 配置, 模式: ${settings.mode}, 规则数: ${rules.length}');
      final configDns = settings.mode == VpnMode.direct
          ? '223.5.5.5, 114.114.114.114'
          : settings.dns;
      debugPrint('[Flutter] DNS 配置: $configDns (模式: ${settings.mode})');

      final config = ConfigGenerator.generateConfig(
        node: node,
        rules: rules,
        mode: settings.mode,
        proxyApps: proxyApps,
        bypassLocal: settings.bypassLocal,
        muxEnabled: settings.muxEnabled,
        tcpCongestion: settings.tcpCongestion,
        allowLan: settings.allowLan,
        logLevel: settings.logLevel,
        socksPort: settings.socksPort,
        httpPort: settings.httpPort,
        dns: configDns,
        fakeDns: settings.fakeDns,
        remoteDns: settings.remoteDns,
        domesticDns: settings.domesticDns,
        enableIPv6: settings.enableIPv6,
        dnsHosts: settings.dnsHosts,
        enableTun: settings.enableTun,
        enableFragment: settings.enableFragment,
        enableSniffing: settings.enableSniffing,
        domainStrategy: settings.domainStrategy,
        tunStack: settings.tunStack,
        apiPort: settings.apiPort,
      );
      debugPrint('[Flutter] Xray 配置生成完成, 长度: ${config.length} 字符');

      ref.read(logProvider.notifier).addLog('info', s.get('submitting_config'));
      state = state.copyWith(currentNodeName: node.name);

      await prefs.setString('last_node_name', node.name);

      final payload = "__XRAY_ASSET_DIR__=$assetDir\n"
          "__XRAY_PROXY_APPS__=${proxyApps.join(',')}\n"
          "__XRAY_BYPASS_APPS__=${settings.bypassApps}\n"
          "__XRAY_ALLOW_LAN__=${settings.allowLan}\n"
          "__XRAY_DNS_SERVERS__=$configDns\n"
          "$config";

      debugPrint('[Flutter] Payload 总长度: ${payload.length} 字符');
      debugPrint('[Flutter] 调用 _vpnManager.startProxy()...');

      await _vpnManager.startProxy(payload, node.name);
      debugPrint('[Flutter] _vpnManager.startProxy() 调用完成, 等待原生回调...');

      // [P0] 持久化连接状态，供开机自启重连使用
      await prefs.setBool('vpn_was_running', true);
    } catch (e, stack) {
      final locale = ref.read(localizationProvider);
      final s = S(locale);

      String userFriendlyError = s.get('kernel_start_failed',
          args: {'error': e.toString().split('\n').first});

      if (e is VpnDriverException) {
        // 🛡️ 联动加固：捕获驱动缺失异常并展示友好提示
        userFriendlyError = s.get('driver_missing_error');
      } else {
        final errorStr = e.toString().toLowerCase();

        if (errorStr.contains('bind: only one usage') ||
            errorStr.contains('address already in use')) {
          userFriendlyError = s.get('port_in_use');
        } else if (errorStr.contains('requires elevation') ||
            errorStr.contains('access is denied') ||
            errorStr.contains('tun_elevation_failed')) {
          userFriendlyError = s.get('tun_elevation_failed');
        } else if (errorStr.contains('timeout')) {
          userFriendlyError = s.get('start_timeout');
        }
      }

      ref.read(logProvider.notifier).addLog('error',
          s.get('start_vpn_failed_log', args: {'error': e.toString()}));
      debugPrint('堆栈: $stack');

      state = state.copyWith(
        isStarting: false,
        isRunning: false,
        lastError: userFriendlyError,
      );

      // [Hotfix] 针对 Windows 平台的 TUN 模式提权失败进行特殊处理
      if (e.toString().contains('TUN_ELEVATION_FAILED')) {
        final settings = ref.read(vpnSettingsProvider);
        if (settings.enableTun) {
          ref
              .read(vpnSettingsProvider.notifier)
              .update(settings.copyWith(enableTun: false));
          ref
              .read(logProvider.notifier)
              .addLog('warning', s.get('auto_reset_tun'));
        }
      }
      // rethrow; // 不再重新抛出，改为通过 state.lastError 驱动 UI
    }
  }

  Future<void> toggleVpn(NodeModel? node) async {
    // 💥 死亡边界 2 加固：并发锁，防止极快连按导致的竞态冲突
    if (_isRestarting) return;

    if (state.isRunning) {
      final bool isSwitching =
          node != null && node.name != state.currentNodeName;
      final s = S(ref.read(localizationProvider));

      ref.read(logProvider.notifier).addLog('info',
          isSwitching ? s.get('switching_node') : s.get('stopping_vpn'));

      // 🚀 UI 灵敏度优化：立即切换到“停止中”状态（connectionStage = 0, isStarting = false, 但让 UI 知道正在处理）
      // 虽然 isRunning 还没变，但我们可以通过 connectionStage 来传达意图
      state = state.copyWith(connectionStage: 0);

      debugPrint(
          '[Flutter] 当前状态: isRunning=${state.isRunning}, isSwitching=$isSwitching');
      try {
        debugPrint('[Flutter] 调用 _vpnManager.stopProxy()...');
        // 💥 死亡边界 6 加固：增加业务层超时，防止原生层彻底死锁导致 UI 永久卡死
        await _vpnManager.stopProxy().timeout(const Duration(seconds: 5),
            onTimeout: () {
          debugPrint('[Flutter] _vpnManager.stopProxy() 严重超时，强制跳过');
        });
        debugPrint('[Flutter] _vpnManager.stopProxy() 完成');

        if (isSwitching) {
          debugPrint('[Flutter] 等待服务完全停止...');
          bool vpnStopped = false;
          // 缩短等待轮询，增加灵敏度
          for (int retry = 0; retry < 15 && !vpnStopped; retry++) {
            await Future.delayed(const Duration(milliseconds: 100));
            if (!state.isRunning) {
              vpnStopped = true;
            }
          }
          // 再次检查 state 确保没有在等待期间被其他操作修改
          if (!state.isRunning) {
            _startVpn(node);
          }
        }
      } catch (e) {
        ref.read(logProvider.notifier).addLog('error',
            s.get('stop_vpn_failed_log', args: {'error': e.toString()}));
      }
    } else {
      if (node != null && !state.isStarting) {
        _startVpn(node);
      }
    }
  }

  @override
  void set state(VpnState value) {
    // 🛡️ 【全链路静默】深度防抖与后台节流
    // 如果窗口不可见，绝对禁止向 UI 发送非必要的重绘信号
    final isVisible = ref.read(appVisibilityProvider);
    if (!isVisible) {
      // 在后台时，我们只关心连接状态的“跳变”，不关心数值的“渐变”（如网速、时长）
      final bool isCriticalJump = value.isRunning != state.isRunning ||
          value.isStarting != state.isStarting ||
          value.connectionStage != state.connectionStage ||
          value.lastError != state.lastError;

      if (!isCriticalJump) {
        // 对于后台期间产生的非关键更新，
        // 我们通过拦截 super.state 调用，彻底阻断 Riverpod 的下游通知链路。
        // 这将防止任何由于状态订阅导致的后台 CPU/GPU 活动。
        return;
      }
    }

    super.state = value;
  }

  void resetStats() {
    state = state.copyWith(
      uploadSpeed: 0,
      downloadSpeed: 0,
      totalUpload: 0,
      totalDownload: 0,
      duration: Duration.zero,
      startTime: state.isRunning ? DateTime.now() : null,
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _durationTimer?.cancel();
    _autoUpdateTimer?.cancel();
    super.dispose();
  }

  void updateCurrentNodeName(String name) {
    if (state.currentNodeName != name) {
      state = state.copyWith(currentNodeName: name);
    }
  }
}

final vpnProvider = StateNotifierProvider<VpnNotifier, VpnState>((ref) {
  return VpnNotifier(ref);
});
