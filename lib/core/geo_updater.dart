import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class GeoUpdater {
  static const String _geoIPUrl =
      'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat';
  static const String _geoSiteUrl =
      'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat';

  // 备用镜像源 (如果 GitHub 访问困难，用户可以切换或系统自动回退)
  static const String _geoIPMirror =
      'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat';
  static const String _geoSiteMirror =
      'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat';

  Future<void> updateGeoFiles({
    void Function(double)? onProgress,
    bool useMirror = true,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final workingDir = supportDir.path;

    await _downloadFile(
      useMirror ? _geoIPMirror : _geoIPUrl,
      p.join(workingDir, 'geoip.dat.new'),
      onProgress: (p) => onProgress?.call(p * 0.5),
    );

    await _downloadFile(
      useMirror ? _geoSiteMirror : _geoSiteUrl,
      p.join(workingDir, 'geosite.dat.new'),
      onProgress: (p) => onProgress?.call(0.5 + p * 0.5),
    );

    // 校验并替换
    await _replaceFile(
        p.join(workingDir, 'geoip.dat.new'), p.join(workingDir, 'geoip.dat'));
    await _replaceFile(p.join(workingDir, 'geosite.dat.new'),
        p.join(workingDir, 'geosite.dat'));

    debugPrint('GeoUpdater: 所有路由规则库更新完成');
  }

  Future<void> _downloadFile(String url, String savePath,
      {void Function(double)? onProgress}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('下载失败: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      int downloaded = 0;
      final file = File(savePath);
      final sink = file.openWrite();

      await response.forEach((chunk) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress?.call(downloaded / contentLength);
        }
      });

      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  Future<void> _replaceFile(String newPath, String oldPath) async {
    final newFile = File(newPath);
    if (await newFile.exists()) {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
      await newFile.rename(oldPath);
    }
  }
}
