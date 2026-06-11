import 'dart:convert';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/core/rule_model.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/proxy_group_model.dart';

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
    // Mux 高级参数
    int muxConcurrency = 8,
    bool muxPadding = true,
    String muxProtocol = 'h2',
  }) {
    // [Fix] 彻底击穿枚举判定陷阱：使用模糊包含判定确保全局模式逻辑生效
    final modeStr = mode.toString().toLowerCase();
    final isGlobalMode = modeStr.contains('global');
    final effectiveRules = isGlobalMode ? <RuleModel>[] : rules;

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
    for (final rule in effectiveRules.where((r) => r.enabled)) {
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
        "queryStrategy": "UseIPv4",
        "domainStrategy": "UseIPv4", // [Fix] 强制 UseIPv4，避开 Hysteria2 IPv6 隧道陷阱
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
          "settings": {
            "domainStrategy": "UseIPv4",
          }, // [Fix] 非直连模式下的 direct 标签也强制 UseIPv4
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
        "domainStrategy": "UseIPv4", // [Fix] 强制 UseIPv4，防止 UDP 环路死锁
        "rules": _buildRoutingRules(effectiveRules, bypassLocal, mode, isTest),
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
          "domains": ["geosite:geolocation-!cn", ...proxyDomains],
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
    final modeString = mode.toString().toLowerCase();
    final isGlobal = modeString.contains('global');

    List<Map<String, dynamic>> routingRules = [
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

    if (isGlobal) {
      // 全局模式：清空一切，只留 53 端口 DNS
      routingRules.addAll([
        {
          "type": "field",
          "port": "53",
          "outboundTag": "proxy", // Xray 核心通常使用 "proxy" 标签
        },
        {"type": "field", "network": "tcp,udp", "outboundTag": "proxy"},
      ]);
    } else {
      // 规则模式：添加原有的 direct/proxy 等分流规则
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
      } else if (modeString.contains('direct')) {
        routingRules.add({
          "type": "field",
          "network": "tcp,udp",
          "outboundTag": "direct",
        });
      } else {
        // ... (原有的规则遍历/添加逻辑) ...
        // 1. Block rules
        for (final r in rules.where(
          (r) => r.enabled && r.outboundTag == 'block',
        )) {
          final Map<String, dynamic> rule = {
            "type": "field",
            "outboundTag": r.outboundTag,
          };
          if (r.domain != null && r.domain!.isNotEmpty)
            rule["domain"] = r.domain;
          if (r.ip != null && r.ip!.isNotEmpty) rule["ip"] = r.ip;
          if (r.port != null && r.port!.isNotEmpty)
            rule["port"] = r.port!.join(',');
          if (r.network != null && r.network!.isNotEmpty)
            rule["network"] = r.network!.join(',');
          routingRules.add(rule);
        }
        // 2. Remote DNS and FakeDNS
        routingRules.addAll([
          {
            "type": "field",
            "ip": ["8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1"],
            "outboundTag": "proxy",
          },
          {
            "type": "field",
            "ip": ["198.18.0.0/15"],
            "outboundTag": "proxy",
          },
        ]);
        // 3. Direct rules
        routingRules.addAll([
          {
            "type": "field",
            "ip": [
              "geoip:private",
              "192.168.0.0/16",
              "10.0.0.0/8",
              "172.16.0.0/12",
            ],
            "outboundTag": "direct",
          },
          {
            "type": "field",
            "domain": ["geosite:private"],
            "outboundTag": "direct",
          },
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
        // Default Proxy
        routingRules.add({
          "type": "field",
          "network": "tcp,udp",
          "outboundTag": "proxy",
        });
      }
    }

    // 必须在上述过滤完成后，再打印这行日志！
    print('[Flutter] 生成 Xray 配置, 模式: $mode, 规则数: ${routingRules.length}');
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
      "settings": {"domainStrategy": "UseIPv4"}, // [Fix] 直连出站也强制 UseIPv4
      "streamSettings": {
        "sockopt": {"mark": 255},
      },
    });

    final Map<String, dynamic> config = {
      "log": {"loglevel": "none"},
      "dns": {
        "servers": ["8.8.8.8", "1.1.1.1", "localhost"],
        "queryStrategy": "UseIPv4",
      },
      "inbounds": inbounds,
      "outbounds": outbounds,
      "routing": {"domainStrategy": "AsIs", "rules": rules},
    };

    return jsonEncode(config);
  }

  static String exportNodeConfig(NodeModel node) {
    // 使用核心 _generateOutbound 逻辑，确保与 Trojan TLS/WS/MTU 修复同步
    final outbound = _generateOutbound(node, false, 'bbr');

    final Map<String, dynamic> config = {
      "log": {"loglevel": "info"},
      "inbounds": [
        {
          "port": 10808,
          "protocol": "socks",
          "listen": "127.0.0.1",
          "settings": {"auth": "noauth", "udp": true},
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
          },
        },
      ],
      "outbounds": [
        {...outbound, "tag": "proxy"},
        {
          "tag": "direct",
          "protocol": "freedom",
          "settings": {"domainStrategy": "UseIPv4"},
        },
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {
            "type": "field",
            "ip": ["geoip:private", "geoip:cn"],
            "outboundTag": "direct",
          },
          {
            "type": "field",
            "domain": ["geosite:cn"],
            "outboundTag": "direct",
          },
        ],
      },
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  static Map<String, dynamic> _generateOutbound(
    NodeModel node,
    bool muxEnabled,
    String tcpCongestion, {
    int muxConcurrency = 8,
    bool muxPadding = true,
    String muxProtocol = 'h2',
  }) {
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
      // [Fix] 强固物理防环路 mark 标记 (255)，确保与 Android VpnService 路由绕过对齐
      // [Audit] CDN 环境下 Trojan 流量黑洞修复：强制 MTU 限制为 1400 防止分片丢包
      streamSettings['sockopt'] = {
        "tcpCongestion": tcpCongestion,
        "mark": 255,
        "tcpFastOpen": true,
        if (protocol == 'trojan') "mtu": 1400,
      };
      outbound['streamSettings'] = streamSettings;

      // Only add Mux for protocols that support it
      // [Audit] Trojan Mux is often problematic and not supported by many servers.
      // Removing 'trojan' from muxSupported to ensure stability as per Architect's directive.
      final muxSupported = ['vmess', 'vless'].contains(protocol);
      if ((node.muxEnabled == true || muxEnabled) && muxSupported) {
        final flow = node.flow?.trim() ?? "";
        final isVision = flow.contains("vision");
        final security = node.security?.toLowerCase() ?? "none";
        final isReality = security == "reality";

        outbound['mux'] = {
          "enabled": (isVision || isReality) ? false : true,
          "concurrency": node.muxConcurrency ?? muxConcurrency,
          "padding": muxPadding,
          "protocol": muxProtocol,
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
          "alpn": ["h3"],
          if (node.pinSHA256 != null && node.pinSHA256!.isNotEmpty)
            "pinnedPeerCertSha256": [node.pinSHA256]
          else
            "allowInsecure": true,
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
          "alpn": [alpn],
          if (node.pinSHA256 != null && node.pinSHA256!.isNotEmpty)
            "pinnedPeerCertSha256": [node.pinSHA256],
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
    // [Fix] Trojan 协议核心审计：强制开启 TLS 防护罩
    // Trojan 几乎 100% 要求 TLS。如果 security 为空或 none，强制修正为 tls，防止“裸奔”导致连接被掐断。
    String security = node.security?.toLowerCase() ?? "none";
    NodeModel effectiveNode = node;
    if (security == "none") {
      effectiveNode = node.copyWith(security: "tls");
    }

    return {
      "protocol": "trojan",
      "settings": {
        "servers": [
          {
            "address": effectiveNode.address,
            "port": effectiveNode.port,
            "password": effectiveNode.password,
          },
        ],
      },
      "streamSettings": _getStreamSettings(
        effectiveNode,
        tcpCongestion: tcpCongestion,
      ),
      // [Fix] 显式禁用 Mux，防止部分 Trojan 服务端握手失败
      "mux": {"enabled": false},
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
          "headers": {
            // [Fix] CDN Header 校验：Host 强制对齐 node.host，缺失则回退到 sni
            "Host": node.host ?? node.sni ?? "",
            "User-Agent":
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
          },
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
        "alpn": node.alpn ?? ["h2", "http/1.1"],
        "fingerprint": node.fingerPrint ?? "chrome",
        if (node.pinSHA256 != null && node.pinSHA256!.isNotEmpty)
          "pinnedPeerCertSha256": [node.pinSHA256],
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

  // --- 代理组支持 ---

  static String generateConfigWithGroups({
    required List<NodeModel> allNodes,
    required List<ProxyGroupModel> groups,
    required String selectedGroupId,
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
    String dns = '8.8.8.8, 1.1.1.1',
    bool fakeDns = true,
    String remoteDns = '1.1.1.1, 1.0.0.1',
    String domesticDns = '223.5.5.5, 223.6.6.6',
    bool enableIPv6 = true,
    String dnsHosts = '',
    // Mux 高级参数
    int muxConcurrency = 8,
    bool muxPadding = true,
    String muxProtocol = 'h2',
  }) {
    final modeStr = mode.toString().toLowerCase();
    final isGlobalMode = modeStr.contains('global');
    final effectiveRules = isGlobalMode ? <RuleModel>[] : rules;
    final listenAddr = allowLan ? "0.0.0.0" : "127.0.0.1";

    final nodeMap = {for (final n in allNodes) n.id: n};

    // 构建所有出站代理
    final outbounds = <Map<String, dynamic>>[
      {"protocol": "freedom", "settings": {}, "tag": "api"},
    ];

    // 添加所有单个节点
    for (final node in allNodes) {
      outbounds.add({
        ..._generateOutbound(
          node,
          muxEnabled,
          tcpCongestion,
          muxConcurrency: muxConcurrency,
          muxPadding: muxPadding,
          muxProtocol: muxProtocol,
        ),
        "tag": "node-${node.id}",
      });
    }

    // 添加代理组
    for (final group in groups.where((g) => !g.hidden)) {
      outbounds.add(_buildProxyGroupOutbound(
        group,
        nodeMap,
        muxEnabled,
        tcpCongestion,
        muxConcurrency: muxConcurrency,
        muxPadding: muxPadding,
        muxProtocol: muxProtocol,
      ));
    }

    // 添加标准 outbounds
    outbounds.addAll([
      {
        "tag": "direct",
        "protocol": "freedom",
        "settings": {"domainStrategy": "UseIPv4"},
        "streamSettings": {
          "sockopt": {"tcpCongestion": tcpCongestion, "mark": 255},
        },
      },
      {
        "tag": "block",
        "protocol": "blackhole",
        "settings": {"response": {"type": "none"}},
      },
      {"tag": "dns-out", "protocol": "dns", "settings": {}},
    ]);

    // 确定主出站 tag
    final selectedGroup = groups.where((g) => g.id == selectedGroupId).firstOrNull;
    final mainOutboundTag = selectedGroup != null
        ? "group-${selectedGroup.id}"
        : (allNodes.isNotEmpty ? "node-${allNodes.first.id}" : "direct");

    final config = {
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
        "servers": [],
        "queryStrategy": "UseIPv4",
        "domainStrategy": "UseIPv4",
        "tag": "dns-out",
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
        ],
      ],
      "outbounds": outbounds,
      "routing": {
        "domainStrategy": "UseIPv4",
        "rules": _buildRoutingRulesWithGroups(
          effectiveRules,
          bypassLocal,
          mode,
          isTest,
          mainOutboundTag,
        ),
      },
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  static Map<String, dynamic> _buildProxyGroupOutbound(
    ProxyGroupModel group,
    Map<String, NodeModel> nodeMap,
    bool muxEnabled,
    String tcpCongestion, {
    int muxConcurrency = 8,
    bool muxPadding = true,
    String muxProtocol = 'h2',
  }) {
    final validProxies = group.proxies.where((id) => nodeMap.containsKey(id)).toList();

    switch (group.type) {
      case ProxyGroupType.select:
        return {
          "tag": "group-${group.id}",
          "protocol": "selector",
          "settings": {
            "outbounds": validProxies.map((id) => "node-$id").toList(),
          },
        };
      case ProxyGroupType.urlTest:
        return {
          "tag": "group-${group.id}",
          "protocol": "urltest",
          "settings": {
            "outbounds": validProxies.map((id) => "node-$id").toList(),
            "url": group.url ?? "http://www.gstatic.com/generate_204",
            "interval": (group.interval ?? 300) * 1000,
            "tolerance": group.tolerance ?? 150,
          },
        };
      case ProxyGroupType.fallback:
        return {
          "tag": "group-${group.id}",
          "protocol": "fallback",
          "settings": {
            "outbounds": validProxies.map((id) => "node-$id").toList(),
            "url": group.url ?? "http://www.gstatic.com/generate_204",
            "interval": (group.interval ?? 300) * 1000,
          },
        };
      case ProxyGroupType.loadBalance:
        return {
          "tag": "group-${group.id}",
          "protocol": "loadbalance",
          "settings": {
            "outbounds": validProxies.map((id) => "node-$id").toList(),
            "strategy": group.strategy ?? "round-robin",
          },
        };
      case ProxyGroupType.relay:
        final chainOutbounds = <Map<String, dynamic>>[];
        for (var i = 0; i < validProxies.length; i++) {
          final proxyId = validProxies[i];
          chainOutbounds.add({
            "tag": "relay-$proxyId",
            ..._generateOutbound(
              nodeMap[proxyId]!,
              muxEnabled,
              tcpCongestion,
              muxConcurrency: muxConcurrency,
              muxPadding: muxPadding,
              muxProtocol: muxProtocol,
            ),
          });
        }
        return {
          "tag": "group-${group.id}",
          "protocol": "relay",
          "settings": {
            "outbounds": validProxies.map((id) => "relay-$id").toList(),
          },
        };
      default:
        return {
          "tag": "group-${group.id}",
          "protocol": "selector",
          "settings": {
            "outbounds": validProxies.map((id) => "node-$id").toList(),
          },
        };
    }
  }

  static List<Map<String, dynamic>> _buildRoutingRulesWithGroups(
    List<RuleModel> rules,
    bool bypassLocal,
    VpnMode mode,
    bool isTest,
    String mainOutboundTag,
  ) {
    final routingRules = <Map<String, dynamic>>[
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field",
      },
      {
        "inboundTag": ["tun-in"],
        "outboundTag": "dns-out",
        "port": "53",
        "type": "field",
      },
    ];

    final modeString = mode.toString().toLowerCase();
    final isGlobal = modeString.contains('global');

    if (isGlobal) {
      routingRules.addAll([
        {"type": "field", "port": "53", "outboundTag": mainOutboundTag},
        {"type": "field", "network": "tcp,udp", "outboundTag": mainOutboundTag},
      ]);
    } else {
      if (!isTest) {
        routingRules.add({
          "ip": ["223.5.5.5", "114.114.114.114"],
          "port": "53",
          "network": "udp",
          "outboundTag": "direct",
          "type": "field",
        });
      }

      // 添加用户规则
      for (final rule in rules.where((r) => r.enabled)) {
        final Map<String, dynamic> ruleMap = {
          "type": "field",
          "outboundTag": rule.outboundTag == "proxy" ? mainOutboundTag : rule.outboundTag,
        };
        if (rule.domain != null && rule.domain!.isNotEmpty) {
          ruleMap["domain"] = rule.domain;
        }
        if (rule.ip != null && rule.ip!.isNotEmpty) {
          ruleMap["ip"] = rule.ip;
        }
        if (rule.port != null && rule.port!.isNotEmpty) {
          ruleMap["port"] = rule.port!.join(',');
        }
        if (rule.network != null && rule.network!.isNotEmpty) {
          ruleMap["network"] = rule.network!.join(',');
        }
        routingRules.add(ruleMap);
      }

      // 默认直连规则
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

      // 默认使用主出站
      routingRules.add({
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": mainOutboundTag,
      });
    }

    return routingRules;
  }
}
