enum RuleSetFormat {
  yaml,
  json,
  text,
}

enum RuleSetBehavior {
  domain,
  ipcidr,
  classical,
}

class RuleSetModel {
  final String id;
  final String name;
  final String url;
  final RuleSetFormat format;
  final RuleSetBehavior behavior;
  final int? interval; // 更新间隔（小时）
  final DateTime? lastUpdated;
  final bool enabled;
  final int order;

  RuleSetModel({
    required this.id,
    required this.name,
    required this.url,
    required this.format,
    required this.behavior,
    this.interval,
    this.lastUpdated,
    this.enabled = true,
    this.order = 0,
  });

  RuleSetModel copyWith({
    String? id,
    String? name,
    String? url,
    RuleSetFormat? format,
    RuleSetBehavior? behavior,
    int? interval,
    DateTime? lastUpdated,
    bool? enabled,
    int? order,
  }) {
    return RuleSetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      format: format ?? this.format,
      behavior: behavior ?? this.behavior,
      interval: interval ?? this.interval,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'format': format.name,
        'behavior': behavior.name,
        'interval': interval,
        'lastUpdated': lastUpdated?.toIso8601String(),
        'enabled': enabled,
        'order': order,
      };

  factory RuleSetModel.fromJson(Map<String, dynamic> json) => RuleSetModel(
        id: json['id'],
        name: json['name'],
        url: json['url'],
        format: RuleSetFormat.values.firstWhere(
          (e) => e.name == json['format'],
          orElse: () => RuleSetFormat.yaml,
        ),
        behavior: RuleSetBehavior.values.firstWhere(
          (e) => e.name == json['behavior'],
          orElse: () => RuleSetBehavior.domain,
        ),
        interval: json['interval'],
        lastUpdated: json['lastUpdated'] != null
            ? DateTime.tryParse(json['lastUpdated'])
            : null,
        enabled: json['enabled'] ?? true,
        order: json['order'] ?? 0,
      );
}
