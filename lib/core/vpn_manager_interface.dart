import 'package:lightning/core/node_model.dart';

/// VPN 驱动相关的异常 (如 wintun.dll 缺失)
class VpnDriverException implements Exception {
  final String message;
  VpnDriverException(this.message);
  @override
  String toString() => message;
}

abstract class IVpnManager {
  /// 启动 VPN
  Future<void> startProxy(String config, String nodeName);

  /// 停止 VPN
  Future<void> stopProxy();

  /// 获取当前 VPN 运行状态
  Future<bool> getVpnStatus();

  /// 查询流量统计信息，返回格式通常为 "up,down"
  Future<String> queryStats();

  /// 获取内核版本
  Future<String> getCoreVersion();

  /// 获取内核可执行文件路径
  Future<String> getCorePath();

  /// 测量单个配置的延迟
  Future<int> measureSingleDelay(String config);

  /// Google Ping 测试
  Future<int> googlePing();

  /// 批量测量延迟
  Future<List<int>> measureBatchDelay(List<String> configs);

  /// 强制停止正在进行的批量测速
  Future<void> stopBatchTest();

  /// TCP Ping 测试
  Future<int> tcpPing(String address, int port);

  /// 更新原生端设置 (主要用于 Android/Windows)
  Future<void> updateSettings({
    bool? autoStart,
    bool? autoReconnect,
    bool? showTraffic,
    bool? useSystemProxy, // 新增参数用于 Windows
  });

  /// 检查是否忽略电池优化
  Future<bool> isIgnoringBatteryOptimizations();

  /// 设置状态变更回调
  void setStatusHandler(
      Future<dynamic> Function(String method, dynamic arguments) handler);
}
