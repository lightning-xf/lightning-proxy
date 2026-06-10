import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lightning/core/vpn_manager_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

class WindowsVpnManager implements IVpnManager {
  Process? _xrayProcess;
  StreamSubscription? _stdoutSubscription;
  StreamSubscription? _stderrSubscription;
  int? _xrayPid; // 追踪 Xray 进程 PID，用于精准销毁
  Future<dynamic> Function(String method, dynamic arguments)? _statusHandler;
  void Function(String level, String message)? _windowsLogHandler;
  bool _isStopping = false;
  int? _watchdogPid; // 新增：看门狗进程 PID
  bool _useSystemProxy = true;
  int _currentHttpPort = 10809; // 追踪当前使用的 HTTP 端口
  Completer<void>? _exitCompleter;
  final List<String> _lastStderrLines = [];

  // ♻️ 句柄泄露防线：复用 HttpClient
  HttpClient? _httpClient;

  static const String _registryPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  WindowsVpnManager() {
    // 终极防线：冷启动时执行网络自愈清理
    _emergencyNetworkCleanup();
  }

  /// 🛰️ 静态自愈接口：供 main.dart 全局异常捕获调用
  /// 采用同步/极速异步设计，确保在崩溃前恢复网络环境
  static void forceCleanupSync() {
    debugPrint('Windows VPN: 触发全局异常自愈清理 (Sync)...');
    try {
      // 💥 死亡边界 4 加固：使用超时限制防止注册表服务挂起导致主线程死锁
      // 由于 Process.runSync 不支持原生超时，我们采用广谱的命令超时控制 (Windows timeout)
      // 但更稳妥的是通过物理分离执行。此处使用 cmd /c start 极速拉起一个独立清理进程
      // 确保主线程能在 100ms 内脱身。
      Process.runSync('cmd', [
        '/c',
        'start /min reg add "$_registryPath" /v ProxyEnable /t REG_DWORD /d 0 /f'
      ]);

      debugPrint('Windows VPN: 全局自愈清理指令已发出 (独立进程托管)。');
    } catch (e) {
      debugPrint('Windows VPN: 全局自愈清理失败: $e');
    }
  }

  /// 紧急网络自愈清理 (P1 级防线)
  /// 解决 TUN 模式崩溃后导致的残留脏路由和全局断网问题
  Future<void> _emergencyNetworkCleanup() async {
    debugPrint('Windows VPN: 执行冷启动网络自愈清理 (P1 级防线)...');
    try {
      // 1. 强制清理 Wintun 脏路由 (通过 PowerShell)
      // 寻找并删除任何网卡名称包含 "wintun" 的路由，防止断网残留
      final cleanupRoutesPs =
          'Get-NetRoute -InterfaceAlias "*wintun*" -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:\$false -ErrorAction SilentlyContinue';
      await Process.run('powershell', ['-Command', cleanupRoutesPs]);

      // 2. 物理禁用系统代理，防止残留代理设置导致网页打不开
      await _disableSystemProxy();

      debugPrint('Windows VPN: 网络自愈清理完成。');
    } catch (e) {
      debugPrint('Windows VPN: 网络自愈清理过程中出现非致命异常: $e');
    }
  }

  static const int defaultSocksPort = 10808;
  static const int defaultHttpPort = 10809;

  Future<bool> isPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      // 🛡️ 端口探测加固：优先尝试绑定 0.0.0.0 (anyIPv4) 以探测全接口占用情况
      socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (socket != null) {
        await socket.close();
        // [Audit] 增加探测后的冷却时间，防止 Xray 紧接着启动时遇到端口尚未释放的竞态
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  Future<void> _checkPortAvailability(String jsonConfig) async {
    try {
      final config = jsonDecode(jsonConfig) as Map<String, dynamic>;
      final inbounds = config['inbounds'] as List<dynamic>?;
      if (inbounds != null) {
        for (final inbound in inbounds) {
          final port = inbound['port'] as int?;
          if (port != null) {
            final available = await isPortAvailable(port);
            if (!available) {
              final tag = inbound['tag'] ?? 'unknown';
              throw Exception('端口 $port ($tag) 已被占用，请关闭占用该端口的程序或更换端口');
            }
          }
        }
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('端口检测失败: $e');
    }
  }

  /// 启用系统代理
  Future<void> _enableSystemProxy([int? httpPort]) async {
    final port = httpPort ?? _currentHttpPort;
    debugPrint('Windows VPN: Enabling system proxy (127.0.0.1:$port)...');
    try {
      // ProxyEnable = 1
      await Process.run('reg', [
        'add',
        _registryPath,
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '1',
        '/f'
      ]);
      // ProxyServer = 127.0.0.1:$port
      await Process.run('reg', [
        'add',
        _registryPath,
        '/v',
        'ProxyServer',
        '/t',
        'REG_SZ',
        '/d',
        '127.0.0.1:$port',
        '/f'
      ]);
      // ProxyOverride: 深度对标 v2rayN，确保局域网、回环地址及私有网段完全绕过
      // 解决本地打印机、NAS、虚拟机等通信瘫痪问题
      const String bypassList =
          'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>';
      await Process.run('reg', [
        'add',
        _registryPath,
        '/v',
        'ProxyOverride',
        '/t',
        'REG_SZ',
        '/d',
        bypassList,
        '/f'
      ]);
      debugPrint('Windows VPN: System proxy enabled.');
    } catch (e) {
      debugPrint('Windows VPN: Failed to enable system proxy: $e');
    }
  }

  /// 禁用系统代理
  Future<void> _disableSystemProxy() async {
    debugPrint('Windows VPN: Disabling system proxy...');
    try {
      // 💥 死亡边界 5 加固：增加超时限制，防止注册表挂起导致整个 stopProxy 链条死锁
      await Process.run('reg', [
        'add',
        _registryPath,
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '0',
        '/f'
      ]).timeout(const Duration(seconds: 3));

      // 🧹 深度清理：同时清空服务器和排除列表，防止残留干扰其他代理软件
      await Process.run('reg', [
        'add',
        _registryPath,
        '/v',
        'ProxyServer',
        '/t',
        'REG_SZ',
        '/d',
        '',
        '/f'
      ]).timeout(const Duration(seconds: 2));

      debugPrint('Windows VPN: System proxy disabled and cleaned.');
    } catch (e) {
      debugPrint(
          'Windows VPN: Failed to disable system proxy (or timeout): $e');
    }
  }

  Future<String> _ensureCoreAssets() async {
    final supportDir = await getApplicationSupportDirectory();
    final workingDir = supportDir.path;

    final assets = {
      'assets/windows/xray-core.exe': p.join(workingDir, 'xray-core.exe'),
      'assets/windows/geoip.dat': p.join(workingDir, 'geoip.dat'),
      'assets/windows/geosite.dat': p.join(workingDir, 'geosite.dat'),
      'assets/windows/wintun.dll':
          p.join(workingDir, 'wintun.dll'), // 新增 Wintun 驱动支持
    };

    for (var entry in assets.entries) {
      final file = File(entry.value);
      // 强制更新核心文件，确保越狱版内核生效
      final isCore = entry.key.contains('xray-core.exe');
      if (!await file.exists() || isCore) {
        if (isCore)
          debugPrint('Windows VPN: Force updating core asset: ${file.path}');
        try {
          final data = await rootBundle.load(entry.key);
          final bytes = data.buffer.asUint8List();
          await file.writeAsBytes(bytes, flush: true);
        } catch (e) {
          if (entry.key.contains('wintun.dll')) {
            throw VpnDriverException(
                '缺少核心虚拟网卡驱动 wintun.dll，请确保程序目录完整或以管理员身份重新安装。');
          }
          debugPrint('Windows VPN: Failed to extract ${entry.key}: $e');
        }
      }
    }

    // 再次深度校验 wintun.dll 是否真实存在 (针对 TUN 模式)
    if (!await File(p.join(workingDir, 'wintun.dll')).exists()) {
      throw VpnDriverException('检测到 TUN 模式核心组件 wintun.dll 丢失，无法启动加密隧道。');
    }

    return p.join(workingDir, 'xray-core.exe');
  }

  /// 启动进程看门狗：监控主程序 PID，若主程序消失则强杀内核并清理代理
  Future<void> _startWatchdog(int xrayPid) async {
    try {
      final parentPid = pid;
      // PowerShell 看门狗脚本：
      // 1. 等待主进程退出
      // 2. 主进程退出后，尝试强杀 Xray 进程
      // 3. 彻底清理系统代理设置 (ProxyEnable = 0, 并清理 Server/Override)
      final watchdogScript = 'Wait-Process -Id $parentPid; ' +
          'Stop-Process -Id $xrayPid -Force -ErrorAction SilentlyContinue; ' +
          'reg add "$_registryPath" /v ProxyEnable /t REG_DWORD /d 0 /f; ' +
          'reg add "$_registryPath" /v ProxyServer /t REG_SZ /d "" /f; ' +
          'reg add "$_registryPath" /v ProxyOverride /t REG_SZ /d "" /f';

      // [Fix] 精准捕获看门狗 PID：使用 ($p.Id) 确保输出仅包含数字
      final psCommand =
          '\$p = Start-Process powershell -ArgumentList "-Command `"$watchdogScript`"" -WindowStyle Hidden -PassThru; if(\$p) { \$p.Id }';
      final result = await Process.run('powershell', ['-Command', psCommand]);

      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        _watchdogPid = int.tryParse(output);
        debugPrint(
            'Windows VPN: Watchdog started (PID: $_watchdogPid) for Xray PID: $xrayPid');
      }
    } catch (e) {
      debugPrint('Windows VPN: Failed to start watchdog: $e');
    }
  }

  /// 停止看门狗：当手动断开连接时，应当杀掉看门狗，避免它误触清理逻辑
  Future<void> _stopWatchdog() async {
    if (_watchdogPid != null) {
      try {
        await Process.run(
            'taskkill', ['/F', '/PID', _watchdogPid.toString(), '/T']);
        debugPrint('Windows VPN: Watchdog (PID: $_watchdogPid) stopped.');
      } catch (_) {}
      _watchdogPid = null;
    }
  }

  @override
  Future<void> startProxy(String config, String nodeName) async {
    // 启动前再次确保环境纯净，清理可能存在的脏路由
    await _emergencyNetworkCleanup();

    if (_xrayProcess != null) {
      await stopProxy();
    }

    try {
      final corePath = await _ensureCoreAssets();
      final workingDir = File(corePath).parent.path;
      final configFile = File(p.join(workingDir, 'config.json'));

      // The config passed from vpn_provider might contain prefix variables
      // We need the raw JSON config. If vpn_provider sends a payload with metadata,
      // we extract the JSON part.
      String jsonConfig = config;
      if (config.contains('{')) {
        jsonConfig = config.substring(config.indexOf('{'));
      }

      await _checkPortAvailability(jsonConfig);

      await configFile.writeAsString(jsonConfig);

      bool isTun = jsonConfig.contains('"protocol": "tun"');

      if (isTun) {
        debugPrint(
            'Windows VPN: TUN mode detected, requesting elevation via PowerShell...');
        // 使用 PowerShell 以管理员权限拉起 Xray，并设置为隐藏窗口
        // 使用 -PassThru 获取进程对象并输出其 Id (PID)
        final psCommand =
            '\$p = Start-Process -FilePath "$corePath" -ArgumentList "-c config.json" -WorkingDirectory "$workingDir" -Verb runAs -WindowStyle Hidden -PassThru; if(\$p) { \$p.Id }';
        final result = await Process.run('powershell', ['-Command', psCommand]);

        if (result.exitCode != 0) {
          throw Exception('TUN_ELEVATION_FAILED: 需要管理员权限才能开启 TUN 模式');
        }

        // 解析返回的 PID
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          _xrayPid = int.tryParse(output);
          debugPrint('Windows VPN: TUN mode Xray started with PID: $_xrayPid');
          if (_xrayPid != null) {
            unawaited(_startWatchdog(_xrayPid!));
          }
        }

        _xrayProcess = null;
      } else {
        debugPrint('Windows VPN: Starting Xray process: $corePath');
        _resetExitCompleter();
        _xrayProcess = await Process.start(
          corePath,
          ['-c', 'config.json'],
          workingDirectory: workingDir,
        );
        _xrayPid = _xrayProcess?.pid;
        debugPrint('Windows VPN: Xray started with PID: $_xrayPid');
        if (_xrayPid != null) {
          unawaited(_startWatchdog(_xrayPid!));
        }

        _stdoutSubscription =
            _xrayProcess!.stdout.transform(utf8.decoder).listen((data) {
          final trimmed = data.trim();
          if (trimmed.isNotEmpty) {
            // debugPrint('Xray STDOUT: $trimmed'); // 移除控制台冗余打印
            // 默认传入 'debug'，让 LogProvider 内部正则嗅探真实级别
            _windowsLogHandler?.call('debug', '[Xray] $trimmed');
          }
        });

        _stderrSubscription =
            _xrayProcess!.stderr.transform(utf8.decoder).listen((data) {
          final trimmed = data.trim();
          if (trimmed.isNotEmpty) {
            // debugPrint('Xray STDERR: $trimmed'); // 移除控制台冗余打印
            _windowsLogHandler?.call('error', '[Xray] $trimmed');
            _lastStderrLines.add(trimmed);
            if (_lastStderrLines.length > 20) {
              _lastStderrLines.removeAt(0);
            }
          }
        });

        _xrayProcess!.exitCode.then((code) {
          if (code != 0) {
            debugPrint('=' * 80);
            debugPrint('[FATAL ERROR] 🚨 Xray 内核异常崩溃退出! ExitCode: $code');
            debugPrint('=' * 80);
            debugPrint('最后 20 条 stderr 日志:');
            for (var i = 0; i < _lastStderrLines.length; i++) {
              debugPrint('  [$i] ${_lastStderrLines[i]}');
            }
            debugPrint('=' * 80);
            _windowsLogHandler?.call(
                'error', '[FATAL ERROR] 🚨 Xray 内核异常崩溃退出! ExitCode: $code');
            for (var line in _lastStderrLines) {
              _windowsLogHandler?.call('error', '  $line');
            }
          } else {
            debugPrint('Windows VPN: Xray process exited with code $code');
          }
          _xrayProcess = null;
          _lastStderrLines.clear();

          // 停止看门狗
          unawaited(_stopWatchdog());

          _disableSystemProxy();
          _exitCompleter?.complete();
          if (!_isStopping) {
            _statusHandler?.call('onStatusChanged', false);
          }
        });
      }

      if (_useSystemProxy && !isTun) {
        int httpPort = defaultHttpPort;
        try {
          final configMap = jsonDecode(jsonConfig) as Map<String, dynamic>;
          final inbounds = configMap['inbounds'] as List<dynamic>?;
          if (inbounds != null) {
            final httpInbound = inbounds
                .firstWhere((i) => i['protocol'] == 'http', orElse: () => null);
            if (httpInbound != null) {
              httpPort = httpInbound['port'] as int? ?? defaultHttpPort;
            }
          }
        } catch (e) {
          debugPrint('Windows VPN: Failed to parse http port from config: $e');
        }
        _currentHttpPort = httpPort; // 保存当前端口
        await _enableSystemProxy(httpPort);
      }
      _statusHandler?.call('onStatusChanged', true);
    } catch (e) {
      debugPrint('Windows VPN: Failed to start Xray: $e');
      _disableSystemProxy();
      _statusHandler?.call('onError', e.toString());
    }
  }

  /// 进入后台动作：挂起 IO 监听以压榨 CPU
  void goToBackground() {
    debugPrint('Windows VPN: Pausing Xray IO listeners (Deep Sleep).');
    _stdoutSubscription?.pause();
    _stderrSubscription?.pause();
  }

  /// 唤醒动作：恢复 IO 监听
  void refreshOnWake() {
    debugPrint('Windows VPN: Resuming Xray IO listeners.');
    _stdoutSubscription?.resume();
    _stderrSubscription?.resume();
  }

  @override
  Future<void> stopProxy() async {
    if (_isStopping) return; // 💥 并发防御
    _isStopping = true;

    try {
      debugPrint(
          'Windows VPN: Stopping Xray (PID: $_xrayPid) and disabling proxy...');

      // 0. 停止看门狗，避免手动停止时触发清理脚本
      unawaited(_stopWatchdog());

      // 1. 优先恢复网络设置 (必须 await 确保在进程关闭前网络已通)
      await _disableSystemProxy();

      // 2. 终止进程
      if (_xrayProcess != null) {
        _xrayProcess!.kill();
        _xrayProcess = null;
      }

      // 3. 核心加固：使用 PID 精准击杀，增加超时
      if (_xrayPid != null) {
        try {
          await Process.run(
                  'taskkill', ['/F', '/PID', _xrayPid.toString(), '/T'])
              .timeout(const Duration(seconds: 3));
          debugPrint('Windows VPN: Precise kill executed for PID: $_xrayPid');
        } catch (e) {
          debugPrint('Windows VPN: taskkill failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Windows VPN: Stop process failed: $e');
    } finally {
      _xrayPid = null;
      _xrayProcess = null;
      _isStopping = false;

      // 4. 无论如何确保状态回调发出，打破 UI 转圈
      _statusHandler?.call('onStatusChanged', false);
    }
  }

  @override
  Future<bool> getVpnStatus() async {
    return _xrayProcess != null;
  }

  Future<void> get whenExited {
    return _exitCompleter?.future ?? Future.value();
  }

  void _resetExitCompleter() {
    _exitCompleter = Completer<void>();
  }

  @override
  Future<String> queryStats() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final corePath = p.join(supportDir.path, 'xray-core.exe');

      // 使用 CLI 工具查询统计信息，返回 Prototext 格式
      final result = await Process.run(
          corePath, ['api', 'statsquery', '-server=127.0.0.1:10085']);

      // 架构方案一：强行合并 stdout 和 stderr，防止数据错位
      final output = "${result.stdout}\n${result.stderr}".trim();

      if (result.exitCode == 0) {
        return output;
      }

      if (output.isNotEmpty) {
        debugPrint(
            'Windows VPN: statsquery exit with code ${result.exitCode}, but has output: $output');
        return output;
      }

      return "";
    } catch (e) {
      debugPrint('Windows VPN: Failed to query stats via CLI: $e');
      return "";
    }
  }

  @override
  Future<String> getCoreVersion() async {
    return "Xray-core Windows Sidecar";
  }

  @override
  Future<String> getCorePath() async {
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'xray-core.exe');
  }

  @override
  Future<int> measureSingleDelay(String config) async {
    return -1;
  }

  @override
  Future<int> googlePing() async {
    // ♻️ 句柄泄露防线：网络探测器池化/复用
    _httpClient ??= HttpClient();
    final client = _httpClient!;

    try {
      client.findProxy = (url) => 'PROXY 127.0.0.1:${defaultSocksPort};DIRECT';
      client.badCertificateCallback = (cert, host, port) => true;
      // [Audit] 限制连接空闲时间，防止句柄长期占用
      client.idleTimeout = const Duration(seconds: 10);
      client.connectionTimeout = const Duration(seconds: 5);

      final results = <int>[];
      for (int i = 0; i < 3; i++) {
        try {
          final stopwatch = Stopwatch()..start();
          final request = await client
              .getUrl(Uri.parse('https://www.google.com/generate_204'));
          request.headers
              .set(HttpHeaders.connectionHeader, 'keep-alive'); // 优化：复用连接
          request.headers.set(HttpHeaders.userAgentHeader,
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36');

          HttpClientResponse? response;
          try {
            response = await request.close().timeout(
                  const Duration(milliseconds: 5000),
                );
          } on TimeoutException {
            // Timeout, ignore
          }

          stopwatch.stop();
          if (response != null &&
              (response.statusCode == 204 || response.statusCode == 200)) {
            results.add(stopwatch.elapsedMilliseconds);
          }

          await Future.delayed(const Duration(milliseconds: 150));
        } catch (_) {
          // Ignore failure
        }
      }

      if (results.isEmpty) {
        return -2;
      }

      results.sort();
      return results[results.length ~/ 2];
    } catch (e) {
      debugPrint('Windows VPN: Google Ping failed: $e');
      return -2;
    }
    // 注意：不再在这里关闭 client，而是等待 dispose 时释放
  }

  Process? _batchTestProcess; // 用于追踪正在运行的测速进程

  @override
  Future<void> stopBatchTest() async {
    if (_batchTestProcess != null) {
      debugPrint('Windows VPN: 正在强制终止测速进程...');
      _batchTestProcess!.kill(ProcessSignal.sigkill);
      _batchTestProcess = null;
    }
  }

  @override
  Future<List<int>> measureBatchDelay(List<String> configs) async {
    Process? testProcess;
    File? configFile;
    List<int> results = [];
    final testLogBuffer = <String>[];

    try {
      // ======================
      // 1. 解析配置（兼容两种模式：单个完整配置或多个单节点配置）
      // ======================
      final tempDir = Directory.systemTemp;
      configFile = File('${tempDir.path}/xray_batch_test.json');

      late Map<String, dynamic> superConfig;
      late int nodeCount;
      late List<int> ports;

      if (configs.length == 1) {
        // 单个完整配置模式（直接使用 ConfigGenerator.generateBatchTestConfig 生成的）
        final rawConfig = configs[0];
        final startIndex = rawConfig.indexOf('{');
        final jsonStr =
            startIndex != -1 ? rawConfig.substring(startIndex) : rawConfig;
        superConfig = jsonDecode(jsonStr) as Map<String, dynamic>;

        // 统计节点数量（inbound 数量）
        final inbounds = superConfig['inbounds'] as List;
        nodeCount = inbounds.length;
        ports = inbounds.map((inb) => inb['port'] as int).toList();

        testLogBuffer.add("[BatchTest] 单个完整配置模式 (${nodeCount} 个节点)");
      } else {
        // 多个单节点配置模式（兼容旧逻辑，自己组装）
        final inbounds = <Map<String, dynamic>>[];
        final outbounds = <Map<String, dynamic>>[];
        final rules = <Map<String, dynamic>>[];
        ports = <int>[];

        for (int i = 0; i < configs.length; i++) {
          final inboundPort = 30000 + i;
          ports.add(inboundPort);
          inbounds.add({
            'tag': 'test_in_$i',
            'port': inboundPort,
            'listen': '127.0.0.1',
            'protocol': 'socks',
            'settings': {'auth': 'noauth', 'udp': true},
          });

          try {
            final rawConfig = configs[i];
            final startIdx = rawConfig.indexOf('{');
            final jsonStr =
                startIdx != -1 ? rawConfig.substring(startIdx) : rawConfig;
            final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

            if (parsed.containsKey('outbounds') &&
                parsed['outbounds'] is List) {
              final originalOutbounds = parsed['outbounds'] as List;
              if (originalOutbounds.isNotEmpty) {
                final outbound =
                    Map<String, dynamic>.from(originalOutbounds.first as Map);
                outbound['tag'] = 'test_out_$i';
                outbounds.add(outbound);
              }
            }
          } catch (e) {
            testLogBuffer.add("[BatchTest] 解析配置 $i 失败: $e");
          }

          rules.add({
            'type': 'field',
            'inboundTag': ['test_in_$i'],
            'outboundTag': 'test_out_$i',
          });
        }

        outbounds.add({
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {'domainStrategy': 'UseIPv4'},
        });

        superConfig = {
          'log': {'loglevel': 'none'},
          'dns': {
            'servers': ['8.8.8.8', '1.1.1.1', 'localhost'],
            'queryStrategy': 'UseIPv4',
          },
          'inbounds': inbounds,
          'outbounds': outbounds,
          'routing': {'domainStrategy': 'AsIs', 'rules': rules},
        };

        nodeCount = configs.length;
        testLogBuffer.add("[BatchTest] 多配置组装模式 (${nodeCount} 个节点)");
      }

      // 初始化结果数组
      results = List<int>.filled(nodeCount, -2);

      // 写入配置
      await configFile.writeAsString(jsonEncode(superConfig));
      testLogBuffer.add("[BatchTest] 配置已写入 (${nodeCount} 个节点)");

      // ======================
      // 2. 启动沙盒进程
      // ======================
      final corePath = await _ensureCoreAssets();
      final workingDir = File(corePath).parent.path;

      _batchTestProcess = testProcess = await Process.start(
        corePath,
        ['-c', configFile.path],
        workingDirectory: workingDir,
      );

      // 收集 Xray 输出（仅用于调试）
      testProcess!.stderr.transform(utf8.decoder).listen((data) {
        // 静默处理，不影响性能
      });

      testProcess!.stdout.transform(utf8.decoder).listen((data) {
        // 静默处理，不影响性能
      });

      // 缩短预热时间到 500ms（V2RayN 风格）
      testLogBuffer.add("[BatchTest] 等待 Xray 内核预热...");
      await Future.delayed(const Duration(milliseconds: 500));

      // ======================
      // 3. 并发测速（极速优化版 - 提高并发、大幅压缩超时）
      // ======================
      const maxConcurrency = 16; // 进一步提高并发
      const testTimeout = Duration(milliseconds: 3000); // 压缩到 3 秒，提升体感速度

      Future<void> testSingleIndex(int i, int port) async {
        final client = HttpClient();

        try {
          client.findProxy = (url) => 'PROXY 127.0.0.1:$port';
          client.badCertificateCallback = (cert, host, port) => true;
          client.connectionTimeout = testTimeout;
          client.idleTimeout = testTimeout;

          final stopwatch = Stopwatch()..start();

          final request = await client
              .getUrl(Uri.parse('https://www.google.com/generate_204'))
              .timeout(testTimeout);

          request.headers.set(HttpHeaders.connectionHeader, 'close');
          request.headers.set(HttpHeaders.userAgentHeader,
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36');

          final response = await request.close().timeout(testTimeout);
          stopwatch.stop();

          if (response.statusCode == 200 || response.statusCode == 204) {
            results[i] = stopwatch.elapsedMilliseconds;
            testLogBuffer.add("[测试 $i] 成功: ${results[i]}ms (端口 $port)");
          } else {
            results[i] = -2;
            testLogBuffer.add("[测试 $i] HTTP 错误: ${response.statusCode}");
          }
        } catch (e) {
          results[i] = -2;
          // testLogBuffer.add("[测试 $i] 异常: $e (端口 $port)");
        } finally {
          client.close(force: true);
        }
      }

      // 分批执行
      for (int i = 0; i < nodeCount; i += maxConcurrency) {
        final batch = <Future<void>>[];
        for (int j = 0; j < maxConcurrency && i + j < nodeCount; j++) {
          batch.add(testSingleIndex(i + j, ports[i + j]));
        }
        await Future.wait(batch);
      }

      // 输出日志
      if (_windowsLogHandler != null) {
        for (final log in testLogBuffer) {
          _windowsLogHandler!('debug', log);
        }
      }
    } finally {
      // ======================
      // 4. 终极清理
      // ======================
      _batchTestProcess = null;
      try {
        testProcess?.kill();
      } catch (_) {}

      try {
        await configFile?.delete();
      } catch (_) {}
    }

    return results;
  }

  @override
  Future<int> tcpPing(String address, int port) async {
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      // 延长超时到5秒，提高成功率
      socket = await Socket.connect(address, port).timeout(
        const Duration(seconds: 5),
      );
      stopwatch.stop();
      // 如果延迟小于5000ms，返回实际延迟，否则返回超时
      final latency = stopwatch.elapsedMilliseconds;
      if (latency < 5000) {
        return latency;
      } else {
        return -2;
      }
    } on TimeoutException {
      return -2;
    } catch (_) {
      return -2;
    } finally {
      try {
        // 确保socket被正确关闭，防止资源泄漏
        socket?.destroy();
      } catch (_) {
        // 忽略关闭错误
      }
    }
  }

  @override
  Future<void> updateSettings({
    bool? autoStart,
    bool? autoReconnect,
    bool? showTraffic,
    bool? useSystemProxy, // 新增参数
  }) async {
    if (useSystemProxy != null) {
      _useSystemProxy = useSystemProxy;
      debugPrint(
          'Windows VPN: System proxy control updated to: $_useSystemProxy');
      // 如果正在运行，动态切换系统代理
      if (_xrayProcess != null) {
        if (_useSystemProxy) {
          await _enableSystemProxy();
        } else {
          await _disableSystemProxy();
        }
      }
    }
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    return true;
  }

  @override
  void setStatusHandler(
      Future<dynamic> Function(String method, dynamic arguments) handler) {
    _statusHandler = handler;
  }

  void setWindowsLogHandler(
      void Function(String level, String message) handler) {
    _windowsLogHandler = handler;
  }
}
