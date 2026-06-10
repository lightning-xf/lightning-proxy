import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightning/core/rule_model.dart';

class RoutingNotifier extends StateNotifier<List<RuleModel>> {
  RoutingNotifier() : super([]) {
    _loadRules();
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    // Use a version key to force reset to mature rules if needed
    const rulesVersion = 'v5';
    final currentVersion = prefs.getString('routing_rules_version');

    final rulesJson = prefs.getStringList('routing_rules');
    if (rulesJson == null || currentVersion != rulesVersion) {
      _applyMatureRules();
      await prefs.setString('routing_rules_version', rulesVersion);
    } else {
      state = rulesJson.map((e) => RuleModel.fromJson(jsonDecode(e))).toList();
    }
  }

  void resetToDefault() {
    _applyMatureRules();
  }

  void _applyMatureRules() {
    // Mature rules - Reference: Loyalsoldier/v2ray-rules-dat & V2RayNG
    state = [
      // 1. 阻断广告与追踪 - 提升加载速度
      RuleModel(
        id: 'block_ads',
        type: 'field',
        domain: ['geosite:category-ads-all'],
        outboundTag: 'block',
      ),
      // 2. 阻断 QUIC (UDP 443) - 解决 Chrome 访问慢/无法访问的问题
      RuleModel(
        id: 'block_quic',
        type: 'field',
        port: ['443'],
        network: ['udp'],
        outboundTag: 'block',
      ),
      // 3. 局域网及私有地址直连
      RuleModel(
        id: 'direct_private',
        type: 'field',
        ip: ['geoip:private'],
        domain: ['geosite:private'],
        outboundTag: 'direct',
      ),
      // 4. 显式代理核心海外服务 - 确保 Google/GitHub/Telegram 100% 走隧道
      RuleModel(
        id: 'proxy_core_services',
        type: 'field',
        domain: [
          'geosite:google',
          'geosite:github',
          'geosite:telegram',
          'geosite:twitter',
          'geosite:facebook',
          'geosite:netflix',
          'geosite:youtube',
        ],
        outboundTag: 'proxy',
      ),
      // 5. 绕过中国 (成熟方案的核心)
      // 直连所有中国大陆域名与 IP
      RuleModel(
        id: 'direct_cn',
        type: 'field',
        domain: ['geosite:cn'],
        ip: ['geoip:cn'],
        outboundTag: 'direct',
      ),
      // 代理所有非中国大陆域名 (作为 DNS 分流的提示)
      RuleModel(
        id: 'proxy_non_cn_hint',
        type: 'field',
        domain: ['geosite:geolocation-!cn'],
        outboundTag: 'proxy',
      ),
      // 6. 常用国内 DNS 直连 (防止 DNS 回路)
      RuleModel(
        id: 'direct_dns',
        type: 'field',
        ip: [
          '223.5.5.5',
          '223.6.6.6',
          '119.29.29.29',
          '180.76.76.76',
          '114.114.114.114',
        ],
        outboundTag: 'direct',
      ),
    ];
    _saveRules();
  }

  Future<void> _saveRules() async {
    final prefs = await SharedPreferences.getInstance();
    final rulesJson = state.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('routing_rules', rulesJson);
  }

  void addRule(RuleModel rule) {
    state = [...state, rule];
    _saveRules();
  }

  void removeRule(String id) {
    state = state.where((e) => e.id != id).toList();
    _saveRules();
  }

  void toggleRule(String id) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(enabled: !r.enabled) else r,
    ];
    _saveRules();
  }
}

final routingProvider = StateNotifierProvider<RoutingNotifier, List<RuleModel>>(
  (ref) {
    return RoutingNotifier();
  },
);
