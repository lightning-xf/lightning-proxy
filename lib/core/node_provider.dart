import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/core/config_generator.dart';
import 'package:lightning/core/proxy_channel.dart';
import 'package:lightning/core/consistency_checker.dart';

import 'package:lightning/core/vpn_provider.dart';

class NodeNotifier extends StateNotifier<List<NodeModel>> {
  final Ref _ref;
  bool _isProcessing = false; // 内部状态守卫：防止异步竞争
  bool get isProcessing => _isProcessing;

  bool _isTesting = false; // [Fix] 测速总电闸，支持中途停火
  bool get isTesting => _isTesting;

  // --- UI 节流缓冲区相关 ---
  final Map<String, int> _speedBuffer = {}; // 存储节点 ID 与延迟值的映射
  Timer? _throttleTimer;
  static const int _throttleDurationMs = 300; // 300ms 批量刷新一次 UI

  NodeNotifier(this._ref) : super([]) {
    _loadNodes();
  }

  @override
  void dispose() {
    _isTesting = false; // [Fix] 物理熄火，防止 disposed state 崩溃
    _throttleTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNodes() async {
    final prefs = await SharedPreferences.getInstance();
    final nodesJson = prefs.getStringList('nodes') ?? [];
    state = nodesJson.map((e) => NodeModel.fromJson(jsonDecode(e))).toList();
  }

  Future<void> _saveNodes() async {
    final currentNodes = List<NodeModel>.from(state);

    // 物理隔离至后台 Isolate 执行全量序列化，防止主线程卡死
    final nodesJson = await compute(_serializeNodes, currentNodes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('nodes', nodesJson);
  }

  // 顶层函数供 compute 使用
  static List<String> _serializeNodes(List<NodeModel> nodes) {
    return nodes.map((e) => jsonEncode(e.toJson())).toList();
  }

  void addNode(NodeModel node) {
    state = [...state, node];
    _saveNodes();
  }

  void addNodes(List<NodeModel> newNodes) {
    if (newNodes.isEmpty) return;
    state = [...state, ...newNodes];
    _saveNodes();
  }

  void removeNode(String id) {
    state = state.where((e) => e.id != id).toList();
    _saveNodes();
  }

  void updateNode(NodeModel node) {
    state = [
      for (final n in state)
        if (n.id == node.id) node else n,
    ];
    _saveNodes();
  }

  void toggleFavorite(String id) {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isFavorite: !n.isFavorite) else n,
    ];
    _saveNodes();
  }

  bool _isFakeNode(NodeModel node) {
    final name = node.name.toLowerCase();
    final address = node.address.toLowerCase();
    final port = node.port;

    // 1. 检查地址是否为本地回环或全零
    if (address == '127.0.0.1' ||
        address == '0.0.0.0' ||
        address == 'localhost') {
      return true;
    }

    // 2. 检查端口是否无效
    if (port <= 0 || port > 65535) {
      return true;
    }

    // 3. 检查名称关键字
    final fakeKeywords = ['剩余', '到期', '重置', '流量', '有效期', '套餐'];
    for (final kw in fakeKeywords) {
      if (name.contains(kw)) {
        return true;
      }
    }

    return false;
  }

  Future<void> testLatency(
    String id, {
    bool useTcpPing = false,
    bool useGooglePing = false,
  }) async {
    final nodeIndex = state.indexWhere((e) => e.id == id);
    if (nodeIndex == -1) return;

    final node = state[nodeIndex];

    // 秒杀假节点
    if (_isFakeNode(node)) {
      if (!mounted) return;
      state = [
        ...state.sublist(0, nodeIndex),
        node.copyWith(latency: -2),
        ...state.sublist(nodeIndex + 1),
      ];
      _saveNodes();
      return;
    }

    // 1. Set status to testing (-3)
    if (!mounted) return;
    state = [
      ...state.sublist(0, nodeIndex),
      node.copyWith(latency: -3),
      ...state.sublist(nodeIndex + 1),
    ];

    // [Fix] 同步更新已选择节点的测试状态
    final selectedNode = _ref.read(selectedNodeProvider);
    if (selectedNode != null && selectedNode.id == id) {
      _ref
          .read(selectedNodeProvider.notifier)
          .setNode(selectedNode.copyWith(latency: -3));
    }

    int latency = -2;
    try {
      if (useGooglePing) {
        latency = await ProxyChannel.googlePing().timeout(
          const Duration(seconds: 15),
          onTimeout: () => -2,
        );
      } else if (useTcpPing) {
        latency = await ProxyChannel.tcpPing(node.address, node.port);
      } else {
        // Real Delay: 统一采用导入节点时的批量并行测速逻辑 (Batch Test)
        final isVpnRunning = _ref.read(vpnProvider).isRunning;

        if (isVpnRunning) {
          // 如果 VPN 正在运行，为避免干扰主进程，回退到 TCP Ping（与导入逻辑一致）
          latency = await ProxyChannel.tcpPing(node.address, node.port);
        } else {
          final dir = await getApplicationDocumentsDirectory();
          final assetDir = "${dir.path}/data";
          final nodeConfig = ConfigGenerator.generateBatchTestConfig([node]);
          final payload = "__XRAY_ASSET_DIR__=$assetDir\n$nodeConfig";

          final latencies = await ProxyChannel.measureBatchDelay([payload]);
          latency = latencies.isNotEmpty ? latencies.first : -2;
        }
      }
    } catch (e) {
      debugPrint("Latency test error for ${node.name}: $e");
      latency = -2;
    }

    // [Fix] 异步守卫：await 结束后必须检查 mounted，防止 state 更新崩溃
    if (!mounted) return;

    await updateNodeLatency(id, latency);
  }

  Future<void> updateNodeLatency(String id, int latency) async {
    // 如果底层返回 -1 (超时/错误)，我们统一映射为 UI 层的 -2 (超时)
    if (latency == -1) latency = -2;

    // [Fix] 同步更新已选择节点的延迟显示
    final selectedNode = _ref.read(selectedNodeProvider);
    if (selectedNode != null && selectedNode.id == id) {
      _ref
          .read(selectedNodeProvider.notifier)
          .setNode(selectedNode.copyWith(latency: latency));
    }

    // --- 使用节流缓冲区更新 ---
    _speedBuffer[id] = latency;

    if (_throttleTimer == null || !_throttleTimer!.isActive) {
      _throttleTimer = Timer(Duration(milliseconds: _throttleDurationMs), () {
        if (!mounted || _speedBuffer.isEmpty) return;

        // 批量更新 state
        state = [
          for (final n in state)
            if (_speedBuffer.containsKey(n.id))
              n.copyWith(latency: _speedBuffer[n.id])
            else
              n,
        ];

        _speedBuffer.clear();
        _saveNodes();
      });
    }
  }

  Future<void> testAllLatencies({
    bool useTcpPing = false,
    List<String>? ids,
  }) async {
    if (state.isEmpty || _isProcessing || _isTesting) return;

    // 工业级双重锁保护
    _isProcessing = true;
    _isTesting = true;

    try {
      final nodesToTest = ids != null
          ? state.where((n) => ids.contains(n.id)).toList()
          : List<NodeModel>.from(state);

      if (nodesToTest.isEmpty) {
        // [Fix] 早期 Return 必须手动释放锁，或者将 nodesToTest 解析移入 try 块
        _isProcessing = false;
        _isTesting = false;
        return;
      }

      // 1. Mark target nodes as testing (-3)
      if (!mounted) {
        _isProcessing = false;
        _isTesting = false;
        return;
      }
      state = [
        for (final n in state)
          if (ids == null || ids.contains(n.id))
            (_isFakeNode(n) ? n.copyWith(latency: -2) : n.copyWith(latency: -3))
          else
            n,
      ];

      // [Fix] 同步更新已选择节点的测试状态
      final selectedNode = _ref.read(selectedNodeProvider);
      if (selectedNode != null &&
          (ids == null || ids.contains(selectedNode.id))) {
        _ref
            .read(selectedNodeProvider.notifier)
            .setNode(
              selectedNode.copyWith(
                latency: _isFakeNode(selectedNode) ? -2 : -3,
              ),
            );
      }

      final realNodesToTest = nodesToTest
          .where((n) => !_isFakeNode(n))
          .toList();
      if (realNodesToTest.isEmpty) {
        await _saveNodes();
        _isProcessing = false;
        _isTesting = false;
        return;
      }

      // 2. 核心：引入并发控制流控队列 (Worker Pool)
      const int maxConcurrency = 32;
      int index = 0;

      // [防死锁加固] 定义单节点测速任务，确保内部异常不逃逸
      Future<void> worker() async {
        while (_isTesting) {
          NodeModel? node;
          // 原子化获取下一个任务索引
          if (index < realNodesToTest.length) {
            node = realNodesToTest[index++];
          } else {
            break;
          }

          int resultLatency = -1;
          try {
            // [Catch-All] 严防任何解析、网络或平台调用抛出的 FormatException/TypeError
            if (useTcpPing) {
              resultLatency = await ProxyChannel.tcpPing(
                node.address,
                node.port,
              ).timeout(const Duration(seconds: 4));
            } else {
              final dir = await getApplicationDocumentsDirectory();
              final assetDir = "${dir.path}/data";
              final config = ConfigGenerator.generateBatchTestConfig([node]);
              final payload = "__XRAY_ASSET_DIR__=$assetDir\n$config";

              // [Fix] 铁血重构：Dart 层 measureBatchDelay 必须挂载 6s 终极 Timeout 防线
              final latencies = await ProxyChannel.measureBatchDelay([
                payload,
              ]).timeout(const Duration(seconds: 6));

              // [Fix] 铁血重构：严防 JSON 解析空值与缺失 ID 导致的幽灵状态
              if (latencies.isNotEmpty) {
                resultLatency = latencies.first;
              } else {
                debugPrint(
                  "Worker: Batch test returned empty for ${node.name}",
                );
                resultLatency = -1; // 强制设为超时
              }
            }
          } catch (e) {
            debugPrint("Worker exception for node ${node.name}: $e");
            resultLatency =
                -1; // 发生任何异常（如 FormatException, TimeoutException）均视为超时
          } finally {
            // 确保即便发生异常，UI 也能收到“测速完成”的反馈（显示为红色超时）
            if (mounted) {
              await updateNodeLatency(node.id, resultLatency);
            }
          }
        }
      }

      // 启动指定数量的 worker 并发执行
      final List<Future<void>> workers = List.generate(
        realNodesToTest.length < maxConcurrency
            ? realNodesToTest.length
            : maxConcurrency,
        (_) => worker(),
      );

      // 使用 wait 等待所有 worker 结束，即使其中某些抛出未捕获异常（虽然已被 try-catch 包裹）
      await Future.wait(workers).catchError((e) {
        debugPrint("Worker pool error: $e");
        return [];
      });
    } catch (e) {
      debugPrint("Global testAllLatencies exception: $e");
    } finally {
      // [铁血防线] 无论发生什么，状态锁必须释放，UI 绝不允许永久转圈
      _isProcessing = false;
      _isTesting = false;

      // [Fix] 强制清空节流缓冲区并清理残留的 -3 状态
      // 确保即便发生异常，所有标记为 -3 的节点都能恢复正常状态（null 或测得的值）
      if (mounted) {
        state = [
          for (final n in state)
            if (_speedBuffer.containsKey(n.id))
              n.copyWith(latency: _speedBuffer[n.id])
            else if (n.latency == -3)
              n.copyWith(latency: null)
            else
              n,
        ];

        // 同步更新 SelectedNode
        final selectedNode = _ref.read(selectedNodeProvider);
        if (selectedNode != null) {
          final updatedSelected = state.firstWhere(
            (n) => n.id == selectedNode.id,
            orElse: () => selectedNode,
          );
          if (updatedSelected.latency != selectedNode.latency) {
            _ref.read(selectedNodeProvider.notifier).setNode(updatedSelected);
          }
        }

        _speedBuffer.clear();
        _throttleTimer?.cancel();
        _saveNodes();
      }
    }
  }

  void stopTesting() {
    _isTesting = false;
  }

  void sortByLatency() {
    if (!mounted) return;
    final List<NodeModel> sorted = List.from(state);
    sorted.sort((a, b) {
      final la = a.latency ?? 9999;
      final lb = b.latency ?? 9999;
      // Timeout (-2) should be at the end, Testing (-3) before that
      final valA = la == -2
          ? 99999
          : (la == -3 ? 99998 : (la == -1 ? 99999 : la));
      final valB = lb == -2
          ? 99999
          : (lb == -3 ? 99998 : (lb == -1 ? 99999 : lb));
      return valA.compareTo(valB);
    });
    state = sorted;
    _saveNodes();
  }

  void sortByName() {
    if (!mounted) return;
    final List<NodeModel> sorted = List.from(state);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = sorted;
    _saveNodes();
  }

  void updateNodesFromSubscription(String subId, List<NodeModel> nodes) {
    if (!mounted) return;
    // 1. Remove old nodes from this subscription
    final otherNodes = state.where((n) => n.subscriptionId != subId).toList();

    // 2. Add new nodes with subscriptionId set
    final newNodes = nodes
        .map((n) => n.copyWith(subscriptionId: subId))
        .toList();

    state = [...otherNodes, ...newNodes];
    _saveNodes();
  }

  void removeNodesBySubscription(String subId) {
    if (!mounted) return;
    state = state.where((n) => n.subscriptionId != subId).toList();
    _saveNodes();
  }

  // --- 净化引擎算法开始 ---

  /// 清除所有测速超时的节点
  Future<int> clearTimeoutNodes() async {
    if (!mounted || _isProcessing) return 0;
    _isProcessing = true;

    final int originalCount = state.length;
    final List<NodeModel> backupState = List.from(state);

    try {
      // 过滤掉 latency 为 -2 (超时) 或 -1 (错误) 的节点
      final filtered = state
          .where((n) => n.latency != -2 && n.latency != -1)
          .toList();

      state = filtered;
      await _saveNodes();
      return originalCount - filtered.length;
    } catch (e) {
      debugPrint("Cleanup failed, restoring backup: $e");
      // [Fix] 异步守卫：回滚状态前检查 mounted
      if (mounted) {
        state = backupState;
      }
      return 0;
    } finally {
      _isProcessing = false;
    }
  }

  /// 手动强力去重：基于 server + port + auth 唯一指纹
  Future<int> manualDeduplicateNodes() async {
    if (!mounted || _isProcessing) return 0;
    _isProcessing = true;

    final int originalCount = state.length;
    final List<NodeModel> backupState = List.from(state);

    try {
      final seen = <String>{};
      final List<NodeModel> unique = [];

      for (final node in state) {
        final String fingerprint =
            "${node.address}:${node.port}:${node.uuid ?? node.password ?? node.username}";

        if (!seen.contains(fingerprint)) {
          seen.add(fingerprint);
          unique.add(node);
        }
      }

      state = unique;
      await _saveNodes();
      return originalCount - unique.length;
    } catch (e) {
      debugPrint("Deduplication failed, restoring backup: $e");
      // [Fix] 异步守卫：回滚状态前检查 mounted
      if (mounted) {
        state = backupState;
      }
      return 0;
    } finally {
      _isProcessing = false;
    }
  }

  // --- 净化引擎算法结束 ---
}

final nodeProvider = StateNotifierProvider<NodeNotifier, List<NodeModel>>((
  ref,
) {
  return NodeNotifier(ref);
});

class SelectedNodeNotifier extends StateNotifier<NodeModel?> {
  SelectedNodeNotifier() : super(null) {
    _loadSelection();
  }

  Future<void> _loadSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final nodeJson = prefs.getString('selected_node');
    if (nodeJson != null) {
      try {
        state = NodeModel.fromJson(jsonDecode(nodeJson));
      } catch (_) {}
    }
  }

  Future<void> setNode(NodeModel? node) async {
    state = node;
    final prefs = await SharedPreferences.getInstance();
    if (node == null) {
      await prefs.remove('selected_node');
    } else {
      await prefs.setString('selected_node', jsonEncode(node.toJson()));
    }
  }
}

final selectedNodeProvider =
    StateNotifierProvider<SelectedNodeNotifier, NodeModel?>((ref) {
      return SelectedNodeNotifier();
    });
