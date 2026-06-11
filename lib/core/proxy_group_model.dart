enum ProxyGroupType {
  select, // 手动选择
  urlTest, // URL 延迟测试自动选择
  fallback, // 故障转移
  loadBalance, // 负载均衡
  relay, // 代理链
}

class ProxyGroupModel {
  final String id;
  final String name;
  final ProxyGroupType type;
  final List<String> proxies; // 节点 ID 列表
  final String? url; // 用于 urlTest
  final int? interval; // 用于 urlTest（秒）
  final int? tolerance; // 用于 fallback（毫秒）
  final String? strategy; // 用于 loadBalance: round-robin, consistent-hashing
  final bool hidden;
  final int order;

  ProxyGroupModel({
    required this.id,
    required this.name,
    required this.type,
    required this.proxies,
    this.url,
    this.interval,
    this.tolerance,
    this.strategy,
    this.hidden = false,
    this.order = 0,
  });

  ProxyGroupModel copyWith({
    String? id,
    String? name,
    ProxyGroupType? type,
    List<String>? proxies,
    String? url,
    int? interval,
    int? tolerance,
    String? strategy,
    bool? hidden,
    int? order,
  }) {
    return ProxyGroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      proxies: proxies ?? this.proxies,
      url: url ?? this.url,
      interval: interval ?? this.interval,
      tolerance: tolerance ?? this.tolerance,
      strategy: strategy ?? this.strategy,
      hidden: hidden ?? this.hidden,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'proxies': proxies,
        'url': url,
        'interval': interval,
        'tolerance': tolerance,
        'strategy': strategy,
        'hidden': hidden,
        'order': order,
      };

  factory ProxyGroupModel.fromJson(Map<String, dynamic> json) => ProxyGroupModel(
        id: json['id'],
        name: json['name'],
        type: ProxyGroupType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => ProxyGroupType.select,
        ),
        proxies: List<String>.from(json['proxies'] ?? []),
        url: json['url'],
        interval: json['interval'],
        tolerance: json['tolerance'],
        strategy: json['strategy'],
        hidden: json['hidden'] ?? false,
        order: json['order'] ?? 0,
      );
}
