import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:lightning/core/rule_set_model.dart';

class RuleSetNotifier extends StateNotifier<List<RuleSetModel>> {
  final Ref _ref;

  RuleSetNotifier(this._ref) : super([]) {
    _loadRuleSets();
  }

  Future<void> _loadRuleSets() async {
    final prefs = await SharedPreferences.getInstance();
    final ruleSetsJson = prefs.getStringList('rule_sets') ?? [];
    state = ruleSetsJson
        .map((e) => RuleSetModel.fromJson(jsonDecode(e)))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  Future<void> _saveRuleSets() async {
    final prefs = await SharedPreferences.getInstance();
    final ruleSetsJson = state.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('rule_sets', ruleSetsJson);
  }

  void addRuleSet(RuleSetModel ruleSet) {
    state = [...state, ruleSet]..sort((a, b) => a.order.compareTo(b.order));
    _saveRuleSets();
  }

  void updateRuleSet(RuleSetModel ruleSet) {
    state = [
      for (final r in state)
        if (r.id == ruleSet.id) ruleSet else r,
    ]..sort((a, b) => a.order.compareTo(b.order));
    _saveRuleSets();
  }

  void removeRuleSet(String id) {
    state = state.where((e) => e.id != id).toList();
    _saveRuleSets();
  }

  void reorderRuleSets(int oldIndex, int newIndex) {
    final ruleSets = List<RuleSetModel>.from(state);
    final item = ruleSets.removeAt(oldIndex);
    ruleSets.insert(newIndex, item);
    state = ruleSets.asMap().entries.map((e) {
      return e.value.copyWith(order: e.key);
    }).toList();
    _saveRuleSets();
  }

  Future<void> refreshRuleSet(String id) async {
    final index = state.indexWhere((e) => e.id == id);
    if (index == -1) return;

    final ruleSet = state[index];
    try {
      final response = await http.get(Uri.parse(ruleSet.url));
      if (response.statusCode == 200) {
        // 成功获取，更新 lastUpdated
        final updated = ruleSet.copyWith(lastUpdated: DateTime.now());
        state = [
          for (int i = 0; i < state.length; i++)
            if (i == index) updated else state[i],
        ];
        await _saveRuleSets();
      }
    } catch (e) {
      debugPrint('Failed to update rule set ${ruleSet.name}: $e');
    }
  }

  Future<void> updateAllRuleSets() async {
    for (final ruleSet in state.where((r) => r.enabled)) {
      await refreshRuleSet(ruleSet.id);
    }
  }

  void toggleRuleSet(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(enabled: !r.enabled) else r,
    ];
    _saveRuleSets();
  }
}

final ruleSetProvider =
    StateNotifierProvider<RuleSetNotifier, List<RuleSetModel>>((ref) {
  return RuleSetNotifier(ref);
});
