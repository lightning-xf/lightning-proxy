import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/pages/settings_page.dart';

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;

  LogEntry({required this.timestamp, required this.level, required this.message});
}

class LogNotifier extends StateNotifier<List<LogEntry>> {
  static const _methodChannel = MethodChannel('com.lightning.proxy/log');
  static const _eventChannel = EventChannel('com.lightning.proxy/vpn_logs');

  LogNotifier() : super([]) {
    _methodChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLog') {
        final level = call.arguments['level'] as String;
        final message = call.arguments['message'] as String;
        addLog(level, message);
      }
    });

    _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is String) {
        // 确保 container 已初始化
        if (_container == null) return;

        // 过滤性能开销较大的流量统计日志
        if (event.contains('CRITICAL: JNI Traffic Data ->')) {
          return;
        }

        String level = 'info';
        String message = event;
        
        if (event.contains('|')) {
          final parts = event.split('|');
          level = parts[0];
          message = parts.sublist(1).join('|');
        }

        // 第二步：拦截并翻译日志
        if (message.contains('auto-node-')) {
          final vpnState = _container!.read(vpnProvider);
          
          // 使用正则匹配 auto-node-数字
          final regExp = RegExp(r'auto-node-\d+');
          final matches = regExp.allMatches(message);
          
          String translatedMessage = message;
          String? lastMatchedRealName;

          message = translatedMessage;

          // 第三步：同步更新主 UI 的当前节点状态
          if (lastMatchedRealName != null && vpnState.isRunning) {
            _container!.read(vpnProvider.notifier).updateCurrentNodeName(lastMatchedRealName);
          }
        }

        addLog(level, message);
      }
    });
  }

  // Add this to allow accessing Ref in LogNotifier
  ProviderContainer? _container;
  void setContainer(ProviderContainer c) => _container = c;

  void addLog(String level, String message) {
    if (_container == null) return;

    // 检查日志等级设置
    final settings = _container!.read(vpnSettingsProvider);
    final levels = {
      'debug': 0,
      'info': 1,
      'warning': 2,
      'error': 3,
      'none': 4,
    };
    
    final currentLevel = levels[settings.logLevel.toLowerCase()] ?? 1;
    final logPriority = levels[level.toLowerCase()] ?? 1;
    
    // 如果当前日志优先级低于设置的最小输出等级，则忽略
    if (logPriority < currentLevel) {
      return;
    }

    state = [
      LogEntry(timestamp: DateTime.now(), level: level, message: message),
      ...state.take(999), // Keep last 1000 logs
    ];
  }

  void clearLogs() {
    state = [];
  }
}

final logProvider = StateNotifierProvider<LogNotifier, List<LogEntry>>((ref) {
  return LogNotifier();
});
