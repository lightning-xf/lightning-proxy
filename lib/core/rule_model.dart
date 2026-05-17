class RuleModel {
  final String id;
  final String type; // field, iis
  final List<String>? domain;
  final List<String>? ip;
  final List<String>? port;
  final List<String>? network;
  final String outboundTag; // direct, proxy, block
  final bool enabled;

  RuleModel({
    required this.id,
    required this.type,
    this.domain,
    this.ip,
    this.port,
    this.network,
    required this.outboundTag,
    this.enabled = true,
  });

  RuleModel copyWith({
    String? id,
    String? type,
    List<String>? domain,
    List<String>? ip,
    List<String>? port,
    List<String>? network,
    String? outboundTag,
    bool? enabled,
  }) {
    return RuleModel(
      id: id ?? this.id,
      type: type ?? this.type,
      domain: domain ?? this.domain,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      network: network ?? this.network,
      outboundTag: outboundTag ?? this.outboundTag,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'domain': domain,
    'ip': ip,
    'port': port,
    'network': network,
    'outboundTag': outboundTag,
    'enabled': enabled,
  };

  factory RuleModel.fromJson(Map<String, dynamic> json) => RuleModel(
    id: json['id'],
    type: json['type'],
    domain: json['domain'] != null ? List<String>.from(json['domain']) : null,
    ip: json['ip'] != null ? List<String>.from(json['ip']) : null,
    port: json['port'] != null ? List<String>.from(json['port']) : null,
    network: json['network'] != null
        ? List<String>.from(json['network'])
        : null,
    outboundTag: json['outboundTag'],
    enabled: json['enabled'] ?? true,
  );
}
