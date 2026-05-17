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
  NodeNotifier(this._ref) : super([]) {
    _loadNodes();
  }

  Future<void> _loadNodes() async {
    final prefs = await SharedPreferences.getInstance();
    final nodesJson = prefs.getStringList('nodes') ?? [];
    state = nodesJson.map((e) => NodeModel.fromJson(jsonDecode(e))).toList();
  }

  Future<void> _saveNodes() async {
    final prefs = await SharedPreferences.getInstance();
    final nodesJson = state.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('nodes', nodesJson);
  }

  void addNode(NodeModel node) {
    state = [...state, node];
    _saveNodes();
    // Auto-test latency for the newly added single node
    testLatency(node.id, useTcpPing: false);
  }

  void addNodes(List<NodeModel> nodes) {
    state = [...state, ...nodes];
    _saveNodes();
    // Auto-test latency for newly imported nodes
    if (nodes.isNotEmpty) {
      testAllLatencies(useTcpPing: false);
    }
  }

  void removeNode(String id) {
    state = state.where((e) => e.id != id).toList();
    _saveNodes();
  }

  void updateNode(NodeModel node) {
    state = [
      for (final n in state)
        if (n.id == node.id) node else n
    ];
    _saveNodes();
  }

  void toggleFavorite(String id) {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isFavorite: !n.isFavorite) else n
    ];
    _saveNodes();
  }

  Future<void> testLatency(String id, {bool useTcpPing = false, bool useGooglePing = false}) async {
    final nodeIndex = state.indexWhere((e) => e.id == id);
    if (nodeIndex == -1) return;

    // 1. Set status to testing (-1)
    final node = state[nodeIndex];
    state = [
      ...state.sublist(0, nodeIndex),
      node.copyWith(latency: -1),
      ...state.sublist(nodeIndex + 1),
    ];

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
        // Real Delay: Follow v2rayNG logic
        final isVpnRunning = _ref.read(vpnProvider).isRunning;
        final selectedNode = _ref.read(selectedNodeProvider);
        
        if (isVpnRunning && selectedNode?.id == id) {
          // If testing CONNECTED node, test via active VPN tunnel (port 10808)
          latency = await ProxyChannel.googlePing().timeout(
            const Duration(seconds: 15),
            onTimeout: () => -2,
          );
        } else if (!isVpnRunning) {
          // If VPN is NOT running, start temporary core for Real Delay
          final assetDir = (await getApplicationSupportDirectory()).path;
          final testConfigJson = ConfigGenerator.generateConfig(
            node: node, 
            rules: [], 
            isTest: true,
          );
          final payload = "__XRAY_ASSET_DIR__=$assetDir\n$testConfigJson";
          
          latency = await ProxyChannel.measureSingleDelay(payload).timeout(
            const Duration(seconds: 15),
            onTimeout: () => -2,
          );
        } else {
          // If VPN is running and testing OTHER nodes, v2rayNG typically doesn't 
          // allow real delay without stopping VPN. To align, we return timeout.
          latency = -2;
        }
      }
    } catch (e) {
      debugPrint("Latency test error for ${node.name}: $e");
      latency = -2;
    }

    // 2. Update with result
    if (mounted) {
      final currentIndex = state.indexWhere((e) => e.id == id);
      if (currentIndex != -1) {
        state = [
          ...state.sublist(0, currentIndex),
          state[currentIndex].copyWith(latency: latency),
          ...state.sublist(currentIndex + 1),
        ];
        _saveNodes();
      }
    }
  }

  Future<void> testAllLatencies({bool useTcpPing = false}) async {
    if (state.isEmpty) return;

    // 1. Mark all as testing (-1)
    state = [
      for (final n in state) n.copyWith(latency: -1)
    ];

    if (useTcpPing) {
      final nodesToTest = List<NodeModel>.from(state);
      final List<Future<int>> tasks = [];
      for (final node in nodesToTest) {
        tasks.add(ProxyChannel.tcpPing(node.address, node.port));
      }
      
      final results = await Future.wait(tasks);
      
      if (mounted) {
        state = [
          for (int i = 0; i < state.length; i++)
            state[i].copyWith(latency: results[i])
        ];
        _saveNodes();
      }
    } else {
      // Real Delay: Optimized batch testing similar to v2rayNG
      final nodesToTest = List<NodeModel>.from(state);

      // If VPN is running, we cannot use Real Delay (temporary core) as it would stop the VPN
      final isRunning = _ref.read(vpnProvider).isRunning;
      if (isRunning) {
        // Fallback to TCP Ping for all nodes to avoid interrupting VPN
        final List<Future<int>> tasks = [];
        for (final node in nodesToTest) {
          tasks.add(ProxyChannel.tcpPing(node.address, node.port));
        }
        final results = await Future.wait(tasks);
        if (mounted) {
          state = [
            for (int i = 0; i < state.length; i++)
              state[i].copyWith(latency: results[i])
          ];
          _saveNodes();
        }
        return;
      }

      try {
        // 2. Generate a single Xray config with ALL nodes as outbounds
        // Each node will have its own socks inbound port (10811 + i)
        final batchConfig = ConfigGenerator.generateBatchTestConfig(nodesToTest);
        final assetDir = (await getApplicationSupportDirectory()).path;
        final payload = "__XRAY_ASSET_DIR__=$assetDir\n$batchConfig";
        
        // 3. Call native batch test (Parallel HTTP requests via different socks ports)
        final latencies = await ProxyChannel.measureBatchDelay(
          payload, 
          nodesToTest.length
        );
        
        // 4. Update results using ID mapping to avoid index misalignment
        if (mounted) {
          final Map<String, int> resultMap = {};
          for (int i = 0; i < nodesToTest.length; i++) {
            resultMap[nodesToTest[i].id] = latencies[i];
          }

          state = [
            for (final n in state)
              if (resultMap.containsKey(n.id)) n.copyWith(latency: resultMap[n.id]) else n
          ];
          _saveNodes();
        }
      } catch (e) {
        debugPrint("Batch latency test error: $e");
        // Reset nodes that were testing to error state
        if (mounted) {
          state = [
            for (final n in state)
              if (n.latency == -1) n.copyWith(latency: -2) else n
          ];
        }
      }
    }
  }

  void sortByLatency() {
    final List<NodeModel> sorted = List.from(state);
    sorted.sort((a, b) {
      final la = a.latency ?? 9999;
      final lb = b.latency ?? 9999;
      // Timeout (-2) should be at the end
      final valA = la == -2 ? 99999 : (la == -1 ? 99998 : la);
      final valB = lb == -2 ? 99999 : (lb == -1 ? 99998 : lb);
      return valA.compareTo(valB);
    });
    state = sorted;
    _saveNodes();
  }

  void sortByName() {
    final List<NodeModel> sorted = List.from(state);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = sorted;
    _saveNodes();
  }

  void deduplicate() {
    final seen = <String>{};
    final List<NodeModel> unique = [];
    for (final node in state) {
      final key = "${node.protocol}:${node.address}:${node.port}:${node.uuid ?? node.password ?? node.username}";
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(node);
      }
    }
    state = unique;
    _saveNodes();
  }

  void updateNodesFromSubscription(String subId, List<NodeModel> nodes) {
    // 1. Remove old nodes from this subscription
    final otherNodes = state.where((n) => n.subscriptionId != subId).toList();
    
    // 2. Add new nodes with subscriptionId set
    final newNodes = nodes.map((n) => n.copyWith(subscriptionId: subId)).toList();
    
    state = [...otherNodes, ...newNodes];
    _saveNodes();

    // Auto-test latency for newly updated subscription nodes
    if (newNodes.isNotEmpty) {
      testAllLatencies(useTcpPing: false);
    }
  }

  void removeNodesBySubscription(String subId) {
    state = state.where((n) => n.subscriptionId != subId).toList();
    _saveNodes();
  }
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
