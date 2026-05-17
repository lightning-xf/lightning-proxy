import 'dart:convert';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/core/rule_model.dart';
import 'package:lightning/core/vpn_provider.dart';

class ConfigGenerator {
  static String generateConfig({
    required NodeModel node,
    required List<RuleModel> rules,
    VpnMode mode = VpnMode.rule,
    List<String>? proxyApps,
    bool bypassLocal = true,
    bool muxEnabled = false,
    String tcpCongestion = 'bbr',
    bool allowLan = false,
    bool isTest = false,
    String logLevel = 'info',
    int socksPort = 10808,
    int httpPort = 10809,
    int testPort = 10810,
    String dns = '8.8.8.8, 1.1.1.1',
    bool fakeDns = true,
    String remoteDns = '1.1.1.1, 1.0.0.1',
    String domesticDns = '223.5.5.5, 223.6.6.6',
    bool enableIPv6 = true,
    String dnsHosts = '',
  }) {
    final listenAddr = allowLan ? "0.0.0.0" : "127.0.0.1";
    final dnsServers = dns
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final remoteDnsServers = remoteDns
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final domesticDnsServers = domesticDns
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Get proxy and direct domains from rules
    final proxyDomains = <String>[];
    final directDomains = <String>[];
    for (final rule in rules.where((r) => r.enabled)) {
      if (rule.outboundTag == 'proxy' && rule.domain != null) {
        proxyDomains.addAll(rule.domain!);
      } else if (rule.outboundTag == 'direct' && rule.domain != null) {
        directDomains.addAll(rule.domain!);
      }
    }

    final Map<String, dynamic> config = {
      "log": {"loglevel": isTest ? "none" : logLevel},
      "api": {
        "tag": "api",
        "services": ["StatsService"],
      },
      "stats": {},
      "policy": {
        "levels": {
          "0": {
            "statsUserUplink": true,
            "statsUserDownlink": true,
            "handshake": 4,
            "connIdle": 300,
            "uplinkOnly": 0,
            "downlinkOnly": 0,
            "bufferSize": 64,
          },
        },
        "system": {
          "statsInboundUplink": true,
          "statsInboundDownlink": true,
          "statsOutboundUplink": true,
          "statsOutboundDownlink": true,
        },
      },
      if (fakeDns && !isTest)
        "fakedns": [
          {"ipPool": "198.18.0.0/15", "poolSize": 65535},
        ],
      "dns": {
        "hosts": _buildDnsHosts(dnsHosts),
        "servers": _buildDnsServers(
          remoteDnsServers,
          domesticDnsServers,
          proxyDomains,
          directDomains,
          fakeDns,
          mode,
          enableIPv6,
          isTest,
          dnsServers,
        ),
        "queryStrategy": "UseIP",
        "tag": "dns-out",
        "enableParallelQuery":
            (remoteDnsServers.length + domesticDnsServers.length) > 2,
      },
      "inbounds": [
        {
          "listen": "127.0.0.1",
          "port": 10085,
          "protocol": "dokodemo-door",
          "settings": {"address": "127.0.0.1"},
          "tag": "api",
        },
        if (!isTest)
          {
            "tag": "tun-in",
            "protocol": "tun",
            "settings": {
              "name": "lightning-tun",
              "mtu": 1500,
              "userLevel": 0,
              "stack": "gvisor",
              "network": "tcp,udp",
              "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false,
              },
              if (fakeDns) "fakeDns": true,
            },
          },
        if (!isTest) ...[
          {
            "tag": "socks-in",
            "protocol": "socks",
            "listen": listenAddr,
            "port": socksPort,
            "settings": {"auth": "noauth", "udp": true, "userLevel": 0},
            "sniffing": {
              "enabled": true,
              "destOverride": ["http", "tls", "quic"],
              "metadataOnly": false,
            },
          },
          {
            "tag": "http-in",
            "protocol": "http",
            "listen": listenAddr,
            "port": httpPort,
            "settings": {"userLevel": 0},
            "sniffing": {
              "enabled": true,
              "destOverride": ["http", "tls", "quic"],
              "metadataOnly": false,
            },
          },
        ] else
          {
            "tag": "socks-in",
            "protocol": "socks",
            "listen": "127.0.0.1",
            "port": testPort,
            "settings": {"auth": "noauth", "udp": true, "userLevel": 0},
          },
      ],
      "outbounds": [
        {"protocol": "freedom", "settings": {}, "tag": "api"},
        {..._generateOutbound(node, muxEnabled, tcpCongestion), "tag": "proxy"},
        {
          "tag": "direct",
          "protocol": "freedom",
          "settings": {"domainStrategy": "UseIP"},
          "streamSettings": {
            "sockopt": {"tcpCongestion": tcpCongestion, "mark": 255},
          },
        },
        {
          "tag": "block",
          "protocol": "blackhole",
          "settings": {
            "response": {"type": "none"},
          },
        },
        {"tag": "dns-out", "protocol": "dns", "settings": {}},
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": _buildRoutingRules(rules, bypassLocal, mode, isTest),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  static Map<String, dynamic> _buildDnsHosts(String dnsHosts) {
    final hosts = <String, dynamic>{
      "domain:googleapis.cn": "googleapis.com",
      // Private DNS fixes
      "domain:dns.alidns.com": ["223.5.5.5", "223.6.6.6"],
      "domain:dns.pub": ["119.29.29.29", "180.76.76.76"],
      "domain:cloudflare-dns.com": ["1.1.1.1", "1.0.0.1"],
      "domain:dns.google": ["8.8.8.8", "8.8.4.4"],
    };

    if (dnsHosts.isNotEmpty) {
      try {
        final userHosts = dnsHosts.split(',');
        for (final host in userHosts) {
          final parts = host.split(':');
          if (parts.length >= 2) {
            final domain = parts[0].trim();
            final ip = parts.sublist(1).join(':').trim();
            hosts[domain] = ip;
          }
        }
      } catch (_) {}
    }

    return hosts;
  }

  static List<dynamic> _buildDnsServers(
    List<String> remoteDnsServers,
    List<String> domesticDnsServers,
    List<String> proxyDomains,
    List<String> directDomains,
    bool fakeDns,
    VpnMode mode,
    bool enableIPv6,
    bool isTest,
    List<String> dnsServers,
  ) {
    final servers = <dynamic>[];

    if (!isTest) {
      if (fakeDns && mode != VpnMode.direct) {
        // FakeDNS should apply to all non-direct domains to avoid leaking
        servers.add({
          "address": "fakedns",
          "domains": ["geosite:geolocation-!cn", ...proxyDomains]
        });
      }

      // Remote DNS: Priority for proxy/non-cn domains
      for (final server in remoteDnsServers) {
        servers.add({
          "address": server,
          "domains": ["geosite:geolocation-!cn", ...proxyDomains],
          "tag": "remote-dns",
        });
      }

      // Domestic DNS: Priority for direct/cn domains
      final hasCnDomain = directDomains.contains('geosite:cn');
      for (int i = 0; i < domesticDnsServers.length; i++) {
        final server = domesticDnsServers[i];
        final tag = "domestic-dns-$i";
        servers.add({
          "address": server,
          "domains": hasCnDomain
              ? directDomains.where((d) => d != 'geosite:cn').toList()
              : directDomains,
          "skipFallback": true,
          "tag": tag,
        });
        if (hasCnDomain) {
          servers.add({
            "address": server,
            "domains": ["geosite:cn"],
            "expectIPs": ["geoip:cn"],
            "skipFallback": true,
            "tag": "${tag}_cn",
          });
        }
      }
    }

    // Additional DNS servers (Fallbacks)
    final addedDns = <String>{};
    if (isTest) {
      for (final dns in ["8.8.8.8", "1.1.1.1", ...dnsServers]) {
        if (addedDns.add(dns)) {
          servers.add(dns);
        }
      }
    } else {
      for (final s in dnsServers) {
        if (addedDns.add(s)) {
          servers.add({
            "address": s,
            "domains": ["geosite:geolocation-!cn", ...proxyDomains],
          });
        }
      }
      
      // Default fallbacks based on mode
      if (mode != VpnMode.direct) {
        // For rule/global mode, use international DNS as fallback
        for (final dns in ["8.8.8.8", "1.1.1.1"]) {
          if (addedDns.add(dns)) {
            servers.add({"address": dns, "tag": "fallback-dns"});
          }
        }
      } else {
        // For direct mode, use domestic DNS as fallback
        for (final dns in ["223.5.5.5", "114.114.114.114"]) {
          if (addedDns.add(dns)) {
            servers.add({"address": dns, "tag": "fallback-dns"});
          }
        }
      }
    }

    servers.add("localhost");
    return servers;
  }

  static List<Map<String, dynamic>> _buildRoutingRules(
    List<RuleModel> rules,
    bool bypassLocal,
    VpnMode mode,
    bool isTest,
  ) {
    final routingRules = <Map<String, dynamic>>[
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field",
      },
      // DNS routing for VPN mode
      {
        "inboundTag": ["tun-in"],
        "outboundTag": "dns-out",
        "port": "53",
        "type": "field",
      },
    ];

    if (!isTest) {
      routingRules.add({
        "ip": ["223.5.5.5", "114.114.114.114"],
        "port": "53",
        "network": "udp",
        "outboundTag": "direct",
        "type": "field",
      });
    }

    if (isTest) {
      routingRules.add({
        "type": "field",
        "outboundTag": "proxy",
        "port": "0-65535",
      });
    } else if (mode == VpnMode.direct) {
      routingRules.add({
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct",
      });
    } else if (mode == VpnMode.global) {
      routingRules.addAll([
        {
          "type": "field",
          "inboundTag": ["tun-in", "socks-in", "http-in"],
          "network": "tcp,udp",
          "outboundTag": "proxy",
        },
        {"type": "field", "network": "tcp,udp", "outboundTag": "direct"},
      ]);
    } else {
      // Rule mode - simplified and reliable configuration
      // Priority: Block rules → Direct rules → Proxy rules → Default direct (safer fallback)
      
      // 1. Block rules (highest priority for filtering)
      for (final r in rules.where((r) => r.enabled && r.outboundTag == 'block')) {
        final Map<String, dynamic> rule = {
          "type": "field",
          "outboundTag": r.outboundTag,
        };
        if (r.domain != null && r.domain!.isNotEmpty) {
          rule["domain"] = r.domain;
        }
        if (r.ip != null && r.ip!.isNotEmpty) {
          rule["ip"] = r.ip;
        }
        if (r.port != null && r.port!.isNotEmpty) {
          rule["port"] = r.port!.join(',');
        }
        if (r.network != null && r.network!.isNotEmpty) {
          rule["network"] = r.network!.join(',');
        }
        routingRules.add(rule);
      }

      // 2. Remote DNS and FakeDNS Traffic (Must go through Proxy)
      routingRules.addAll([
        {
          "type": "field",
          "ip": ["8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1"],
          "outboundTag": "proxy",
        },
        {
          "type": "field",
          "ip": ["198.18.0.0/15"], // FakeDNS IP range
          "outboundTag": "proxy",
        },
      ]);

      // 3. Direct rules for private networks and Chinese infrastructure
      routingRules.addAll([
        {
          "type": "field",
          "ip": ["geoip:private", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"],
          "outboundTag": "direct",
        },
        {
          "type": "field",
          "domain": ["geosite:private"],
          "outboundTag": "direct",
        },
        // DNS traffic to Chinese DNS servers goes direct
        {
          "ip": ["223.5.5.5", "223.6.6.6", "119.29.29.29", "114.114.114.114"],
          "port": "53",
          "network": "udp",
          "outboundTag": "direct",
          "type": "field",
        },
        {
          "type": "field",
          "ip": ["geoip:cn"],
          "outboundTag": "direct",
        },
        {
          "type": "field",
          "domain": ["geosite:cn"],
          "outboundTag": "direct",
        },
      ]);
      
      // 3. User-defined direct rules
      for (final r in rules.where((r) => r.enabled && r.outboundTag == 'direct')) {
        final Map<String, dynamic> rule = {
          "type": "field",
          "outboundTag": r.outboundTag,
        };
        if (r.domain != null && r.domain!.isNotEmpty) {
          rule["domain"] = r.domain;
        }
        if (r.ip != null && r.ip!.isNotEmpty) {
          rule["ip"] = r.ip;
        }
        if (r.port != null && r.port!.isNotEmpty) {
          rule["port"] = r.port!.join(',');
        }
        if (r.network != null && r.network!.isNotEmpty) {
          rule["network"] = r.network!.join(',');
        }
        routingRules.add(rule);
      }

      // 4. Proxy rules
      for (final r in rules.where((r) => r.enabled && r.outboundTag == 'proxy')) {
        final Map<String, dynamic> rule = {
          "type": "field",
          "outboundTag": r.outboundTag,
        };
        if (r.domain != null && r.domain!.isNotEmpty) {
          rule["domain"] = r.domain;
        }
        if (r.ip != null && r.ip!.isNotEmpty) {
          rule["ip"] = r.ip;
        }
        if (r.port != null && r.port!.isNotEmpty) {
          rule["port"] = r.port!.join(',');
        }
        if (r.network != null && r.network!.isNotEmpty) {
          rule["network"] = r.network!.join(',');
        }
        routingRules.add(rule);
      }
      
      // 5. Final fallback for Rule Mode
      // If traffic hasn't matched any direct/block/proxy rules yet, 
      // it means it's likely a non-CN IP or a domain that wasn't in any geosite.
      // For a "Bypass China" experience, we should proxy it.
      routingRules.add({
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "proxy",
      });
    }

    return routingRules;
  }

  static String generateBatchTestConfig(List<NodeModel> nodes) {
    final List<Map<String, dynamic>> inbounds = [];
    final List<Map<String, dynamic>> outbounds = [];
    final List<Map<String, dynamic>> rules = [];

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final tag = "node_$i";
      final port = 10811 + i; // Start from 10811 for batch testing

      inbounds.add({
        "tag": "in_$tag",
        "protocol": "socks",
        "listen": "127.0.0.1",
        "port": port,
        "settings": {"auth": "noauth", "udp": true, "userLevel": 0},
      });

      outbounds.add({
        ..._generateOutbound(
          node,
          false,
          'none',
        ), // Disable BBR/Congestion for test
        "tag": tag,
        "streamSettings": {
          ...?_generateOutbound(node, false, 'none')['streamSettings'],
          "sockopt": {"mark": 255, "tcpFastOpen": true},
        },
        "sniffing": {
          "enabled": false, // Disable sniffing for test to save time
        },
      });

      rules.add({
        "type": "field",
        "inboundTag": ["in_$tag"],
        "outboundTag": tag,
      });
    }

    // Add direct for fallback
    outbounds.add({
      "tag": "direct",
      "protocol": "freedom",
      "settings": {"domainStrategy": "UseIP"},
      "streamSettings": {
        "sockopt": {"mark": 255},
      },
    });

    final Map<String, dynamic> config = {
      "log": {"loglevel": "none"},
      "dns": {
        "servers": ["8.8.8.8", "1.1.1.1", "localhost"],
        "queryStrategy": "UseIP",
      },
      "inbounds": inbounds,
      "outbounds": outbounds,
      "routing": {"domainStrategy": "AsIs", "rules": rules},
    };

    return jsonEncode(config);
  }

  static Map<String, dynamic> _generateOutbound(
    NodeModel node,
    bool muxEnabled,
    String tcpCongestion,
  ) {
    Map<String, dynamic> outbound;
    final protocol = node.protocol.toLowerCase();

    switch (protocol) {
      case 'vmess':
        outbound = _vmessOutbound(node, tcpCongestion: tcpCongestion);
        break;
      case 'vless':
        outbound = _vlessOutbound(node, tcpCongestion: tcpCongestion);
        break;
      case 'trojan':
        outbound = _trojanOutbound(node, tcpCongestion: tcpCongestion);
        break;
      case 'shadowsocks':
      case 'ss':
        outbound = _ssOutbound(node, tcpCongestion: tcpCongestion);
        break;
      case 'socks':
        outbound = _socksOutbound(node, tcpCongestion: tcpCongestion);
        break;
      case 'http':
        outbound = _httpOutbound(node, tcpCongestion: tcpCongestion);
        break;
      case "hysteria2":
      case "hy2":
      case "hysteria":
        outbound = _hysteria2Outbound(node);
        break;
      case "tuic":
        outbound = _tuicOutbound(node);
        break;
      case "wireguard":
        outbound = _wireguardOutbound(node);
        break;
      case "dokodemo-door":
        outbound = _dokodemoOutbound(node);
        break;
      default:
        outbound = _vmessOutbound(node);
        break;
    }

    // List of protocols that support streamSettings and sockopt in Xray
    final effectiveProtocol = outbound['protocol'] as String;
    final streamSettingsSupported = [
      'vmess',
      'vless',
      'trojan',
      'shadowsocks',
      'ss',
      'socks',
      'http',
      'freedom',
      'hysteria',
      'tuic',
      'wireguard',
    ];

    if (streamSettingsSupported.contains(effectiveProtocol)) {
      final streamSettings = Map<String, dynamic>.from(
        outbound['streamSettings'] ?? {},
      );
      streamSettings['sockopt'] = {"tcpCongestion": tcpCongestion, "mark": 255};
      outbound['streamSettings'] = streamSettings;

      // Only add Mux for protocols that support it
      final muxSupported = ['vmess', 'vless', 'trojan'].contains(protocol);
      if ((node.muxEnabled == true || muxEnabled) && muxSupported) {
        final flow = node.flow?.trim() ?? "";
        final isVision = flow.contains("vision");
        final security = node.security?.toLowerCase() ?? "none";
        final isReality = security == "reality";

        outbound['mux'] = {
          "enabled": (isVision || isReality) ? false : true,
          "concurrency": node.muxConcurrency ?? 8,
        };
      }
    }

    return outbound;
  }

  static Map<String, dynamic> _wireguardOutbound(NodeModel node) {
    return {
      "protocol": "wireguard",
      "settings": {
        "secretKey": node.wgSecretKey ?? node.password ?? "",
        "address": node.wgLocalAddress ?? ["10.0.0.2/32"],
        "peers": [
          {
            "publicKey": node.wgPeerPublicKey ?? node.publicKey ?? "",
            "endpoint": "${node.address}:${node.port}",
            "preSharedKey": node.wgPreSharedKey,
            "keepAlive": node.wgKeepAlive ?? 20,
          },
        ],
        "mtu": node.wgMtu ?? 1420,
      },
    };
  }

  static Map<String, dynamic> _dokodemoOutbound(NodeModel node) {
    String network = node.network ?? "tcp,udp";
    if (network == "kcp" || network == "mkcp" || network == "nkcp") {
      network = "udp"; // Dokodemo-door network should be tcp or udp
    }
    return {
      "protocol": "dokodemo-door",
      "settings": {
        "address": node.address,
        "port": node.port,
        "network": network,
      },
    };
  }

  static String _formatBandwidth(String? val, String defaultVal) {
    if (val == null || val.isEmpty) return defaultVal;
    if (RegExp(r'^\d+$').hasMatch(val)) return "${val}mbps";
    return val;
  }

  static Map<String, dynamic> _hysteria2Outbound(NodeModel node) {
    final query = node.rawData ?? {};
    return {
      "protocol": "hysteria",
      "settings": {"version": 2, "address": node.address, "port": node.port},
      "streamSettings": {
        "network": "hysteria",
        "hysteriaSettings": {
          "version": 2,
          "auth": node.password ?? "",
          "congestion": query['obfs'] != null ? "none" : "brutal",
          "up": _formatBandwidth(query['up']?.toString(), "100mbps"),
          "down": _formatBandwidth(query['down']?.toString(), "100mbps"),
        },
        "security": "tls",
        "tlsSettings": {
          "serverName": node.sni ?? node.host ?? node.address,
          "allowInsecure": node.type == 'insecure',
          "alpn": ["h3"],
        },
        if (query['obfs'] != null)
          "udpmasks": [
            {
              "type": query['obfs'],
              "settings": {"password": query['obfs-password'] ?? ""},
            },
          ],
      },
    };
  }

  static Map<String, dynamic> _tuicOutbound(NodeModel node) {
    String alpn = node.network ?? "h3";
    if (alpn == "kcp" || alpn == "mkcp" || alpn == "nkcp") {
      alpn = "h3";
    }
    return {
      "protocol": "tuic",
      "settings": {
        "address": node.address,
        "port": node.port,
        "uuid": node.uuid,
        "password": node.password,
        "congestion": "bbr",
        "udpRelayMode": "quic",
        "zeroRttHandshake": false,
      },
      "streamSettings": {
        "security": "tls",
        "tlsSettings": {
          "serverName": node.sni ?? node.host ?? node.address,
          "allowInsecure": node.type == 'insecure',
          "alpn": [alpn],
        },
      },
    };
  }

  static Map<String, dynamic> _vmessOutbound(
    NodeModel node, {
    String tcpCongestion = 'bbr',
  }) {
    return {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": node.address,
            "port": node.port,
            "users": [
              {
                "id": node.uuid,
                "alterId": 0,
                "security": node.encryption ?? "auto",
                "level": 0,
              },
            ],
          },
        ],
      },
      "streamSettings": _getStreamSettings(node, tcpCongestion: tcpCongestion),
      "mux": {
        "enabled": node.muxEnabled ?? false,
        "concurrency": node.muxConcurrency ?? 8,
      },
    };
  }

  static Map<String, dynamic> _vlessOutbound(
    NodeModel node, {
    String tcpCongestion = 'bbr',
  }) {
    final flow = node.flow?.trim() ?? "";
    final isVision = flow.contains("vision");

    // Audit XTLS: Xray 1.8+ deprecated "security": "xtls". Force convert to "tls".
    String security = node.security?.toLowerCase() ?? "none";
    if (security == "xtls") {
      security = "tls";
    }
    final isReality = security == "reality";

    // Xray 1.8+ for VLESS-TLS requires flow: xtls-rprx-vision for Vision
    String actualFlow = "";
    if (isVision) {
      actualFlow = "xtls-rprx-vision";
    }

    return {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": node.address,
            "port": node.port,
            "users": [
              {
                "id": node.uuid,
                "encryption": node.encryption ?? "none",
                if (actualFlow.isNotEmpty) "flow": actualFlow,
              },
            ],
          },
        ],
      },
      "streamSettings": _getStreamSettings(node, tcpCongestion: tcpCongestion),
      "mux": {
        // Mux is incompatible with Vision/Reality and will cause performance issues or connection drops
        "enabled": (isVision || isReality) ? false : (node.muxEnabled ?? false),
        "concurrency": node.muxConcurrency ?? 8,
      },
    };
  }

  static Map<String, dynamic> _trojanOutbound(
    NodeModel node, {
    String tcpCongestion = 'bbr',
  }) {
    return {
      "protocol": "trojan",
      "settings": {
        "servers": [
          {
            "address": node.address,
            "port": node.port,
            "password": node.password,
          },
        ],
      },
      "streamSettings": _getStreamSettings(node, tcpCongestion: tcpCongestion),
    };
  }

  static Map<String, dynamic> _ssOutbound(
    NodeModel node, {
    String tcpCongestion = 'bbr',
  }) {
    return {
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": node.address,
            "port": node.port,
            "method": node.method ?? "aes-256-gcm",
            "password": (node.password != null && node.password!.isNotEmpty)
                ? node.password
                : "password", // Fallback to avoid Xray config error
            "udp": true,
          },
        ],
      },
      "streamSettings": _getStreamSettings(node, tcpCongestion: tcpCongestion),
    };
  }

  static Map<String, dynamic> _socksOutbound(
    NodeModel node, {
    String tcpCongestion = 'bbr',
  }) {
    return {
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": node.address,
            "port": node.port,
            "users": [
              if (node.username != null && node.username!.isNotEmpty)
                {"user": node.username, "pass": node.password},
            ],
          },
        ],
      },
      "streamSettings": _getStreamSettings(node, tcpCongestion: tcpCongestion),
    };
  }

  static Map<String, dynamic> _httpOutbound(
    NodeModel node, {
    String tcpCongestion = 'bbr',
  }) {
    return {
      "protocol": "http",
      "settings": {
        "servers": [
          {
            "address": node.address,
            "port": node.port,
            "users": [
              if (node.username != null && node.username!.isNotEmpty)
                {"user": node.username, "pass": node.password},
            ],
          },
        ],
      },
      "streamSettings": _getStreamSettings(node, tcpCongestion: tcpCongestion),
    };
  }

  static Map<String, dynamic> _getStreamSettings(
    NodeModel node, {
    String tcpCongestion = 'bbr',
  }) {
    // Audit XTLS: Force convert "xtls" to "tls" for Xray 1.8+ compatibility
    String security = node.security?.toLowerCase() ?? "none";
    if (security == "xtls") {
      security = "tls";
    }

    Map<String, dynamic> settings = {
      "network": node.network ?? "tcp",
      "security": security,
    };

    switch (node.network) {
      case "tcp":
        if (node.type == "http") {
          settings["tcpSettings"] = {
            "header": {
              "type": "http",
              "request": {
                "version": "1.1",
                "method": "GET",
                "path": node.path != null ? [node.path!] : ["/"],
                "headers": {
                  "Host": node.host != null ? [node.host!] : [""],
                  "User-Agent": [
                    "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.75 Safari/537.36",
                  ],
                  "Accept-Encoding": ["gzip, deflate"],
                  "Connection": ["keep-alive"],
                  "Pragma": ["no-cache"],
                },
              },
            },
          };
        }
        break;
      case "ws":
      case "websocket":
        settings["network"] = "ws"; // Standardize to "ws"
        settings["wsSettings"] = {
          "path": node.path ?? "/",
          "headers": {"Host": node.host ?? ""},
        };
        break;
      case "httpupgrade":
        settings["httpupgradeSettings"] = {
          "path": node.path ?? "/",
          "host": node.host ?? "",
        };
        break;
      case "grpc":
        settings["grpcSettings"] = {
          "serviceName":
              (node.serviceName != null && node.serviceName!.isNotEmpty)
              ? node.serviceName
              : (node.path ?? ""),
          "multiMode": node.mode == "multi",
        };
        break;
      case "h2":
      case "http":
        settings["httpSettings"] = {
          "path": node.path ?? "/",
          "host": [node.host ?? ""],
        };
        break;
      case "quic":
      case "xhttp":
        // Xray 1.8+ migration: Standalone QUIC transport has been removed.
        // It's migrated to XHTTP with mode: stream-one and H3 enabled.
        settings["network"] = "xhttp";
        settings["xhttpSettings"] = {
          "mode": "stream-one",
          "path": (node.path == null || node.path!.isEmpty) ? "/" : node.path,
          "host": node.host ?? "",
          "extra": {
            "h3": {"enabled": true},
          },
        };
        break;
      case "kcp":
      case "mkcp":
        settings["kcpSettings"] = {
          "mtu": 1350,
          "tti": 50,
          "uplinkCapacity": 12,
          "downlinkCapacity": 100,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
        }; // 绝对不能有 header 和 seed!

        String rawType = node.type?.trim() ?? "none";
        String headerType = rawType.isEmpty ? "none" : rawType;
        String seed = (node.path ?? node.host)?.trim() ?? "";

        final List<Map<String, dynamic>> udpMasks = [];
        if (headerType == "none" && seed.isEmpty) {
          udpMasks.add({"type": "mkcp-original"});
        } else {
          if (headerType != "none") {
            udpMasks.add({
              "type": headerType.startsWith("header-")
                  ? headerType
                  : "header-$headerType",
            });
          }
          if (seed.isNotEmpty) {
            udpMasks.add({
              "type": "mkcp-aes128gcm",
              "settings": {"password": seed},
            });
          }
        }
        settings["finalmask"] = {"udp": udpMasks};
        settings["sockopt"] = {"tcpCongestion": tcpCongestion, "mark": 255};
        break;
    }

    if (security == "tls") {
      settings["tlsSettings"] = {
        "serverName": node.sni ?? node.host ?? node.address,
        "allowInsecure": node.type == 'insecure',
        "alpn": node.alpn ?? ["h2", "http/1.1"],
        "fingerprint": node.fingerPrint ?? "chrome",
      };
    } else if (security == "reality") {
      settings["realitySettings"] = {
        "show": false,
        "fingerprint": node.fingerPrint ?? "chrome",
        "serverName": node.sni ?? node.host ?? node.address,
        "publicKey": node.publicKey ?? "",
        "shortId": node.shortId ?? "",
        "spiderX": node.spiderX ?? "/",
      };
    }

    return settings;
  }
}
