class NodeModel {
  final String id;
  final String name;
  final String protocol; // vmess, vless, trojan, shadowsocks, socks, http
  final String address;
  final int port;
  final String? uuid; // For VMess/VLESS
  final String? password; // For Trojan/SS/SOCKS5/HTTP
  final String? username; // For SOCKS5/HTTP
  final String? security; // none, tls, reality
  final String? network; // tcp, ws, h2, grpc, kcp, quic, httpupgrade
  final String? sni;
  final String? host; // For WS/H2/HTTP host header
  final String? path; // For WS/H2/gRPC/QUIC
  final String? type; // For KCP/QUIC header type
  final String? publicKey; // For Reality
  final String? fingerPrint; // For Reality (chrome, firefox, edge, etc.)
  final String? shortId; // For Reality
  final String? spiderX; // For Reality
  final String? flow; // For VLESS XTLS (xtls-rprx-vision)
  final String? method; // For SS (aes-256-gcm, 2022-blake3-aes-256-gcm, etc.)
  final String? serviceName; // For gRPC
  final String? mode; // For gRPC (gun, multi, tun)
  final String? encryption; // For VLESS (usually 'none')
  final String? wgSecretKey; // For WireGuard
  final List<String>? wgLocalAddress; // For WireGuard (e.g. ["10.0.0.2/32"])
  final String? wgPeerPublicKey; // For WireGuard
  final String? wgPreSharedKey; // For WireGuard
  final int? wgMtu; // For WireGuard
  final int? wgKeepAlive; // For WireGuard
  final List<String>? alpn; // ALPN list
  final bool? muxEnabled;
  final int? muxConcurrency;
  final Map<String, dynamic>? rawData; // Original import metadata for 100% fidelity
  final bool isFavorite;
  final int? latency;
  final String? subscriptionId;

  NodeModel({
    required this.id,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    this.uuid,
    this.password,
    this.username,
    this.security = 'none',
    this.network = 'tcp',
    this.sni,
    this.host,
    this.path,
    this.type,
    this.publicKey,
    this.fingerPrint,
    this.shortId,
    this.spiderX,
    this.flow,
    this.method,
    this.serviceName,
    this.mode,
    this.encryption,
    this.wgSecretKey,
    this.wgLocalAddress,
    this.wgPeerPublicKey,
    this.wgPreSharedKey,
    this.wgMtu,
    this.wgKeepAlive,
    this.alpn,
    this.muxEnabled,
    this.muxConcurrency,
    this.rawData,
    this.isFavorite = false,
    this.latency,
    this.subscriptionId,
  });

  NodeModel copyWith({
    String? name,
    String? protocol,
    String? address,
    int? port,
    String? uuid,
    String? password,
    String? username,
    String? security,
    String? network,
    String? sni,
    String? host,
    String? path,
    String? type,
    String? publicKey,
    String? fingerPrint,
    String? shortId,
    String? spiderX,
    String? flow,
    String? method,
    String? serviceName,
    String? mode,
    String? encryption,
    String? wgSecretKey,
    List<String>? wgLocalAddress,
    String? wgPeerPublicKey,
    String? wgPreSharedKey,
    int? wgMtu,
    int? wgKeepAlive,
    List<String>? alpn,
    bool? muxEnabled,
    int? muxConcurrency,
    Map<String, dynamic>? rawData,
    bool? isFavorite,
    int? latency,
    String? subscriptionId,
  }) {
    return NodeModel(
      id: id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      address: address ?? this.address,
      port: port ?? this.port,
      uuid: uuid ?? this.uuid,
      password: password ?? this.password,
      username: username ?? this.username,
      security: security ?? this.security,
      network: network ?? this.network,
      sni: sni ?? this.sni,
      host: host ?? this.host,
      path: path ?? this.path,
      type: type ?? this.type,
      publicKey: publicKey ?? this.publicKey,
      fingerPrint: fingerPrint ?? this.fingerPrint,
      shortId: shortId ?? this.shortId,
      spiderX: spiderX ?? this.spiderX,
      flow: flow ?? this.flow,
      method: method ?? this.method,
      serviceName: serviceName ?? this.serviceName,
      mode: mode ?? this.mode,
      encryption: encryption ?? this.encryption,
      wgSecretKey: wgSecretKey ?? this.wgSecretKey,
      wgLocalAddress: wgLocalAddress ?? this.wgLocalAddress,
      wgPeerPublicKey: wgPeerPublicKey ?? this.wgPeerPublicKey,
      wgPreSharedKey: wgPreSharedKey ?? this.wgPreSharedKey,
      wgMtu: wgMtu ?? this.wgMtu,
      wgKeepAlive: wgKeepAlive ?? this.wgKeepAlive,
      alpn: alpn ?? this.alpn,
      muxEnabled: muxEnabled ?? this.muxEnabled,
      muxConcurrency: muxConcurrency ?? this.muxConcurrency,
      rawData: rawData ?? this.rawData,
      isFavorite: isFavorite ?? this.isFavorite,
      latency: latency ?? this.latency,
      subscriptionId: subscriptionId ?? this.subscriptionId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol,
        'address': address,
        'port': port,
        'uuid': uuid,
        'password': password,
        'username': username,
        'security': security,
        'network': network,
        'sni': sni,
        'host': host,
        'path': path,
        'type': type,
        'publicKey': publicKey,
        'fingerPrint': fingerPrint,
        'shortId': shortId,
        'spiderX': spiderX,
        'flow': flow,
        'method': method,
        'serviceName': serviceName,
        'mode': mode,
        'encryption': encryption,
        'wgSecretKey': wgSecretKey,
        'wgLocalAddress': wgLocalAddress,
        'wgPeerPublicKey': wgPeerPublicKey,
        'wgPreSharedKey': wgPreSharedKey,
        'wgMtu': wgMtu,
        'wgKeepAlive': wgKeepAlive,
        'alpn': alpn,
        'muxEnabled': muxEnabled,
        'muxConcurrency': muxConcurrency,
        'rawData': rawData,
        'isFavorite': isFavorite,
        'latency': latency,
        'subscriptionId': subscriptionId,
      };

  factory NodeModel.fromJson(Map<String, dynamic> json) => NodeModel(
        id: json['id'],
        name: json['name'],
        protocol: json['protocol'],
        address: json['address'],
        port: json['port'],
        uuid: json['uuid'],
        password: json['password'],
        username: json['username'],
        security: json['security'] ?? 'none',
        network: json['network'] ?? 'tcp',
        sni: json['sni'],
        host: json['host'],
        path: json['path'],
        type: json['type'],
        publicKey: json['publicKey'],
        fingerPrint: json['fingerPrint'],
        shortId: json['shortId'],
        spiderX: json['spiderX'],
        flow: json['flow'],
        method: json['method'],
        serviceName: json['serviceName'],
        mode: json['mode'],
        encryption: json['encryption'],
        wgSecretKey: json['wgSecretKey'],
        wgLocalAddress: json['wgLocalAddress'] != null ? List<String>.from(json['wgLocalAddress']) : null,
        wgPeerPublicKey: json['wgPeerPublicKey'],
        wgPreSharedKey: json['wgPreSharedKey'],
        wgMtu: json['wgMtu'],
        wgKeepAlive: json['wgKeepAlive'],
        alpn: json['alpn'] != null ? List<String>.from(json['alpn']) : null,
        muxEnabled: json['muxEnabled'],
        muxConcurrency: json['muxConcurrency'],
        rawData: json['rawData'] != null ? Map<String, dynamic>.from(json['rawData']) : null,
        isFavorite: json['isFavorite'] ?? false,
        latency: json['latency'],
        subscriptionId: json['subscriptionId'],
      );
}
