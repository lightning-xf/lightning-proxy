import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/vpn_manager_provider.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/log_provider.dart';
import 'package:lightning/utils/format_utils.dart';
import 'package:lightning/pages/settings_page.dart';
import 'package:lightning/core/app_visibility_provider.dart';

class SpeedPoint {
  final int upload;
  final int download;
  final DateTime time;
  SpeedPoint(this.upload, this.download, this.time);
}

class TrafficState {
  final int uploadSpeed; // 字节/秒
  final int downloadSpeed; // 字节/秒
  final int totalUplink; // 总字节
  final int totalDownlink; // 总字节
  final bool isInitial; // 是否是首次获取数据
  final List<SpeedPoint> speedHistory; // [P2] 流量历史数据

  TrafficState({
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.totalUplink = 0,
    this.totalDownlink = 0,
    this.isInitial = true,
    this.speedHistory = const [],
  });

  TrafficState copyWith({
    int? uploadSpeed,
    int? downloadSpeed,
    int? totalUplink,
    int? totalDownlink,
    bool? isInitial,
    List<SpeedPoint>? speedHistory,
  }) {
    return TrafficState(
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      totalUplink: totalUplink ?? this.totalUplink,
      totalDownlink: totalDownlink ?? this.totalDownlink,
      isInitial: isInitial ?? this.isInitial,
      speedHistory: speedHistory ?? this.speedHistory,
    );
  }
}

class _IsolateParams {
  final String corePath;
  final String apiUrl;

  _IsolateParams(this.corePath, this.apiUrl);
}

class _TrafficResult {
  final int currentUp;
  final int currentDown;
  final String? error;

  _TrafficResult(this.currentUp, this.currentDown, {this.error});
}

class TrafficMonitorNotifier extends StateNotifier<TrafficState> {
  final Ref _ref;
  Timer? _timer;
  int _lastUplink = 0;
  int _lastDownlink = 0;
  bool _isFetching = false;
  bool _isPaused = false;
  static const int _intervalSeconds = 2; // 降频至 2 秒

  TrafficMonitorNotifier(this._ref) : super(TrafficState());

  @override
  void set state(TrafficState value) {
    // 🛡️ 【全链路静默】深度加固
    // 当窗口隐藏时，网速 Provider 必须彻底停止向下游发送任何通知信号。
    // 这将阻断所有关联 Widget 的 Rebuild 链条。
    final isVisible = _ref.read(appVisibilityProvider);
    if (!isVisible) {
      // 仅静默同步内部数据，绝不触发 super.state = value (Riverpod 通知)
      // 注意：StateNotifier 的 state 是通过 setter 触发通知的，
      // 我们通过反射或私有方式绕过通知是不可能的，但我们可以选择不调用 super.state。
      // 由于我们只需要在恢复时看到最新数据，我们可以在后台期间只更新内部变量。
      return;
    }
    super.state = value;
  }

  void start() {
    // 🛡️ 审计加固：启动前检查可见性
    final isVisible = _ref.read(appVisibilityProvider);
    if (!isVisible) {
      debugPrint('TrafficMonitor: Window hidden, skipping start.');
      return;
    }

    if (!_isPaused && _timer != null) return;
    _isPaused = false;
    _timer?.cancel(); // 🛡️ 彻底杜绝多 Timer 并行，先 cancel 再创建
    _timer = null;

    _lastUplink = 0;
    _lastDownlink = 0;
    _isFetching = false;
    state = TrafficState();

    _timer = Timer.periodic(const Duration(seconds: _intervalSeconds), (timer) {
      if (!_isPaused) {
        _fetchStats();
      }
    });
  }

  void pause() {
    debugPrint('TrafficMonitor: 🧊 进入深度休眠，停止流量雷达。');
    _isPaused = true;
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(uploadSpeed: 0, downloadSpeed: 0);
  }

  void resume() {
    if (_isPaused) {
      debugPrint('TrafficMonitor: ⚡ 恢复流量轮询 (唤醒动作)...');
      _isPaused = false;
      start(); // 🛡️ 逻辑闭环：resume 应当直接调用 start 重新初始化 Timer
    }
  }

  void stop() {
    debugPrint('TrafficMonitor: 🛑 熄火，停止流量雷达...');
    _timer?.cancel();
    _timer = null;
    _isFetching = false;
    _isPaused = false;
    _lastUplink = 0;
    _lastDownlink = 0;
    state = TrafficState(); // 重置速率和总量为 0
  }

  Future<void> _fetchStats() async {
    if (_isFetching) return;

    final vpnState = _ref.read(vpnProvider);
    if (!vpnState.isRunning) {
      stop();
      return;
    }

    _isFetching = true;
    try {
      final vpnManager = _ref.read(vpnManagerProvider);
      final vpnSettings = _ref.read(vpnSettingsProvider);
      final corePath = await vpnManager.getCorePath();

      // 🚀 架构核心重构：将进程拉起与 JSON 解析全部移至独立 Isolate 执行
      // 彻底解放 UI 线程，消除 Process.run 带来的主线程抖动
      final result = await compute(_isolateFetchAndParse,
          _IsolateParams(corePath, '127.0.0.1:${vpnSettings.apiPort}'));

      if (result.error != null) {
        _ref.read(logProvider.notifier).addLog('error', result.error!);
        return;
      }

      final currentUp = result.currentUp;
      final currentDown = result.currentDown;

      // [Fix] 首次获取数据时不计算速度，仅建立基准值
      if (state.isInitial) {
        _lastUplink = currentUp;
        _lastDownlink = currentDown;
        state = state.copyWith(
            isInitial: false,
            totalUplink: _lastUplink,
            totalDownlink: _lastDownlink);
        return;
      }

      // 🧮 架构方案二：时序闭环与 Delta (差值) 算法防飙升
      // 由于是 2秒 采样一次，计算速率时需要除以间隔时间
      final upSpeed = (currentUp - _lastUplink) ~/ _intervalSeconds;
      final downSpeed = (currentDown - _lastDownlink) ~/ _intervalSeconds;
      final uploadSpeed = upSpeed < 0 ? 0 : upSpeed;
      final downloadSpeed = downSpeed < 0 ? 0 : downSpeed;

      // 更新内部状态
      _lastUplink = currentUp;
      _lastDownlink = currentDown;

      // [P2] 更新历史记录
      final newHistory = List<SpeedPoint>.from(state.speedHistory);
      newHistory.add(SpeedPoint(uploadSpeed, downloadSpeed, DateTime.now()));
      if (newHistory.length > 30) {
        newHistory.removeAt(0); // 保持最近 60 秒 (30 * 2s)
      }

      final debugLogMsg =
          '[TrafficMonitor] 🚀 速率 -> ↑ ${FormatUtils.formatBytes(uploadSpeed)}/s, ↓ ${FormatUtils.formatBytes(downloadSpeed)}/s (累计 ↑ ${FormatUtils.formatBytes(currentUp)}, ↓ ${FormatUtils.formatBytes(currentDown)})';

      // 📝 将流量数据归类为 debug 日志上报至实时日志页面
      _ref.read(logProvider.notifier).addLog('debug', debugLogMsg);

      // 广播状态给 UI
      state = state.copyWith(
        uploadSpeed: uploadSpeed,
        downloadSpeed: downloadSpeed,
        totalUplink: currentUp,
        totalDownlink: currentDown,
        isInitial: false,
        speedHistory: newHistory,
      );
    } catch (e) {
      debugPrint('TrafficMonitor: 流量解析异常: $e');
    } finally {
      _isFetching = false;
    }
  }

  /// 🛰️ 独立 Isolate 运行函数：负责阻塞性的进程调用与 CPU 密集型的字符串解析
  static Future<_TrafficResult> _isolateFetchAndParse(
      _IsolateParams params) async {
    try {
      // 1. 在后台线程拉起进程 (不影响 UI)
      final result = await Process.run(
          params.corePath, ['api', 'statsquery', '-server=${params.apiUrl}']);

      final output = "${result.stdout}\n${result.stderr}".trim();
      if (output.isEmpty) {
        return _TrafficResult(0, 0, error: '[Error] 🚨 流量雷达异常: 内核返回数据为空');
      }

      // 2. 解析 JSON (极端反向数据注入防护)
      final dynamic decoded = jsonDecode(output);

      // 💥 死亡边界 3 加固：严格校验 JSON 结构，防止 Malformed Data 导致 Isolate 崩溃
      if (decoded is! Map<String, dynamic>) {
        return _TrafficResult(0, 0,
            error: '[Error] 🚨 流量雷达异常: 内核返回非预期格式 (Not a Map)');
      }

      final List<dynamic>? stats =
          decoded['stat'] is List ? decoded['stat'] : null;
      if (stats == null) {
        return _TrafficResult(0, 0, error: '[Error] 🚨 流量雷达异常: 统计字段不存在或格式错误');
      }

      int currentUp = 0;
      int currentDown = 0;

      for (final item in stats) {
        if (item is! Map<String, dynamic>) continue; // 健壮性检查

        final String name = item['name']?.toString() ?? '';
        final bool isUplink = name.contains('uplink');
        final bool isDownlink = name.contains('downlink');
        final bool isApi = name.contains('api');

        if ((isUplink || isDownlink) && !isApi) {
          final dynamic valueRaw = item['value'];
          final int value =
              valueRaw != null ? (int.tryParse(valueRaw.toString()) ?? 0) : 0;

          if (isUplink) {
            currentUp += value;
          } else if (isDownlink) {
            currentDown += value;
          }
        }
      }
      return _TrafficResult(currentUp, currentDown);
    } catch (e) {
      return _TrafficResult(0, 0, error: '[Error] 🚨 流量雷达 Isolate 解析失败: $e');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

final trafficMonitorProvider =
    StateNotifierProvider<TrafficMonitorNotifier, TrafficState>((ref) {
  // 保持存活，确保 UI 切换页面时统计不中断
  return TrafficMonitorNotifier(ref);
});
