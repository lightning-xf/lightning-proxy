import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/pages/settings_page.dart';

import 'package:lightning/core/app_visibility_provider.dart';

enum LogLevel { debug, info, warning, error, fatal }

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });
}

class LogNotifier extends StateNotifier<List<LogEntry>> {
  LogNotifier() : super([]);

  @override
  void set state(List<LogEntry> value) {
    // 🛡️ 【全链路静默】日志审计
    // 后台运行时，禁止向 UI 发送日志列表更新信号。
    // 日志将累积在内部 buffer，直到唤醒时再同步。
    if (_container != null) {
      final isVisible = _container!.read(appVisibilityProvider);
      if (!isVisible) return;
    }
    super.state = value;
  }

  // 🛡️ 架构方案三：渲染节流与容量锁
  static const int MAX_LOG_LINES = 1000;
  final List<LogEntry> _logBuffer = [];
  Timer? _throttleTimer;

  // Add this to allow accessing Ref in LogNotifier
  ProviderContainer? _container;
  void setContainer(ProviderContainer c) => _container = c;

  void addLog(String level, String message) {
    if (_container == null) return;

    // 🧊 P0级休眠优化：如果窗口不可见，且不是关键错误，则阻断日志处理逻辑，降低 CPU 占用
    final isVisible = _container!.read(appVisibilityProvider);
    final effectiveLevel = level.toLowerCase();
    final isCritical = effectiveLevel == 'error' || effectiveLevel == 'fatal';

    if (!isVisible && !isCritical) {
      return;
    }

    // 🔍 架构方案二：精准分类与级别映射
    String mappedLevel = effectiveLevel;

    // 正则嗅探真实级别 (针对 Xray 原生输出)
    final xrayLevelMatch =
        RegExp(r'\[(Debug|Info|Warning|Error|Fatal)\]', caseSensitive: false)
            .firstMatch(message);
    if (xrayLevelMatch != null) {
      mappedLevel = xrayLevelMatch.group(1)!.toLowerCase();
    }

    // 检查日志等级设置
    final settings = _container!.read(vpnSettingsProvider);
    final levels = {
      'debug': 0,
      'info': 1,
      'warning': 2,
      'error': 3,
      'fatal': 4,
      'none': 5
    };

    final currentLevel = levels[settings.logLevel.toLowerCase()] ?? 1;
    final logPriority = levels[mappedLevel] ?? 1;

    // 如果当前日志优先级低于设置的最小输出等级，且不是强制显示的 info (来自 Flutter 端)，则忽略
    if (logPriority < currentLevel && mappedLevel != 'info') {
      return;
    }

    // 将日志存入缓冲队列
    _logBuffer.insert(
        0,
        LogEntry(
          timestamp: DateTime.now(),
          level: mappedLevel,
          message: message,
        ));

    // 🛡️ 容量锁（Ring Buffer）：超过时截断
    if (_logBuffer.length > MAX_LOG_LINES) {
      _logBuffer.removeRange(MAX_LOG_LINES ~/ 2, _logBuffer.length);
    }

    // 🛡️ 渲染防抖 (Throttling)：500ms 批量更新一次 UI
    if (_throttleTimer == null || !_throttleTimer!.isActive) {
      _throttleTimer = Timer(const Duration(milliseconds: 500), () {
        state = List.from(_logBuffer);
      });
    }
  }

  void clearLogs() {
    _logBuffer.clear();
    state = [];
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }
}

final logProvider = StateNotifierProvider<LogNotifier, List<LogEntry>>((ref) {
  return LogNotifier();
});
