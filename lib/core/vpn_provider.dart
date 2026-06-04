import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/proxy_channel.dart';
import 'package:lightning/core/routing_provider.dart';
import 'package:lightning/core/rule_model.dart';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/subscription_provider.dart';
import 'package:lightning/core/config_generator.dart';
import 'package:lightning/core/log_provider.dart';
import 'package:lightning/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

enum VpnMode { global, rule, direct }

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

class VpnNotifier extends StateNotifier<VpnState> with WidgetsBindingObserver {
  final Ref ref;
  VpnNotifier(this.ref) : super(VpnState()) {
    _initStatusListener();
    _syncStatus();
    _listenToSettings();
    _initAutoUpdate();
    WidgetsBinding.instance.addObserver(this);
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
    for (final sub in subscriptions) {
      if (sub.autoUpdate) {
        // If never updated, or update interval has passed
        final lastUpdate =
            sub.lastUpdate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final nextUpdate = lastUpdate.add(Duration(hours: sub.updateInterval));

        if (now.isAfter(nextUpdate)) {
          ref
              .read(logProvider.notifier)
              .addLog('info', '订阅 [${sub.name}] 达到更新间隔，开始自动同步...');
          ref.read(subscriptionProvider.notifier).updateSubscription(sub.id);
        }
      }
    }
  }

  void _listenToSettings() {
    // Listen to VPN mode changes
    ref.listen<VpnSettings>(vpnSettingsProvider, (previous, next) async {
      if (state.isRunning && previous != null && previous.mode != next.mode) {
        ref.read(logProvider.notifier).addLog('info', '检测到运行模式变更，正在更新内核配置...');
        _handleRestart();
      }
    });

    // Listen to Routing rules changes
    ref.listen<List<RuleModel>>(routingProvider, (previous, next) async {
      if (state.isRunning && previous != null) {
        ref.read(logProvider.notifier).addLog('info', '检测到路由规则变更，正在更新内核配置...');
        _handleRestart();
      }
    });
  }

  Future<void> _handleRestart() async {
    final node = ref.read(selectedNodeProvider);
    if (node != null) {
      // Restart VPN with new config
      await ProxyChannel.stopProxy();
      // Wait a bit for the service to fully stop
      await Future.delayed(const Duration(milliseconds: 800));
      toggleVpn(node);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncStatus();
    }
  }

  Future<void> _syncStatus() async {
    final bool isRunning = await ProxyChannel.getVpnStatus();
    if (isRunning) {
      if (!state.isRunning || _statsTimer == null) {
        _startStatsTimer();
      }
      final prefs = await SharedPreferences.getInstance();
      final String? lastNodeName = prefs.getString('last_node_name');
      state = state.copyWith(
        isRunning: true,
        connectionStage: 3,
        currentNodeName: lastNodeName,
      );
    } else {
      if (state.isRunning || _statsTimer != null) {
        _stopStatsTimer();
      }
      state = state.copyWith(isRunning: false, connectionStage: 0);
    }
  }

  Timer? _statsTimer;
  static const MethodChannel _vpnChannel = MethodChannel(
    'com.lightning.proxy/vpn',
  );
  int _lastUp = 0;
  int _lastDown = 0;

  void _initStatusListener() {
    _vpnChannel.setMethodCallHandler((call) async {
      ref
          .read(logProvider.notifier)
          .addLog('debug', '[Flutter] 收到原生回调: ${call.method}');
      if (call.method == 'onStatusChanged') {
        final bool isRunning = call.arguments as bool;
        ref
            .read(logProvider.notifier)
            .addLog('debug', '[Flutter] 状态变更: isRunning=$isRunning');
        if (isRunning) {
          if (_statsTimer == null) _startStatsTimer();
          ref.read(logProvider.notifier).addLog('info', '[Flutter] VPN 连接成功!');
        } else {
          _stopStatsTimer();
          state = state.copyWith(
            uploadSpeed: 0,
            downloadSpeed: 0,
            totalUpload: 0,
            totalDownload: 0,
            duration: Duration.zero,
            startTime: null,
          );
          ref.read(logProvider.notifier).addLog('info', '[Flutter] VPN 已断开');
        }
        state = state.copyWith(
          isRunning: isRunning,
          isStarting: false,
          connectionStage: isRunning ? 3 : 0,
        );
      } else if (call.method == 'onError') {
        final String error = call.arguments as String;
        ref
            .read(logProvider.notifier)
            .addLog('error', '[Flutter] 内核错误: $error');
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

  void _startVpn(NodeModel node) async {
    ref.read(logProvider.notifier).addLog('info', '准备连接节点: ${node.name}');
    ref
        .read(logProvider.notifier)
        .addLog(
          'debug',
          '[Flutter] 节点信息: address=${node.address}, port=${node.port}, protocol=${node.protocol}',
        );
    state = state.copyWith(isStarting: true, connectionStage: 1);

    try {
      resetStats();
      ref.read(logProvider.notifier).addLog('debug', '正在准备资源文件...');
      final assetDir = await _prepareAssets();

      await Future.delayed(const Duration(milliseconds: 600));
      state = state.copyWith(connectionStage: 2);
      ref
          .read(logProvider.notifier)
          .addLog('debug', '[Flutter] 连接阶段推进到 2 (配置生成)');

      await Future.delayed(const Duration(milliseconds: 800));

      ref.read(logProvider.notifier).addLog('debug', '[Flutter] 读取路由规则和设置...');
      final rules = ref.read(routingProvider);
      final settings = ref.read(vpnSettingsProvider);
      final prefs = await SharedPreferences.getInstance();
      final proxyApps = prefs.getStringList('proxy_apps') ?? [];

      ref
          .read(logProvider.notifier)
          .addLog(
            'debug',
            '[Flutter] 生成 Xray 配置, 模式: ${settings.mode}, 规则数: ${rules.length}',
          );
      final configDns = settings.mode == VpnMode.direct
          ? '223.5.5.5, 114.114.114.114'
          : settings.dns;
      ref
          .read(logProvider.notifier)
          .addLog(
            'debug',
            '[Flutter] DNS 配置: $configDns (模式: ${settings.mode})',
          );

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
      );
      ref
          .read(logProvider.notifier)
          .addLog('debug', '[Flutter] Xray 配置生成完成, 长度: ${config.length} 字符');

      ref.read(logProvider.notifier).addLog('info', '正在下发配置到内核并请求 VPN 权限...');
      state = state.copyWith(currentNodeName: node.name);

      await prefs.setString('last_node_name', node.name);

      final payload =
          "__XRAY_ASSET_DIR__=$assetDir\n"
          "__XRAY_PROXY_APPS__=${proxyApps.join(',')}\n"
          "__XRAY_BYPASS_APPS__=${settings.bypassApps}\n"
          "__XRAY_ALLOW_LAN__=${settings.allowLan}\n"
          "__XRAY_DNS_SERVERS__=$configDns\n"
          "$config";

      ref
          .read(logProvider.notifier)
          .addLog('debug', '[Flutter] Payload 总长度: ${payload.length} 字符');
      ref
          .read(logProvider.notifier)
          .addLog('debug', '[Flutter] 调用 ProxyChannel.startProxy()...');

      await ProxyChannel.startProxy(payload, node.name);
      ref
          .read(logProvider.notifier)
          .addLog(
            'info',
            '[Flutter] ProxyChannel.startProxy() 调用完成, 等待原生回调...',
          );
    } catch (e, stack) {
      ref.read(logProvider.notifier).addLog('error', '启动 VPN 失败: $e');
      ref.read(logProvider.notifier).addLog('debug', '堆栈: $stack');
      state = state.copyWith(isStarting: false, isRunning: false);
    }
  }

  void toggleVpn(NodeModel? node) async {
    if (state.isRunning) {
      final bool isSwitching =
          node != null && node.name != state.currentNodeName;

      ref
          .read(logProvider.notifier)
          .addLog('info', isSwitching ? '正在切换节点...' : '正在停止 VPN...');
      ref
          .read(logProvider.notifier)
          .addLog(
            'debug',
            '[Flutter] 当前状态: isRunning=${state.isRunning}, isSwitching=$isSwitching',
          );
      try {
        ref
            .read(logProvider.notifier)
            .addLog('debug', '[Flutter] 调用 ProxyChannel.stopProxy()...');
        await ProxyChannel.stopProxy();
        ref
            .read(logProvider.notifier)
            .addLog('debug', '[Flutter] ProxyChannel.stopProxy() 完成');

        if (isSwitching) {
          ref
              .read(logProvider.notifier)
              .addLog('debug', '[Flutter] 等待服务完全停止...');
          bool vpnStopped = false;
          for (int retry = 0; retry < 10 && !vpnStopped; retry++) {
            await Future.delayed(const Duration(milliseconds: 200));
            final currentState = ref.read(vpnProvider);
            if (!currentState.isRunning) {
              vpnStopped = true;
            }
          }
          _startVpn(node);
        }
      } catch (e) {
        ref.read(logProvider.notifier).addLog('error', '断开 VPN 失败: $e');
      }
    } else {
      if (node != null) {
        _startVpn(node);
      }
    }
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _lastUp = 0;
    _lastDown = 0;
    final now = DateTime.now();
    state = state.copyWith(startTime: now, duration: Duration.zero);

    bool isUpdating = false;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (state.isRunning && !isUpdating) {
        isUpdating = true;
        try {
          final String stats = await ProxyChannel.queryStats();

          if (stats.isEmpty) {
            isUpdating = false;
            return;
          }

          final parts = stats.split(',').map((e) => e.trim()).toList();
          if (parts.length >= 2) {
            final int currentUp = int.tryParse(parts[0]) ?? 0;
            final int currentDown = int.tryParse(parts[1]) ?? 0;

            final duration = DateTime.now().difference(state.startTime ?? now);

            if (_lastUp > 0 || _lastDown > 0) {
              // Handle counter reset to avoid negative values
              final upSpeed = currentUp >= _lastUp ? currentUp - _lastUp : 0;
              final downSpeed = currentDown >= _lastDown
                  ? currentDown - _lastDown
                  : 0;

              state = state.copyWith(
                uploadSpeed: upSpeed,
                downloadSpeed: downSpeed,
                totalUpload: currentUp,
                totalDownload: currentDown,
                duration: duration,
              );
            } else {
              // On the very first tick after _lastUp/Down were 0,
              // we still want to show total upload/download.
              state = state.copyWith(
                totalUpload: currentUp,
                totalDownload: currentDown,
                duration: duration,
              );
            }

            _lastUp = currentUp;
            _lastDown = currentDown;
          }
        } catch (e) {
          // ignore
        } finally {
          isUpdating = false;
        }
      }
    });
  }

  void _stopStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = null;
    state = state.copyWith(
      uploadSpeed: 0,
      downloadSpeed: 0,
      startTime: null,
      duration: Duration.zero,
      currentNodeName: null, // Reset node name on stop
    );
  }

  void resetStats() {
    _lastUp = 0;
    _lastDown = 0;
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
    WidgetsBinding.instance.removeObserver(this);
    _autoUpdateTimer?.cancel();
    _stopStatsTimer();
    super.dispose();
  }

  Future<void> requestBatteryOptimization() async {
    await ProxyChannel.requestBatteryOptimization();
  }

  Future<bool> requestNotificationPermission() async {
    return await ProxyChannel.requestNotificationPermission();
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
