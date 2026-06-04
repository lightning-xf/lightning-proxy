import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lightning/core/node_model.dart';

class NodeEditDialog extends StatefulWidget {
  final NodeModel? node;
  final String? initialProtocol;

  const NodeEditDialog({super.key, this.node, this.initialProtocol});

  @override
  State<NodeEditDialog> createState() => _NodeEditDialogState();
}

class _NodeEditDialogState extends State<NodeEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _portController;
  late TextEditingController _uuidController;
  late TextEditingController _passwordController;
  late TextEditingController _usernameController;
  late TextEditingController _sniController;
  late TextEditingController _hostController;
  late TextEditingController _pathController;
  late TextEditingController _publicKeyController;
  late TextEditingController _shortIdController;
  late TextEditingController _spiderXController;
  late TextEditingController _serviceNameController;
  late TextEditingController _flowController;
  late TextEditingController _methodController;
  late TextEditingController _encryptionController;
  late TextEditingController _wgSecretKeyController;
  late TextEditingController _wgPeerPublicKeyController;
  late TextEditingController _wgPreSharedKeyController;
  late TextEditingController _wgLocalAddressController;
  late TextEditingController _wgMtuController;
  late TextEditingController _wgKeepAliveController;
  late TextEditingController _alpnController;
  late TextEditingController _concurrencyController;

  late String _protocol;
  late String _network;
  late String _security;
  late String _fingerprint;
  late String _type;
  late String _mode;
  late String _ssMethod;
  late String _vmessSecurity;
  late String _vlessEncryption;
  late bool _muxEnabled;

  @override
  void initState() {
    super.initState();
    final node = widget.node;
    _protocol = node?.protocol ?? widget.initialProtocol ?? 'vmess';
    _network = node?.network ?? 'tcp';
    _security = node?.security ?? 'none';
    _fingerprint = node?.fingerPrint ?? 'chrome';
    _type = node?.type ?? 'none';
    _mode = node?.mode ?? 'gun';
    _ssMethod = node?.method ?? 'aes-256-gcm';
    _vmessSecurity = node?.encryption ?? 'auto';
    _vlessEncryption = node?.encryption ?? 'none';
    _muxEnabled = node?.muxEnabled ?? false;
    _concurrencyController = TextEditingController(
      text: node?.muxConcurrency?.toString() ?? '8',
    );

    _nameController = TextEditingController(text: node?.name ?? '');
    _addressController = TextEditingController(text: node?.address ?? '');
    _portController = TextEditingController(
      text: node?.port?.toString() ?? '443',
    );
    _uuidController = TextEditingController(text: node?.uuid ?? '');
    _passwordController = TextEditingController(text: node?.password ?? '');
    _usernameController = TextEditingController(text: node?.username ?? '');
    _sniController = TextEditingController(text: node?.sni ?? '');
    _hostController = TextEditingController(text: node?.host ?? '');
    _pathController = TextEditingController(text: node?.path ?? '');
    _publicKeyController = TextEditingController(text: node?.publicKey ?? '');
    _shortIdController = TextEditingController(text: node?.shortId ?? '');
    _spiderXController = TextEditingController(text: node?.spiderX ?? '');
    _serviceNameController = TextEditingController(
      text: node?.serviceName ?? '',
    );
    _flowController = TextEditingController(text: node?.flow ?? '');
    _methodController = TextEditingController(text: _ssMethod);
    _encryptionController = TextEditingController(
      text: _protocol == 'vmess' ? _vmessSecurity : _vlessEncryption,
    );
    _wgSecretKeyController = TextEditingController(
      text: node?.wgSecretKey ?? '',
    );
    _wgPeerPublicKeyController = TextEditingController(
      text: node?.wgPeerPublicKey ?? '',
    );
    _wgPreSharedKeyController = TextEditingController(
      text: node?.wgPreSharedKey ?? '',
    );
    _wgLocalAddressController = TextEditingController(
      text: node?.wgLocalAddress?.join(',') ?? '10.0.0.2/32',
    );
    _wgMtuController = TextEditingController(
      text: node?.wgMtu?.toString() ?? '1420',
    );
    _wgKeepAliveController = TextEditingController(
      text: node?.wgKeepAlive?.toString() ?? '20',
    );
    _alpnController = TextEditingController(text: node?.alpn?.join(',') ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    _uuidController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _sniController.dispose();
    _hostController.dispose();
    _pathController.dispose();
    _publicKeyController.dispose();
    _shortIdController.dispose();
    _spiderXController.dispose();
    _serviceNameController.dispose();
    _flowController.dispose();
    _methodController.dispose();
    _encryptionController.dispose();
    _wgSecretKeyController.dispose();
    _wgPeerPublicKeyController.dispose();
    _wgPreSharedKeyController.dispose();
    _wgLocalAddressController.dispose();
    _wgMtuController.dispose();
    _wgKeepAliveController.dispose();
    _alpnController.dispose();
    _concurrencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AlertDialog(
        backgroundColor: isDark
            ? Colors.black.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.85),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        title: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              widget.node == null ? '添加节点' : '编辑节点',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('基本配置'),
                _buildDropdown<String>(
                  label: '协议',
                  value: _protocol,
                  items: [
                    'vmess',
                    'vless',
                    'trojan',
                    'shadowsocks',
                    'socks',
                    'http',
                    'hysteria2',
                    'tuic',
                    'wireguard',
                    'dokodemo-door',
                  ],
                  onChanged: (v) => setState(() {
                    _protocol = v!;
                    if (_protocol == 'wireguard') {
                      _network = 'udp';
                      _security = 'none';
                    }
                    if (_protocol == 'hysteria2' || _protocol == 'tuic') {
                      _network = 'quic';
                      _security = 'none'; // Protocol handles its own security
                    }
                  }),
                ),
                _buildTextField(
                  controller: _nameController,
                  label: '名称',
                  hint: '节点名称',
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTextField(
                        controller: _addressController,
                        label: '地址',
                        hint: '域名或IP',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildTextField(
                        controller: _portController,
                        label: '端口',
                        hint: '443',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),

                if (_protocol == 'vmess' || _protocol == 'vless')
                  _buildTextField(
                    controller: _uuidController,
                    label: 'UUID',
                    hint: 'User ID',
                  ),

                if (_protocol == 'vmess')
                  _buildDropdown<String>(
                    label: '加密方式 (Security)',
                    value: _vmessSecurity,
                    items: {
                      'auto',
                      'aes-128-gcm',
                      'chacha20-poly1305',
                      'none',
                      'zero',
                      _vmessSecurity,
                    }.toList(),
                    onChanged: (v) => setState(() => _vmessSecurity = v!),
                  ),

                if (_protocol == 'vless')
                  _buildDropdown<String>(
                    label: '加密 (Encryption)',
                    value: _vlessEncryption,
                    items: {'none', _vlessEncryption}.toList(),
                    onChanged: (v) => setState(() => _vlessEncryption = v!),
                  ),

                if (_protocol == 'trojan' ||
                    _protocol == 'shadowsocks' ||
                    _protocol == 'socks' ||
                    _protocol == 'http')
                  _buildTextField(
                    controller: _passwordController,
                    label: '密码',
                    hint: 'Password',
                  ),

                if (_protocol == 'socks' || _protocol == 'http')
                  _buildTextField(
                    controller: _usernameController,
                    label: '用户名',
                    hint: 'Optional',
                  ),

                if (_protocol == 'shadowsocks')
                  _buildDropdown<String>(
                    label: '加密方法 (Method)',
                    value: _ssMethod,
                    items: [
                      'aes-128-gcm',
                      'aes-192-gcm',
                      'aes-256-gcm',
                      'chacha20-ietf-poly1305',
                      'xchacha20-ietf-poly1305',
                      '2022-blake3-aes-128-gcm',
                      '2022-blake3-aes-256-gcm',
                      '2022-blake3-chacha20-poly1305',
                      if (![
                        'aes-128-gcm',
                        'aes-192-gcm',
                        'aes-256-gcm',
                        'chacha20-ietf-poly1305',
                        'xchacha20-ietf-poly1305',
                        '2022-blake3-aes-128-gcm',
                        '2022-blake3-aes-256-gcm',
                        '2022-blake3-chacha20-poly1305',
                      ].contains(_ssMethod))
                        _ssMethod,
                    ],
                    onChanged: (v) => setState(() => _ssMethod = v!),
                  ),

                if (_protocol == 'vless')
                  _buildTextField(
                    controller: _flowController,
                    label: '流控 (Flow)',
                    hint: 'xtls-rprx-vision',
                  ),

                if (_protocol == 'hysteria2') ...[
                  _buildTextField(
                    controller: _passwordController,
                    label: '密码 (Auth)',
                    hint: 'Auth/Password',
                  ),
                  _buildTextField(
                    controller: _hostController,
                    label: '伪装域名 (SNI)',
                    hint: 'Optional',
                  ),
                  _buildDropdown<String>(
                    label: '允许不安全连接 (Insecure)',
                    value: _type == 'insecure' ? 'true' : 'false',
                    items: ['true', 'false'],
                    onChanged: (v) => setState(
                      () => _type = v == 'true' ? 'insecure' : 'none',
                    ),
                  ),
                ],

                if (_protocol == 'tuic') ...[
                  _buildTextField(
                    controller: _uuidController,
                    label: 'UUID',
                    hint: 'User ID',
                  ),
                  _buildTextField(
                    controller: _passwordController,
                    label: '密码',
                    hint: 'Password',
                  ),
                  _buildTextField(
                    controller: _sniController,
                    label: 'SNI',
                    hint: 'Optional',
                  ),
                  _buildDropdown<String>(
                    label: 'UDP 转发模式',
                    value: _mode == 'multi' ? 'multi' : 'gun',
                    items: ['gun', 'multi'],
                    onChanged: (v) => setState(() => _mode = v!),
                  ),
                ],

                if (_protocol == 'wireguard') ...[
                  _buildTextField(
                    controller: _wgSecretKeyController,
                    label: '私钥 (Secret Key)',
                    hint: 'WireGuard Private Key',
                  ),
                  _buildTextField(
                    controller: _wgPeerPublicKeyController,
                    label: '对端公钥 (Peer Public Key)',
                    hint: 'WireGuard Peer Public Key',
                  ),
                  _buildTextField(
                    controller: _wgPreSharedKeyController,
                    label: '预共享密钥 (Pre-shared Key)',
                    hint: 'Optional',
                  ),
                  _buildTextField(
                    controller: _wgLocalAddressController,
                    label: '本地地址',
                    hint: '10.0.0.2/32',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _wgMtuController,
                          label: 'MTU',
                          hint: '1420',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _wgKeepAliveController,
                          label: '保活间隔',
                          hint: '20',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                _buildSectionTitle('传输配置'),
                _buildDropdown<String>(
                  label: '传输方式',
                  value: _network,
                  items: {
                    'tcp',
                    'ws',
                    'grpc',
                    'h2',
                    'kcp',
                    'mkcp',
                    'quic',
                    'xhttp',
                    'httpupgrade',
                    'split-http',
                    _network,
                  }.toList(),
                  onChanged: (v) => setState(() => _network = v!),
                ),

                if (_network == 'tcp') ...[
                  _buildDropdown<String>(
                    label: '伪装类型 (Header Type)',
                    value: _type,
                    items: {'none', 'http', _type}.toList(),
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                  if (_type == 'http') ...[
                    _buildTextField(
                      controller: _hostController,
                      label: '伪装域名 (Host)',
                      hint: 'Optional',
                    ),
                    _buildTextField(
                      controller: _pathController,
                      label: '路径 (Path)',
                      hint: '/',
                    ),
                  ],
                ],

                if (_network == 'ws' ||
                    _network == 'h2' ||
                    _network == 'httpupgrade' ||
                    _network == 'split-http' ||
                    _network == 'quic' ||
                    _network == 'xhttp') ...[
                  _buildTextField(
                    controller: _hostController,
                    label: '伪装域名 (Host)',
                    hint: 'Optional',
                  ),
                  _buildTextField(
                    controller: _pathController,
                    label: '路径 (Path)',
                    hint: '/',
                  ),
                ],

                if (_network == 'grpc') ...[
                  _buildTextField(
                    controller: _serviceNameController,
                    label: '服务名称',
                    hint: 'grpc service name',
                  ),
                  _buildDropdown<String>(
                    label: 'gRPC 模式',
                    value: _mode,
                    items: ['gun', 'multi'],
                    onChanged: (v) => setState(() => _mode = v!),
                  ),
                ],

                if (_network == 'kcp' || _network == 'mkcp') ...[
                  _buildTextField(
                    controller: _pathController,
                    label: '混淆种子 (Finalmask/Seed)',
                    hint: 'Optional',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: TextEditingController(text: '1350'),
                          label: 'MTU',
                          hint: '1350',
                          keyboardType: TextInputType.number,
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: TextEditingController(text: '20'),
                          label: 'TTI',
                          hint: '20',
                          keyboardType: TextInputType.number,
                          readOnly: true,
                        ),
                      ),
                    ],
                  ),
                  _buildDropdown<String>(
                    label: '伪装类型 (Header Type)',
                    value: _type,
                    items: {
                      'none',
                      'srtp',
                      'utp',
                      'wechat-video',
                      'dtls',
                      'wireguard',
                      'mkcp-original',
                      'mkcp-aes128gcm',
                      _type,
                    }.toList(),
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ],

                if (_protocol == 'vmess' ||
                    _protocol == 'vless' ||
                    _protocol == 'trojan' ||
                    _protocol == 'shadowsocks') ...[
                  const SizedBox(height: 16),
                  _buildSectionTitle('安全配置'),
                  _buildDropdown<String>(
                    label: '底层传输安全 (Security)',
                    value: _security,
                    items: {'none', 'tls', 'reality', _security}.toList(),
                    onChanged: (v) => setState(() => _security = v!),
                  ),
                  if (_security != 'none') ...[
                    _buildTextField(
                      controller: _sniController,
                      label: 'SNI',
                      hint: 'Server Name Indication',
                    ),
                    _buildDropdown<String>(
                      label: '指纹 (Fingerprint)',
                      value: _fingerprint,
                      items: {
                        'chrome',
                        'firefox',
                        'safari',
                        'ios',
                        'android',
                        'edge',
                        'random',
                        'randomized',
                        _fingerprint,
                      }.toList(),
                      onChanged: (v) => setState(() => _fingerprint = v!),
                    ),
                    _buildTextField(
                      controller: _alpnController,
                      label: 'ALPN (以逗号分隔)',
                      hint: 'h2,http/1.1',
                    ),
                  ],
                  if (_security == 'reality') ...[
                    _buildTextField(
                      controller: _publicKeyController,
                      label: 'Reality Public Key',
                      hint: 'Public Key',
                    ),
                    _buildTextField(
                      controller: _shortIdController,
                      label: 'Reality Short ID',
                      hint: 'Optional',
                    ),
                    _buildTextField(
                      controller: _spiderXController,
                      label: 'SpiderX',
                      hint: 'Optional',
                    ),
                  ],
                ],

                if (_protocol == 'vmess' ||
                    _protocol == 'vless' ||
                    _protocol == 'trojan') ...[
                  const SizedBox(height: 16),
                  _buildSectionTitle('Mux 配置'),
                  SwitchListTile(
                    title: const Text(
                      '启用 Mux',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: _muxEnabled,
                    onChanged: (v) => setState(() => _muxEnabled = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_muxEnabled)
                    _buildTextField(
                      controller: _concurrencyController,
                      label: '并发数 (Concurrency)',
                      hint: '8',
                      keyboardType: TextInputType.number,
                    ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              '保存',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            readOnly: readOnly,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.grey.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey,
                ),
                onChanged: onChanged,
                items: items.map((T item) {
                  return DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      item.toString().toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final Map<String, dynamic> updatedRawData = widget.node?.rawData != null
        ? Map<String, dynamic>.from(widget.node!.rawData!)
        : {};

    // Synchronize rawData with current UI values to ensure edits are reflected in exports
    if (_protocol == 'vmess') {
      updatedRawData['ps'] = _nameController.text;
      updatedRawData['add'] = _addressController.text;
      updatedRawData['port'] = int.tryParse(_portController.text) ?? 443;
      updatedRawData['id'] = _uuidController.text;
      updatedRawData['net'] = _network;
      updatedRawData['scy'] = _vmessSecurity;
      updatedRawData['sni'] = _sniController.text;
      updatedRawData['host'] = _hostController.text;
      updatedRawData['path'] = _pathController.text;
      updatedRawData['tls'] = _security == 'tls' ? 'tls' : '';
      updatedRawData['type'] = _type;
      if (_security == 'reality') {
        updatedRawData['fp'] = _fingerprint;
        updatedRawData['pbk'] = _publicKeyController.text;
        updatedRawData['sid'] = _shortIdController.text;
        updatedRawData['spx'] = _spiderXController.text;
      }
    } else {
      // For VLESS/Trojan/SS/Hysteria2/TUIC, rawData is usually query params
      updatedRawData['type'] = _network;
      updatedRawData['security'] = _security;
      updatedRawData['sni'] = _sniController.text;
      updatedRawData['host'] = _hostController.text;
      updatedRawData['path'] = _pathController.text;
      updatedRawData['headerType'] = _type;

      if (_protocol == 'vless') {
        updatedRawData['encryption'] = _vlessEncryption;
        updatedRawData['flow'] = _flowController.text;
      }
      if (_protocol == 'shadowsocks') {
        updatedRawData['method'] = _ssMethod;
      }
      if (_protocol == 'hysteria2') {
        updatedRawData['insecure'] = _type == 'insecure' ? '1' : '0';
      }
      if (_security == 'reality') {
        updatedRawData['fp'] = _fingerprint;
        updatedRawData['pbk'] = _publicKeyController.text;
        updatedRawData['sid'] = _shortIdController.text;
        updatedRawData['spx'] = _spiderXController.text;
      }
      if (_alpnController.text.isNotEmpty) {
        updatedRawData['alpn'] = _alpnController.text;
      }
    }

    final newNode = NodeModel(
      id: widget.node?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.isEmpty ? 'New Node' : _nameController.text,
      protocol: _protocol,
      address: _addressController.text,
      port: int.tryParse(_portController.text) ?? 443,
      uuid: _uuidController.text,
      password: _passwordController.text,
      username: _usernameController.text,
      security: _security,
      network: _network,
      sni: _sniController.text,
      host: _hostController.text,
      path: _pathController.text,
      type: _type,
      publicKey: _publicKeyController.text,
      fingerPrint: _fingerprint,
      shortId: _shortIdController.text,
      spiderX: _spiderXController.text,
      flow: _flowController.text,
      method: _protocol == 'shadowsocks' ? _ssMethod : _methodController.text,
      serviceName: _serviceNameController.text,
      mode: _mode,
      encryption: _protocol == 'vmess'
          ? _vmessSecurity
          : (_protocol == 'vless'
                ? _vlessEncryption
                : _encryptionController.text),
      wgSecretKey: _wgSecretKeyController.text,
      wgLocalAddress: _wgLocalAddressController.text.isNotEmpty
          ? _wgLocalAddressController.text.split(',')
          : null,
      wgPeerPublicKey: _wgPeerPublicKeyController.text,
      wgPreSharedKey: _wgPreSharedKeyController.text.isNotEmpty
          ? _wgPreSharedKeyController.text
          : null,
      wgMtu: int.tryParse(_wgMtuController.text),
      wgKeepAlive: int.tryParse(_wgKeepAliveController.text),
      alpn: _alpnController.text.isNotEmpty
          ? _alpnController.text.split(',').map((e) => e.trim()).toList()
          : null,
      muxEnabled: _muxEnabled,
      muxConcurrency: int.tryParse(_concurrencyController.text) ?? 8,
      rawData: updatedRawData,
      isFavorite: widget.node?.isFavorite ?? false,
      latency: widget.node?.latency,
    );
    Navigator.pop(context, newNode);
  }
}
