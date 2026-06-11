import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightning/core/proxy_group_model.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/node_model.dart';

class ProxyGroupNotifier extends StateNotifier<List<ProxyGroupModel>> {
  final Ref _ref;

  ProxyGroupNotifier(this._ref) : super([]) {
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final groupsJson = prefs.getStringList('proxy_groups') ?? [];
    state = groupsJson
        .map((e) => ProxyGroupModel.fromJson(jsonDecode(e)))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  Future<void> _saveGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final groupsJson = state.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('proxy_groups', groupsJson);
  }

  void addGroup(ProxyGroupModel group) {
    state = [...state, group]..sort((a, b) => a.order.compareTo(b.order));
    _saveGroups();
  }

  void updateGroup(ProxyGroupModel group) {
    state = [
      for (final g in state)
        if (g.id == group.id) group else g,
    ]..sort((a, b) => a.order.compareTo(b.order));
    _saveGroups();
  }

  void removeGroup(String id) {
    state = state.where((e) => e.id != id).toList();
    _saveGroups();
  }

  void reorderGroups(int oldIndex, int newIndex) {
    final groups = List<ProxyGroupModel>.from(state);
    final item = groups.removeAt(oldIndex);
    groups.insert(newIndex, item);
    // 更新 order 字段
    state = groups.asMap().entries.map((e) {
      return e.value.copyWith(order: e.key);
    }).toList();
    _saveGroups();
  }

  List<NodeModel> getAvailableProxiesForGroup(String groupId) {
    final nodes = _ref.read(nodeProvider);
    final group = state.firstWhere((g) => g.id == groupId);
    final usedIds = group.proxies.toSet();
    return nodes.where((n) => !usedIds.contains(n.id)).toList();
  }

  List<NodeModel> getGroupProxies(String groupId) {
    final nodes = _ref.read(nodeProvider);
    final group = state.firstWhere((g) => g.id == groupId);
    final nodeMap = {for (final n in nodes) n.id: n};
    return group.proxies.where((id) => nodeMap.containsKey(id)).map((id) => nodeMap[id]!).toList();
  }
}

final proxyGroupProvider =
    StateNotifierProvider<ProxyGroupNotifier, List<ProxyGroupModel>>((ref) {
  return ProxyGroupNotifier(ref);
});

// 选中的代理组 Provider
class SelectedGroupNotifier extends StateNotifier<ProxyGroupModel?> {
  final Ref ref;

  SelectedGroupNotifier(this.ref) : super(null) {
    _loadSelectedGroup();
  }

  Future<void> _loadSelectedGroup() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString('selected_group');
    if (selectedId != null) {
      final groups = ref.read(proxyGroupProvider);
      try {
        state = groups.firstWhere((g) => g.id == selectedId);
      } catch (e) {
        // Group not found
        state = null;
      }
    }
  }

  Future<void> setSelectedGroup(ProxyGroupModel? group) async {
    final prefs = await SharedPreferences.getInstance();
    if (group == null) {
      await prefs.remove('selected_group');
      state = null;
    } else {
      await prefs.setString('selected_group', group.id);
      state = group;
    }
  }
}

final selectedGroupProvider = StateNotifierProvider<SelectedGroupNotifier, ProxyGroupModel?>((ref) {
  return SelectedGroupNotifier(ref);
});
