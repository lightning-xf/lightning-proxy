import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lightning/core/link_parser.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/subscription_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, List<SubscriptionModel>>((ref) {
  return SubscriptionNotifier(ref);
});

class SubscriptionNotifier extends StateNotifier<List<SubscriptionModel>> {
  final Ref _ref;
  Timer? _autoUpdateTimer;
  final Set<String> _updatingIds = {};

  SubscriptionNotifier(this._ref) : super([]) {
    _load();
    _startAutoUpdateTimer();
  }

  void _startAutoUpdateTimer() {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _checkAutoUpdates();
    });
  }

  void _checkAutoUpdates() {
    final now = DateTime.now();
    for (final sub in state) {
      if (sub.autoUpdate) {
        if (sub.lastUpdate == null ||
            now.difference(sub.lastUpdate!).inHours >= sub.updateInterval) {
          updateSubscription(sub.id);
        }
      }
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('subscriptions');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      state = jsonList.map((e) => SubscriptionModel.fromJson(e)).toList();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(state.map((e) => e.toJson()).toList());
    await prefs.setString('subscriptions', data);
  }

  void addSubscription(SubscriptionModel sub) {
    state = [...state, sub];
    _save();
    updateSubscription(sub.id);
  }

  void updateSubscription(String id) async {
    if (_updatingIds.contains(id)) return;
    
    final index = state.indexWhere((e) => e.id == id);
    if (index == -1) return;

    _updatingIds.add(id);
    final sub = state[index];
    state[index] = sub.copyWith(error: null, isUpdating: true);
    state = [...state];

    try {
      String content = '';
      int? total;
      int? used;
      DateTime? expire;

      if (sub.isFile) {
        final file = File(sub.url);
        if (await file.exists()) {
          content = await file.readAsString();
        } else {
          throw Exception('文件不存在: ${sub.url}');
        }
      } else {
        // High Tolerance Subscription Engine:
        // 1. User-Agent Spoofing (v2rayNG/1.8.5)
        // 2. Accept Header widening
        final response = await http.get(
          Uri.parse(sub.url),
          headers: {
            'User-Agent': 'v2rayNG/1.8.5',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.8,en-US;q=0.5,en;q=0.3',
          },
        ).timeout(
          const Duration(seconds: 15),
        );

        if (response.statusCode == 200) {
          // Use bodyBytes with utf8.decode to handle Chinese characters correctly
          content = utf8.decode(response.bodyBytes, allowMalformed: true);
          // Parse user data info from headers if available
          final info = response.headers['subscription-userinfo'];
          if (info != null) {
            final parts = info.split(';');
            for (var part in parts) {
              if (part.contains('total=')) {
                total = int.tryParse(part.split('=')[1]);
              } else if (part.contains('upload=')) {
                used = (used ?? 0) + (int.tryParse(part.split('=')[1]) ?? 0);
              } else if (part.contains('download=')) {
                used = (used ?? 0) + (int.tryParse(part.split('=')[1]) ?? 0);
              } else if (part.contains('expire=')) {
                final seconds = int.tryParse(part.split('=')[1]);
                if (seconds != null) {
                  expire = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
                }
              }
            }
          }
        } else {
          throw Exception('HTTP Error: ${response.statusCode}');
        }
      }

      final nodes = LinkParser.parse(content);
      
      if (nodes.isEmpty) {
        // If no nodes found, it might be an expired subscription or parsing error.
        // We keep the old nodes but mark it with a warning/error to avoid losing everything.
        throw Exception('未从订阅中解析到任何节点 (可能是订阅已到期或格式不支持)');
      }

      _ref.read(nodeProvider.notifier).updateNodesFromSubscription(id, nodes);

      state[index] = sub.copyWith(
        lastUpdate: DateTime.now(),
        totalData: total,
        usedData: used,
        expireDate: expire,
        error: null,
        isUpdating: false,
      );
    } catch (e) {
      state[index] = sub.copyWith(error: e.toString(), isUpdating: false);
    } finally {
      _updatingIds.remove(id);
    }

    state = [...state];
    _save();
  }

  void updateSubscriptionModel(SubscriptionModel sub) {
    final index = state.indexWhere((e) => e.id == sub.id);
    if (index != -1) {
      state[index] = sub;
      state = [...state];
      _save();
    }
  }

  void removeSubscription(String id) {
    state = state.where((e) => e.id != id).toList();
    _save();
    _ref.read(nodeProvider.notifier).removeNodesBySubscription(id);
  }

  void toggleAutoUpdate(String id, bool value) {
    final index = state.indexWhere((e) => e.id == id);
    if (index != -1) {
      state[index] = state[index].copyWith(autoUpdate: value);
      state = [...state];
      _save();
    }
  }

  void setUpdateInterval(String id, int hours) {
    final index = state.indexWhere((e) => e.id == id);
    if (index != -1) {
      state[index] = state[index].copyWith(updateInterval: hours);
      state = [...state];
      _save();
    }
  }

  @override
  void dispose() {
    _autoUpdateTimer?.cancel();
    super.dispose();
  }
}
