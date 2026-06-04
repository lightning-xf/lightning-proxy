import 'package:flutter/services.dart';

class ProxyChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.lightning.proxy/vpn',
  );

  static Future<void> startProxy(String config, String nodeName) async {
    try {
      await _channel.invokeMethod('startProxy', {
        'config': config,
        'nodeName': nodeName,
      });
    } on PlatformException catch (e) {
      throw 'Failed to start proxy: ${e.message}';
    }
  }

  static Future<void> stopProxy() async {
    try {
      await _channel.invokeMethod('stopProxy');
    } on PlatformException catch (e) {
      throw 'Failed to stop proxy: ${e.message}';
    }
  }

  static Future<bool> getVpnStatus() async {
    try {
      final bool status = await _channel.invokeMethod('getVpnStatus');
      return status;
    } on PlatformException catch (_) {
      return false;
    }
  }

  static Future<String> getCoreVersion() async {
    try {
      final String version = await _channel.invokeMethod('getCoreVersion');
      return version;
    } on PlatformException catch (_) {
      return "Unknown";
    }
  }

  static Future<String> queryStats() async {
    try {
      final String stats = await _channel.invokeMethod('queryStats');
      return stats;
    } on PlatformException catch (_) {
      return "0,0";
    }
  }

  static Future<int> measureSingleDelay(String config) async {
    try {
      final int delay = await _channel.invokeMethod('measureSingleDelay', {
        'config': config,
      });
      return delay;
    } catch (e) {
      return -2; // Timeout or error
    }
  }

  static Future<int> googlePing() async {
    try {
      final int delay = await _channel.invokeMethod('googlePing');
      return delay;
    } catch (e) {
      return -2;
    }
  }

  static Future<List<int>> measureBatchDelay(List<String> configs) async {
    try {
      final String result = await _channel.invokeMethod('measureBatchDelay', {
        'configs': configs,
      });
      if (result.isEmpty) return List.filled(configs.length, -2);
      return result.split(',').map((e) => int.tryParse(e) ?? -2).toList();
    } catch (e) {
      return List.filled(configs.length, -2);
    }
  }

  static Future<int> tcpPing(String address, int port) async {
    try {
      final int delay = await _channel.invokeMethod('tcpPing', {
        'address': address,
        'port': port,
      });
      return delay;
    } catch (e) {
      return -2;
    }
  }

  static Future<void> requestBatteryOptimization() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimization');
    } on PlatformException catch (_) {}
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod('isIgnoringBatteryOptimizations');
    } on PlatformException catch (_) {
      return false;
    }
  }

  static Future<void> updateSettings({
    bool? autoStart,
    bool? autoReconnect,
    bool? showTraffic,
  }) async {
    try {
      await _channel.invokeMethod('updateSettings', {
        'autoStart': autoStart,
        'autoReconnect': autoReconnect,
        'showTraffic': showTraffic,
      });
    } on PlatformException catch (_) {}
  }

  static Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod('requestNotificationPermission');
    } on PlatformException catch (_) {
      return false;
    }
  }
}
