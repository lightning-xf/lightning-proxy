import 'dart:io';
import 'dart:convert';

class UwpApp {
  final String name;
  final String packageFamilyName;
  final bool isExempted;

  UwpApp({
    required this.name,
    required this.packageFamilyName,
    required this.isExempted,
  });
}

class UwpExemptionManager {
  static Future<List<UwpApp>> getUwpApps() async {
    if (!Platform.isWindows) return [];

    try {
      // 1. 获取所有已豁免的应用 SID 列表
      final exemptResult =
          await Process.run('CheckNetIsolation.exe', ['LoopbackExempt', '-s']);
      final exemptedSids = _parseExemptedSids(exemptResult.stdout as String);

      // 2. 使用 PowerShell 获取所有 UWP 应用及其 SID
      // 注意：这里需要管理员权限才能获取完整的 PackageFamilyName 和 SID 映射
      final psCommand =
          'Get-AppxPackage | Select-Object Name, PackageFamilyName, PackageFamilyName | ConvertTo-Json';
      final psResult = await Process.run('powershell', [
        '-Command',
        'Get-AppxPackage | Select-Object Name, PackageFamilyName | ConvertTo-Json'
      ]);

      if (psResult.exitCode != 0) return [];

      final List<dynamic> appsJson = jsonDecode(psResult.stdout as String);

      // 3. 获取每个应用的 SID 以便进行匹配
      // 实际上 CheckNetIsolation 可以直接使用 PackageFamilyName 进行操作
      // 为了准确判断状态，我们通过 SID 或者 PackageFamilyName 匹配

      List<UwpApp> apps = [];
      for (var app in appsJson) {
        final pfn = app['PackageFamilyName'] as String;
        final name = app['Name'] as String;

        // 判断是否在豁免列表中
        // CheckNetIsolation -s 输出中包含 PackageFamilyName
        bool exempted = exemptedSids.contains(pfn.toLowerCase());

        apps.add(UwpApp(
          name: name,
          packageFamilyName: pfn,
          isExempted: exempted,
        ));
      }

      // 按名称排序
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return apps;
    } catch (e) {
      print('Error getting UWP apps: $e');
      return [];
    }
  }

  static Set<String> _parseExemptedSids(String output) {
    final Set<String> pfns = {};
    // CheckNetIsolation -s 的输出格式通常包含 "AppContainer Name : [PackageFamilyName]"
    final lines = output.split('\n');
    for (var line in lines) {
      if (line.contains('AppContainer Name :')) {
        final pfn = line.split(':').last.trim().toLowerCase();
        if (pfn.isNotEmpty) {
          pfns.add(pfn);
        }
      }
    }
    return pfns;
  }

  static Future<bool> setExemption(
      String packageFamilyName, bool exempt) async {
    if (!Platform.isWindows) return false;

    try {
      final arg = exempt ? '-a' : '-d';
      final result = await Process.run(
        'CheckNetIsolation.exe',
        ['LoopbackExempt', arg, '-n=$packageFamilyName'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (e) {
      print('Error setting UWP exemption: $e');
      return false;
    }
  }

  static Future<void> setAllExemption(List<String> pfns, bool exempt) async {
    for (final pfn in pfns) {
      await setExemption(pfn, exempt);
    }
  }
}
