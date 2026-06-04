import 'package:flutter/services.dart';

class AppInfo {
  final String name;
  final String packageName;
  final bool isSystem;

  AppInfo({
    required this.name,
    required this.packageName,
    required this.isSystem,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      name: map['name'] as String,
      packageName: map['packageName'] as String,
      isSystem: map['isSystem'] as bool,
    );
  }
}

class AppChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.lightning.proxy/apps',
  );

  static Future<List<AppInfo>> getInstalledApps() async {
    final List<dynamic> result = await _channel.invokeMethod(
      'getInstalledApps',
    );
    return result.map((e) => AppInfo.fromMap(e as Map)).toList();
  }
}
