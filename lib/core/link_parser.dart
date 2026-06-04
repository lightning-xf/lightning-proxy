import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:lightning/core/node_model.dart';

class LinkParser {
  static String _generateId(
    String prefix,
    String name,
    String address,
    int port, [
    String? extra,
  ]) {
    final input = '$prefix$name$address$port${extra ?? ''}';
    return sha1.convert(utf8.encode(input)).toString();
  }

  static List<NodeModel> parse(String text) {
    final List<NodeModel> nodes = [];
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return nodes;

    // 1. Check if it's Xray/V2Ray JSON config
    if (trimmedText.startsWith('{') && trimmedText.endsWith('}')) {
      try {
        final Map<String, dynamic> data = jsonDecode(trimmedText);
        if (data.containsKey('outbounds') || data.containsKey('protocol')) {
          final jsonNodes = _parseXrayJson(data);
          if (jsonNodes.isNotEmpty) return jsonNodes;
        }
      } catch (_) {}
    }

    // 2. Check if it's Clash YAML (Sniffing for proxies: or port:)
    if (trimmedText.contains('proxies:') ||
        (trimmedText.contains('name:') &&
            trimmedText.contains('type:') &&
            trimmedText.contains('server:'))) {
      try {
        final yamlNodes = _parseClashYaml(trimmedText);
        if (yamlNodes.isNotEmpty) return yamlNodes;
      } catch (e) {
        debugPrint(
          'YAML sniffing matched but parse failed, trying other methods: $e',
        );
      }
    }

    // 3. Handle Subscription Content (Base64 or Multiple Lines)
    String content = trimmedText;

    // [Fix] 增强型正则清洗：处理机场下发文本中夹杂的 HTML 标签、乱码或干扰字符
    // 1. 过滤掉常见的 HTML 标签 (如 <br>, <p> 等)
    content = content.replaceAll(RegExp(r'<[^>]*>'), '');
    // 2. 过滤掉常见的网页转义符
    content = content.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&');

    // [Fix] 混合文本保底提取：如果文本中混有大量的垃圾字符，直接用正则扫描出所有协议 URI
    final List<String> extractedUris = [];
    final protocolRegex = RegExp(
      r'(vmess|vless|trojan|ss|socks5|socks|http|https|hysteria2|hy2|tuic|wireguard|shadowrocket):\/\/[^\s\r\n\t<>"]+',
      caseSensitive: false,
    );
    final matches = protocolRegex.allMatches(content);
    for (final match in matches) {
      extractedUris.add(match.group(0)!);
    }

    // 如果正则扫描到了 URI，说明可能是混合文本，直接进入 URI 解析流程
    if (extractedUris.isNotEmpty && !content.contains('proxies:')) {
      for (var uri in extractedUris) {
        try {
          _parseSingleUri(uri, nodes);
        } catch (_) {}
      }
      return _deduplicateNodes(nodes);
    }

    // Improved Base64 detection:
    // If it doesn't contain common protocol prefixes and looks like Base64 (ignoring whitespace)
    bool isLikelyBase64(String str) {
      final clean = str.replaceAll(RegExp(r'[\s\r\n]+'), '');
      if (clean.isEmpty || clean.length < 8) return false;

      // Must only contain Base64 characters
      if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(clean)) return false;

      // If it already contains protocol schemes at the start, it's a single node link, not a base64-wrapped sub
      final lower = str.toLowerCase();
      if (lower.startsWith('vmess://') ||
          lower.startsWith('vless://') ||
          lower.startsWith('ss://') ||
          lower.startsWith('trojan://') ||
          lower.startsWith('hysteria2://') ||
          lower.startsWith('tuic://')) {
        return false;
      }

      return true;
    }

    if (isLikelyBase64(content)) {
      try {
        // Robust Base64 Decoding Logic
        // 1. Remove all whitespace, newlines and tabs
        String toDecode = content.replaceAll(RegExp(r'[\s\r\n\t]+'), '');

        // 2. Handle URL-Safe Base64
        toDecode = toDecode.replaceAll('-', '+').replaceAll('_', '/');

        // 3. Auto-padding for length % 4
        int padLength = (4 - (toDecode.length % 4)) % 4;
        toDecode += '=' * padLength;

        final decoded = utf8.decode(
          base64.decode(toDecode),
          allowMalformed: true,
        );
        if (decoded.trim().isNotEmpty) {
          // Shadowrocket metadata filtering (STATUS=..., REMARKS=...)
          // Cleaning dirty data: split by line and skip non-protocol lines
          final List<String> filteredLines = [];
          for (var line in decoded.split(RegExp(r'[\n\r]+'))) {
            final l = line.trim();
            if (l.isEmpty) continue;
            // Skip common metadata headers
            if (l.startsWith('STATUS=') ||
                l.startsWith('REMARKS=') ||
                l.startsWith('INTERVAL='))
              continue;
            filteredLines.add(l);
          }
          content = filteredLines.join('\n');
        }
      } catch (e) {
        debugPrint(
          'Base64 decode failed, original body starts with: ${content.substring(0, content.length > 100 ? 100 : content.length)}',
        );
        debugPrint('Error: $e');
      }
    }

    final lines = content.split(RegExp(r'[\n\r,;]+'));

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      _parseSingleUri(line, nodes);
    }

    return _deduplicateNodes(nodes);
  }

  static void _parseSingleUri(String line, List<NodeModel> nodes) {
    try {
      if (line.startsWith('vmess://')) {
        nodes.add(_parseVmess(line));
      } else if (line.startsWith('vless://')) {
        nodes.add(_parseVless(line));
      } else if (line.startsWith('trojan://')) {
        nodes.add(_parseTrojan(line));
      } else if (line.startsWith('ss://')) {
        nodes.add(_parseSS(line));
      } else if (line.startsWith('socks5://') || line.startsWith('socks://')) {
        nodes.add(_parseSocks(line));
      } else if (line.startsWith('http://') || line.startsWith('https://')) {
        nodes.add(_parseHttp(line));
      } else if (line.startsWith('hysteria2://') || line.startsWith('hy2://')) {
        nodes.add(_parseHysteria2(line));
      } else if (line.startsWith('tuic://')) {
        nodes.add(_parseTuic(line));
      } else if (line.startsWith('wireguard://')) {
        nodes.add(_parseWireGuard(line));
      } else if (line.startsWith('dokodemo-door://')) {
        nodes.add(_parseDokodemo(line));
      } else if (line.startsWith('shadowrocket://')) {
        final innerLink = _decodeShadowrocketLink(line);
        if (innerLink != null) {
          final innerNodes = parse(innerLink);
          nodes.addAll(innerNodes);
        }
      }
    } catch (e) {
      debugPrint('Failed to parse link: $line, error: $e');
    }
  }

  static List<NodeModel> _deduplicateNodes(List<NodeModel> nodes) {
    final seenIds = <String>{};
    return nodes.where((n) => seenIds.add(n.id)).toList();
  }

  static String? _decodeShadowrocketLink(String link) {
    try {
      final base64Part = link.substring(15);
      String toDecode = base64Part;
      while (toDecode.length % 4 != 0) toDecode += '=';
      return utf8.decode(base64.decode(toDecode), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static NodeModel _parseVmess(String link) {
    try {
      // Handle links with query parameters at the end (e.g., vmess://BASE64?remarks=...)
      String mainPart = link.substring(8);
      Map<String, String> queryParams = {};
      if (mainPart.contains('?')) {
        final parts = mainPart.split('?');
        mainPart = parts[0];
        queryParams = Uri.splitQueryString(parts[1]);
      } else if (mainPart.contains('#')) {
        final parts = mainPart.split('#');
        mainPart = parts[0];
        queryParams['ps'] = Uri.decodeComponent(parts[1]);
      }

      String normalizedBase64 = mainPart.trim();
      while (normalizedBase64.length % 4 != 0) {
        normalizedBase64 += '=';
      }

      final decoded = utf8.decode(
        base64.decode(normalizedBase64),
        allowMalformed: true,
      );

      // Check if it's JSON format (standard)
      if (decoded.trim().startsWith('{')) {
        final Map<String, dynamic> data = jsonDecode(decoded);
        final name =
            data['ps']?.toString() ??
            queryParams['remarks'] ??
            queryParams['ps'] ??
            'VMess Node';
        final address = data['add']?.toString() ?? '';
        final port = int.tryParse(data['port']?.toString() ?? '443') ?? 443;
        final uuid = data['id']?.toString() ?? '';

        return NodeModel(
          id: _generateId('vmess', name, address, port, uuid),
          name: name,
          protocol: 'vmess',
          address: address,
          port: port,
          uuid: uuid,
          security: data['tls'] == 'tls' ? 'tls' : 'none',
          network: data['net']?.toString() ?? 'tcp',
          host: data['host']?.toString(),
          path: data['path']?.toString(),
          sni: data['sni']?.toString(),
          type: data['type']?.toString() ?? 'none',
          encryption: data['scy']?.toString() ?? 'auto',
          rawData: data,
        );
      } else {
        // Legacy format: method:uuid@address:port
        // or method:uuid@address:port?query
        final atParts = decoded.split('@');
        if (atParts.length == 2) {
          final userInfo = atParts[0].split(':');
          final serverInfo = atParts[1].split(':');

          final encryption = userInfo[0];
          final uuid = userInfo.length > 1 ? userInfo[1] : '';
          final address = serverInfo[0];
          final port = serverInfo.length > 1
              ? (int.tryParse(serverInfo[1]) ?? 443)
              : 443;

          final name =
              queryParams['remarks'] ?? queryParams['ps'] ?? 'VMess Node';

          return NodeModel(
            id: _generateId('vmess', name, address, port, uuid),
            name: name,
            protocol: 'vmess',
            address: address,
            port: port,
            uuid: uuid,
            encryption: encryption,
            network: queryParams['obfs'] ?? 'tcp',
            host: queryParams['obfsParam'] ?? queryParams['host'],
            path: queryParams['path'],
            security: queryParams['tls'] == '1' ? 'tls' : 'none',
            rawData: queryParams,
          );
        }
      }
    } catch (e) {
      debugPrint('VMess parse error: $e');
    }

    // Fallback or empty result
    return NodeModel(
      id: 'error-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Invalid VMess Link',
      protocol: 'vmess',
      address: '',
      port: 0,
    );
  }

  static NodeModel _parseVless(String link) {
    final uri = Uri.parse(link);
    final query = uri.queryParameters;
    final name = Uri.decodeComponent(uri.fragment).isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : (query['remark'] ?? query['ps'] ?? 'VLESS Node');

    final net = query['type'] ?? 'tcp';

    return NodeModel(
      id: _generateId('vless', name, uri.host, uri.port, uri.userInfo),
      name: name,
      protocol: 'vless',
      address: uri.host,
      port: uri.port,
      uuid: uri.userInfo,
      network: net,
      security: query['security'] ?? 'none',
      sni: query['sni'] ?? query['peer'],
      host: query['host'],
      path: query['path'],
      type: query['headerType'] ?? 'none',
      publicKey: query['pbk'],
      fingerPrint: query['fp'],
      shortId: query['sid'],
      spiderX: query['spx'],
      flow: query['flow'],
      serviceName: query['serviceName'],
      mode: query['mode'],
      encryption: query['encryption'] ?? 'none',
      rawData: query,
    );
  }

  static NodeModel _parseTrojan(String link) {
    final uri = Uri.parse(link);
    final Map<String, String> query = {};

    // 1. 暴力切分 Query 参数 (Final Fix)
    // 确保任何特殊字符和 Emoji 都能被安全消化
    if (uri.query.isNotEmpty) {
      for (var part in uri.query.split('&')) {
        final kv = part.split('=');
        if (kv.length == 2) {
          query[kv[0]] = Uri.decodeComponent(kv[1]);
        }
      }
    }

    final name = Uri.decodeComponent(uri.fragment).isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : (query['remark'] ?? query['ps'] ?? 'Trojan Node');

    final net = query['type'] ?? 'tcp';

    // 2. 物理还原密码 (userInfo) (Final Fix)
    // Trojan 协议里，password 就是 userInfo，必须解密
    final password = Uri.decodeComponent(uri.userInfo);

    // 3. 彻底清洗 Path，强制剔除 Emoji 等非法字符 (Final Fix)
    String? path = query['path'];
    if (path != null) {
      path = path.replaceAll(RegExp(r'[^\x00-\x7F]'), '');
    }

    return NodeModel(
      id: _generateId('trojan', name, uri.host, uri.port, password),
      name: name,
      protocol: 'trojan',
      address: uri.host,
      port: uri.port,
      password: password,
      network: net,
      security: query['security'] ?? 'tls',
      sni: query['sni'] ?? query['peer'],
      // [Fix] Host 回退逻辑：强制对齐 SNI 防止 CDN 握手失败
      host: query['host'] ?? query['sni'] ?? query['peer'],
      path: path,
      type: query['headerType'] ?? 'none',
      rawData: query,
    );
  }

  static NodeModel _parseSS(String link) {
    String name = 'Shadowsocks Node';
    if (link.contains('#')) {
      final parts = link.split('#');
      name = Uri.decodeComponent(parts[1]);
      link = parts[0];
    }

    final String data = link.substring(5);
    String method = '';
    String password = '';
    String address = '';
    int port = 8388;
    Map<String, String>? pluginParams;

    if (data.contains('@')) {
      // Standard format: ss://BASE64(method:password)@address:port
      final parts = data.split('@');
      final userInfoBase64 = parts[0];
      final serverInfo = parts[1];

      try {
        String normalizedUserInfo = userInfoBase64;
        while (normalizedUserInfo.length % 4 != 0) normalizedUserInfo += '=';
        final decoded = utf8.decode(base64.decode(normalizedUserInfo));
        if (decoded.contains(':')) {
          final up = decoded.split(':');
          method = up[0];
          password = up[1];
        }
      } catch (_) {
        // Maybe userInfo is not base64 but plaintext (some clients)
        if (userInfoBase64.contains(':')) {
          final up = userInfoBase64.split(':');
          method = up[0];
          password = up[1];
        }
      }

      final serverParts = serverInfo.split(':');
      address = serverParts[0];
      if (serverParts.length > 1) {
        // Handle port and possible query params
        final portAndQuery = serverParts[1].split('?');
        port = int.tryParse(portAndQuery[0]) ?? 8388;
        if (portAndQuery.length > 1) {
          final query = Uri.splitQueryString(portAndQuery[1]);
          if (query.containsKey('plugin')) {
            // Shadowrocket plugin format
            pluginParams = _parseSSPlugin(query['plugin']!);
          }
        }
      }
    } else {
      // Legacy format: ss://BASE64(method:password@address:port)
      try {
        String normalizedData = data;
        while (normalizedData.length % 4 != 0) normalizedData += '=';
        final decoded = utf8.decode(base64.decode(normalizedData));
        final atParts = decoded.split('@');
        if (atParts.length == 2) {
          final up = atParts[0].split(':');
          final ap = atParts[1].split(':');
          method = up[0];
          password = up[1];
          address = ap[0];
          port = int.tryParse(ap[1]) ?? 8388;
        }
      } catch (_) {}
    }

    return NodeModel(
      id: _generateId('ss', name, address, port, password),
      name: name,
      protocol: 'shadowsocks',
      address: address,
      port: port,
      method: method,
      password: password,
      type: pluginParams?['obfs'] ?? 'none',
      host: pluginParams?['obfs-host'],
      rawData: {'plugin': pluginParams},
    );
  }

  static Map<String, String> _parseSSPlugin(String plugin) {
    final Map<String, String> params = {};
    final parts = plugin.split(';');
    for (final part in parts) {
      if (part.contains('=')) {
        final kv = part.split('=');
        params[kv[0]] = kv[1];
      } else {
        params['type'] = part;
      }
    }
    return params;
  }

  static NodeModel _parseSocks(String link) {
    final uri = Uri.parse(link);
    String username = '';
    String password = '';

    if (uri.userInfo.contains(':')) {
      final parts = uri.userInfo.split(':');
      username = parts[0];
      password = parts[1];
    } else {
      username = uri.userInfo;
    }

    final query = uri.queryParameters;
    final name = Uri.decodeComponent(uri.fragment).isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : (query['remark'] ?? query['ps'] ?? 'SOCKS5 Node');

    return NodeModel(
      id: _generateId('socks', name, uri.host, uri.port, uri.userInfo),
      name: name,
      protocol: 'socks',
      address: uri.host,
      port: uri.port > 0 ? uri.port : 1080,
      username: username,
      password: password,
      rawData: query,
      security: query['tls'] == '1' || query['security'] == 'tls'
          ? 'tls'
          : 'none',
    );
  }

  static NodeModel _parseHttp(String link) {
    final uri = Uri.parse(link);
    String username = '';
    String password = '';

    if (uri.userInfo.contains(':')) {
      final parts = uri.userInfo.split(':');
      username = parts[0];
      password = parts[1];
    } else {
      username = uri.userInfo;
    }

    final query = uri.queryParameters;
    final name = Uri.decodeComponent(uri.fragment).isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : (query['remark'] ?? query['ps'] ?? 'HTTP Node');

    return NodeModel(
      id: _generateId('http', name, uri.host, uri.port, uri.userInfo),
      name: name,
      protocol: 'http',
      address: uri.host,
      port: uri.port > 0 ? uri.port : 80,
      username: username,
      password: password,
      rawData: query,
      security: query['tls'] == '1' || query['security'] == 'tls'
          ? 'tls'
          : 'none',
    );
  }

  static NodeModel _parseHysteria2(String link) {
    final uri = Uri.parse(link);
    final query = uri.queryParameters;
    final name = Uri.decodeComponent(uri.fragment).isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : (query['remark'] ?? query['ps'] ?? 'Hysteria2 Node');

    return NodeModel(
      id: _generateId('hy2', name, uri.host, uri.port, uri.userInfo),
      name: name,
      protocol: 'hysteria2',
      address: uri.host,
      port: uri.port,
      password: uri.userInfo,
      sni: query['sni'],
      host: query['host'],
      path: query['path'],
      type: query['insecure'] == '1' ? 'insecure' : null,
      rawData: query,
    );
  }

  static NodeModel _parseTuic(String link) {
    final uri = Uri.parse(link);
    final query = uri.queryParameters;

    String uuid = '';
    String password = '';
    if (uri.userInfo.contains(':')) {
      final parts = uri.userInfo.split(':');
      uuid = parts[0];
      password = parts[1];
    } else {
      uuid = uri.userInfo;
    }

    final name = Uri.decodeComponent(uri.fragment).isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : (query['remark'] ?? query['ps'] ?? 'TUIC Node');

    return NodeModel(
      id: _generateId('tuic', name, uri.host, uri.port, uri.userInfo),
      name: name,
      protocol: 'tuic',
      address: uri.host,
      port: uri.port,
      uuid: uuid,
      password: password,
      sni: query['sni'],
      network: query['alpn'],
      type: query['insecure'] == '1' ? 'insecure' : null,
      rawData: query,
    );
  }

  static NodeModel _parseWireGuard(String link) {
    final uri = Uri.parse(link);
    final query = uri.queryParameters;
    final name = Uri.decodeComponent(uri.fragment).isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : (query['remark'] ?? query['ps'] ?? 'WireGuard Node');

    return NodeModel(
      id: _generateId('wg', name, uri.host, uri.port, uri.userInfo),
      name: name,
      protocol: 'wireguard',
      address: uri.host,
      port: uri.port,
      wgSecretKey: uri.userInfo,
      wgPeerPublicKey: query['public_key'] ?? query['pk'],
      wgPreSharedKey: query['preshared_key'] ?? query['psk'],
      wgLocalAddress: query['address']?.split(','),
      wgMtu: int.tryParse(query['mtu'] ?? ''),
      wgKeepAlive: int.tryParse(query['keepalive'] ?? ''),
      rawData: query,
    );
  }

  static NodeModel _parseDokodemo(String link) {
    final uri = Uri.parse(link);
    final query = uri.queryParameters;
    final name = Uri.decodeComponent(uri.fragment).isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : (query['remark'] ?? query['ps'] ?? 'Dokodemo Node');

    return NodeModel(
      id: _generateId('dokodemo', name, uri.host, uri.port),
      name: name,
      protocol: 'dokodemo-door',
      address: uri.host,
      port: uri.port,
      network: query['network'] ?? 'tcp,udp',
      rawData: query,
    );
  }

  static List<NodeModel> _parseClashYaml(String yamlText) {
    final List<NodeModel> nodes = [];
    try {
      // 1. Try to find the 'proxies:' section
      final proxiesMatch = RegExp(
        r'^proxies:\s*$',
        multiLine: true,
      ).firstMatch(yamlText);
      if (proxiesMatch != null) {
        final proxiesContent = yamlText.substring(proxiesMatch.end);
        // Find where the next top-level key starts (indented by 0 spaces)
        final nextKeyMatch = RegExp(
          r'^\S',
          multiLine: true,
        ).firstMatch(proxiesContent);
        final section = nextKeyMatch != null
            ? proxiesContent.substring(0, nextKeyMatch.start)
            : proxiesContent;

        // Split by '-' at the start of lines to get individual proxy blocks
        final blocks = section.split(RegExp(r'^\s*-\s*', multiLine: true));
        for (final block in blocks) {
          if (block.trim().isEmpty) continue;

          if (block.trim().startsWith('{')) {
            // Handle inline style: - { name: ..., type: ... }
            final inlineNodes = _parseClashInline('- $block');
            nodes.addAll(inlineNodes);
          } else {
            // Handle block style:
            //   name: ...
            //   type: ...
            _parseSingleClashProxy(block, nodes);
          }
        }
      } else {
        // 2. Fallback: search for inline proxies anywhere if no 'proxies:' section found
        nodes.addAll(_parseClashInline(yamlText));
      }
    } catch (e) {
      debugPrint('Clash YAML parse error: $e');
    }
    return nodes;
  }

  static String? _extractYamlValue(String segment, String key) {
    final regex = RegExp('$key:\\s*([^,\\s}]+)');
    final match = regex.firstMatch(segment);
    return match?.group(1)?.replaceAll('"', '').replaceAll("'", "");
  }

  static List<NodeModel> _parseClashInline(String yaml) {
    final List<NodeModel> nodes = [];
    final inlineRegex = RegExp(r'-\s*\{([^}]+)\}');
    final matches = inlineRegex.allMatches(yaml);
    for (var match in matches) {
      final content = match.group(1) ?? '';
      final Map<String, dynamic> data = {};

      int braceDepth = 0;
      bool inQuotes = false;
      String currentKey = '';
      String currentValue = '';
      bool parsingValue = false;

      for (int i = 0; i < content.length; i++) {
        final char = content[i];
        if (char == '"' || char == "'") {
          inQuotes = !inQuotes;
        } else if (!inQuotes && char == ':') {
          parsingValue = true;
        } else if (!inQuotes && char == ',') {
          if (currentKey.isNotEmpty) {
            data[currentKey.trim().replaceAll(
              RegExp(r"^['" + '"' + r"]|['" + '"' + r"]$"),
              '',
            )] = currentValue.trim().replaceAll(
              RegExp(r"^['" + '"' + r"]|['" + '"' + r"]$"),
              '',
            );
          }
          currentKey = '';
          currentValue = '';
          parsingValue = false;
        } else {
          if (parsingValue)
            currentValue += char;
          else
            currentKey += char;
        }
      }
      if (currentKey.isNotEmpty) {
        data[currentKey.trim().replaceAll(
          RegExp(r"^['" + '"' + r"]|['" + '"' + r"]$"),
          '',
        )] = currentValue.trim().replaceAll(
          RegExp(r"^['" + '"' + r"]|['" + '"' + r"]$"),
          '',
        );
      }

      _addNodeFromData(data, nodes);
    }
    return nodes;
  }

  static void _parseSingleClashProxy(String block, List<NodeModel> nodes) {
    try {
      final Map<String, dynamic> data = {};
      final lines = block.split('\n');
      for (var line in lines) {
        final cleanLine = line.trim().replaceFirst(RegExp(r'^-?\s*'), '');
        final kv = cleanLine.split(':');
        if (kv.length >= 2) {
          final key = kv[0].trim().replaceAll(
            RegExp(r"^['" + '"' + r"]|['" + '"' + r"]$"),
            '',
          );
          var value = kv.sublist(1).join(':').trim();
          value = value.split('#')[0].trim();
          value = value.replaceAll(
            RegExp(r"^['" + '"' + r"]|['" + '"' + r"]$"),
            '',
          );
          data[key] = value;
        }
      }
      _addNodeFromData(data, nodes);
    } catch (e) {
      print('Error parsing proxy block: $e');
    }
  }

  static String _decodeYamlString(String input) {
    if (input.isEmpty) return input;

    String result = input;
    // Handle Unicode escapes like \u4e2d\u56fd
    result = result.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
      final hex = match.group(1)!;
      final code = int.parse(hex, radix: 16);
      return String.fromCharCode(code);
    });

    // Handle other common escapes
    result = result
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');

    return result;
  }

  static void _addNodeFromData(
    Map<String, dynamic> data,
    List<NodeModel> nodes,
  ) {
    final type = data['type']?.toString().toLowerCase() ?? '';
    final name = _decodeYamlString(data['name']?.toString() ?? 'Clash Node');
    final server = data['server']?.toString() ?? '';
    final port = int.tryParse(data['port']?.toString() ?? '') ?? 0;

    if (server.isEmpty || port == 0) return;

    if (type == 'vmess') {
      final net = data['network']?.toString() ?? 'tcp';
      String headerType =
          data['obfs']?.toString() ?? data['type']?.toString() ?? 'none';
      if (net == 'kcp' || net == 'mkcp') {
        headerType =
            data['header']?.toString() ?? data['type']?.toString() ?? 'none';
      }

      nodes.add(
        NodeModel(
          id: _generateId(
            'clash-vmess',
            name,
            server,
            port,
            data['uuid']?.toString(),
          ),
          name: name,
          protocol: 'vmess',
          address: server,
          port: port,
          uuid: data['uuid']?.toString(),
          network: net,
          type: headerType,
          path:
              data['ws-path']?.toString() ??
              data['path']?.toString() ??
              data['seed']?.toString(),
          host: data['ws-headers']?.toString() ?? data['host']?.toString(),
          security: (data['tls']?.toString() == 'true') ? 'tls' : 'none',
          sni: data['sni']?.toString(),
          rawData: data,
        ),
      );
    } else if (type == 'vless') {
      final net = data['network']?.toString() ?? 'tcp';
      String headerType =
          data['obfs']?.toString() ?? data['type']?.toString() ?? 'none';
      if (net == 'kcp' || net == 'mkcp') {
        headerType =
            data['header']?.toString() ?? data['type']?.toString() ?? 'none';
      }

      nodes.add(
        NodeModel(
          id: _generateId(
            'clash-vless',
            name,
            server,
            port,
            data['uuid']?.toString(),
          ),
          name: name,
          protocol: 'vless',
          address: server,
          port: port,
          uuid: data['uuid']?.toString(),
          network: net,
          type: headerType,
          path:
              data['ws-path']?.toString() ??
              data['path']?.toString() ??
              data['seed']?.toString(),
          security: (data['tls']?.toString() == 'true') ? 'tls' : 'none',
          flow: data['flow']?.toString(),
          publicKey: data['reality-public-key']?.toString(),
          shortId: data['reality-short-id']?.toString(),
          sni: data['sni']?.toString(),
          rawData: data,
        ),
      );
    } else if (type == 'trojan') {
      final net = data['network']?.toString() ?? 'tcp';
      String headerType =
          data['obfs']?.toString() ?? data['type']?.toString() ?? 'none';
      if (net == 'kcp' || net == 'mkcp') {
        headerType =
            data['header']?.toString() ?? data['type']?.toString() ?? 'none';
      }

      nodes.add(
        NodeModel(
          id: _generateId('clash-trojan', name, server, port),
          name: name,
          protocol: 'trojan',
          address: server,
          port: port,
          password: data['password']?.toString(),
          sni: data['sni']?.toString(),
          security: 'tls',
          network: net,
          type: headerType,
          path:
              data['ws-path']?.toString() ??
              data['path']?.toString() ??
              data['seed']?.toString(),
          rawData: data,
        ),
      );
    } else if (type == 'ss' || type == 'shadowsocks') {
      nodes.add(
        NodeModel(
          id: _generateId('clash-ss', name, server, port),
          name: name,
          protocol: 'shadowsocks',
          address: server,
          port: port,
          method: data['cipher']?.toString(),
          password: data['password']?.toString(),
          network: data['network']?.toString() ?? 'tcp',
          path: data['ws-path']?.toString() ?? data['path']?.toString(),
          host: data['ws-headers']?.toString() ?? data['host']?.toString(),
          rawData: data,
        ),
      );
    } else if (type == 'wireguard') {
      nodes.add(
        NodeModel(
          id: _generateId('clash-wg', name, server, port),
          name: name,
          protocol: 'wireguard',
          address: server,
          port: port,
          wgSecretKey: data['private-key']?.toString(),
          wgPeerPublicKey: data['public-key']?.toString(),
          wgPreSharedKey: data['preshared-key']?.toString(),
          wgLocalAddress: data['ip']?.toString() != null
              ? [data['ip']!.toString()]
              : null,
          wgMtu: int.tryParse(data['mtu']?.toString() ?? ''),
          wgKeepAlive: int.tryParse(data['udp']?.toString() ?? ''),
          rawData: data,
        ),
      );
    } else if (type == 'hysteria2' || type == 'hy2') {
      nodes.add(
        NodeModel(
          id: _generateId('clash-hy2', name, server, port),
          name: name,
          protocol: 'hysteria2',
          address: server,
          port: port,
          password:
              data['auth-str']?.toString() ?? data['password']?.toString(),
          sni: data['sni']?.toString(),
          host: data['host']?.toString(),
          type: data['insecure']?.toString() == 'true' ? 'insecure' : null,
          rawData: data,
        ),
      );
    } else if (type == 'tuic') {
      nodes.add(
        NodeModel(
          id: _generateId('clash-tuic', name, server, port),
          name: name,
          protocol: 'tuic',
          address: server,
          port: port,
          uuid: data['uuid']?.toString(),
          password: data['password']?.toString(),
          sni: data['sni']?.toString(),
          network: data['alpn']?.toString(),
          rawData: data,
        ),
      );
    }
  }

  static List<NodeModel> _parseXrayJson(Map<String, dynamic> data) {
    final List<NodeModel> nodes = [];
    try {
      final List<dynamic> outbounds = data.containsKey('outbounds')
          ? data['outbounds']
          : [data];

      for (var outbound in outbounds) {
        if (outbound is! Map<String, dynamic>) continue;

        final protocol = outbound['protocol']?.toString().toLowerCase();
        if (protocol == null || protocol == 'direct' || protocol == 'block')
          continue;

        final settings = outbound['settings'] as Map<String, dynamic>?;
        final streamSettings =
            outbound['streamSettings'] as Map<String, dynamic>?;

        String address = '';
        int port = 0;
        String? uuid;
        String? password;
        String? username;
        String? encryption;

        if (protocol == 'vmess' || protocol == 'vless') {
          final vnext = settings?['vnext'] as List<dynamic>?;
          if (vnext != null && vnext.isNotEmpty) {
            final server = vnext[0] as Map<String, dynamic>;
            address = server['address']?.toString() ?? '';
            port = int.tryParse(server['port']?.toString() ?? '') ?? 0;
            final users = server['users'] as List<dynamic>?;
            if (users != null && users.isNotEmpty) {
              final user = users[0] as Map<String, dynamic>;
              uuid = user['id']?.toString();
              encryption =
                  user['security']?.toString() ??
                  user['encryption']?.toString();
            }
          }
        } else if (protocol == 'trojan' ||
            protocol == 'shadowsocks' ||
            protocol == 'ss' ||
            protocol == 'socks' ||
            protocol == 'http' ||
            protocol == 'hysteria2' ||
            protocol == 'tuic') {
          final servers = settings?['servers'] as List<dynamic>?;
          if (servers != null && servers.isNotEmpty) {
            final server = servers[0] as Map<String, dynamic>;
            address = server['address']?.toString() ?? '';
            port = int.tryParse(server['port']?.toString() ?? '') ?? 0;
            password = server['password']?.toString();
            username =
                server['user']?.toString() ?? server['username']?.toString();
            uuid = server['uuid']?.toString();
          }
        }

        if (address.isEmpty) continue;

        final network = streamSettings?['network']?.toString() ?? 'tcp';
        final security = streamSettings?['security']?.toString() ?? 'none';

        String? host;
        String? path;
        String? type;
        String? sni;

        if (network == 'ws') {
          final ws = streamSettings?['wsSettings'] as Map<String, dynamic>?;
          path = ws?['path']?.toString();
          host = ws?['headers']?['Host']?.toString();
        } else if (network == 'grpc') {
          final grpc = streamSettings?['grpcSettings'] as Map<String, dynamic>?;
          path = grpc?['serviceName']?.toString();
        } else if (network == 'kcp' || network == 'mkcp') {
          final kcp = streamSettings?['kcpSettings'] as Map<String, dynamic>?;
          path = kcp?['path']?.toString() ?? kcp?['seed']?.toString();
          type = kcp?['header']?['type']?.toString();
          final finalmask =
              streamSettings?['finalmask'] as Map<String, dynamic>?;
          if (finalmask != null && finalmask.containsKey('udp')) {
            final udp = finalmask['udp'];
            if (udp is List && udp.isNotEmpty) {
              final first = udp[0];
              if (first is Map) {
                type = first['type']?.toString() ?? first['header']?.toString();
                path = first['seed']?.toString();
              }
            } else if (udp is Map) {
              type = udp['type']?.toString() ?? udp['header']?.toString();
              path = udp['seed']?.toString();
            }
          }
        } else if (network == 'tcp') {
          final tcp = streamSettings?['tcpSettings'] as Map<String, dynamic>?;
          if (tcp?['header']?['type'] == 'http') {
            type = 'http';
            final request = tcp?['header']?['request'] as Map<String, dynamic>?;
            path = (request?['path'] as List?)?.first?.toString();
            host = (request?['headers']?['Host'] as List?)?.first?.toString();
          }
        }

        if (security == 'tls') {
          final tls = streamSettings?['tlsSettings'] as Map<String, dynamic>?;
          sni = tls?['serverName']?.toString();
        } else if (security == 'reality') {
          final reality =
              streamSettings?['realitySettings'] as Map<String, dynamic>?;
          sni = reality?['serverName']?.toString();
        }

        final name = outbound['tag']?.toString() ?? '$protocol-$address';

        nodes.add(
          NodeModel(
            id: _generateId(protocol, name, address, port, uuid ?? password),
            name: name,
            protocol: protocol,
            address: address,
            port: port,
            uuid: uuid,
            password: password,
            username: username,
            network: network,
            security: security,
            path: path,
            host: host,
            type: type,
            sni: sni,
            encryption: encryption,
            rawData: outbound,
          ),
        );
      }
    } catch (e) {
      print('Error parsing Xray JSON: $e');
    }
    return nodes;
  }
}
