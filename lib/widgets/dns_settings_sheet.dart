import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/localization_provider.dart';

class DnsSettingsSheet extends ConsumerStatefulWidget {
  final String remoteDns;
  final String domesticDns;
  final bool fakeDns;
  final bool enableLocalDns;
  final int localDnsPort;
  final bool enableIPv6;
  final String dnsHosts;
  final Function(
    String remoteDns,
    String domesticDns,
    bool fakeDns,
    bool enableLocalDns,
    int localDnsPort,
    bool enableIPv6,
    String dnsHosts,
  )
  onSave;

  const DnsSettingsSheet({
    super.key,
    required this.remoteDns,
    required this.domesticDns,
    required this.fakeDns,
    required this.enableLocalDns,
    required this.localDnsPort,
    required this.enableIPv6,
    required this.dnsHosts,
    required this.onSave,
  });

  @override
  ConsumerState<DnsSettingsSheet> createState() => _DnsSettingsSheetState();
}

class _DnsSettingsSheetState extends ConsumerState<DnsSettingsSheet> {
  late TextEditingController _remoteDnsController;
  late TextEditingController _domesticDnsController;
  late TextEditingController _localDnsPortController;
  late TextEditingController _dnsHostsController;
  late bool _fakeDns;
  late bool _enableLocalDns;
  late bool _enableIPv6;

  static const _presetRemoteDns = [
    {'label': 'Cloudflare', 'value': '1.1.1.1, 1.0.0.1'},
    {'label': 'Google', 'value': '8.8.8.8, 8.8.4.4'},
    {'label': 'Quad9', 'value': '9.9.9.9, 149.112.112.112'},
    {'label': 'OpenDNS', 'value': '208.67.222.222, 208.67.220.220'},
  ];

  static const _presetDomesticDns = [
    {'label': '阿里 DNS', 'value': '223.5.5.5, 223.6.6.6'},
    {'label': '腾讯 DNS', 'value': '1.12.12.12, 120.53.53.53'},
    {'label': '百度 DNS', 'value': '180.76.76.76, 114.114.114.114'},
  ];

  @override
  void initState() {
    super.initState();
    _remoteDnsController = TextEditingController(text: widget.remoteDns);
    _domesticDnsController = TextEditingController(text: widget.domesticDns);
    _localDnsPortController = TextEditingController(
      text: widget.localDnsPort.toString(),
    );
    _dnsHostsController = TextEditingController(text: widget.dnsHosts);
    _fakeDns = widget.fakeDns;
    _enableLocalDns = widget.enableLocalDns;
    _enableIPv6 = widget.enableIPv6;
  }

  @override
  void dispose() {
    _remoteDnsController.dispose();
    _domesticDnsController.dispose();
    _localDnsPortController.dispose();
    _dnsHostsController.dispose();
    super.dispose();
  }

  void _showPresetDnsDialog(bool isRemote) {
    final s = S.of(context, ref);
    final presets = isRemote ? _presetRemoteDns : _presetDomesticDns;
    final controller = isRemote ? _remoteDnsController : _domesticDnsController;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          s.get(isRemote ? 'remote_dns_preset' : 'domestic_dns_preset'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: presets.map((preset) {
            return ListTile(
              title: Text(preset['label']!),
              subtitle: Text(
                preset['value']!,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              onTap: () {
                controller.text = preset['value']!;
                Navigator.pop(context);
                setState(() {});
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('cancel')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context, ref);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  s.get('dns_settings'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(s.get('fake_dns')),
                  _buildCard(
                    children: [
                      _buildSwitchTile(
                        icon: Icons.flash_on_rounded,
                        title: s.get('enable_fake_dns'),
                        subtitle: s.get('fake_dns_desc'),
                        value: _fakeDns,
                        onChanged: (v) => setState(() => _fakeDns = v),
                      ),
                    ],
                  ),
                  _buildSectionTitle(s.get('remote_dns')),
                  _buildCard(
                    children: [
                      _buildTextFieldTile(
                        icon: Icons.public_rounded,
                        title: s.get('remote_dns'),
                        subtitle: s.get('remote_dns_desc'),
                        controller: _remoteDnsController,
                        hintText: '1.1.1.1, 8.8.8.8',
                        onPresetTap: () => _showPresetDnsDialog(true),
                      ),
                      const Divider(
                        height: 1,
                        indent: 56,
                        endIndent: 16,
                        color: Colors.white10,
                      ),
                      _buildSwitchTile(
                        icon: Icons.language_rounded,
                        title: s.get('enable_ipv6'),
                        subtitle: s.get('enable_ipv6_desc'),
                        value: _enableIPv6,
                        onChanged: (v) => setState(() => _enableIPv6 = v),
                      ),
                    ],
                  ),
                  _buildSectionTitle(s.get('domestic_dns')),
                  _buildCard(
                    children: [
                      _buildTextFieldTile(
                        icon: Icons.home_rounded,
                        title: s.get('domestic_dns'),
                        subtitle: s.get('domestic_dns_desc'),
                        controller: _domesticDnsController,
                        hintText: '223.5.5.5, 114.114.114.114',
                        onPresetTap: () => _showPresetDnsDialog(false),
                      ),
                    ],
                  ),
                  _buildSectionTitle(s.get('local_dns')),
                  _buildCard(
                    children: [
                      _buildSwitchTile(
                        icon: Icons.dns_rounded,
                        title: s.get('enable_local_dns'),
                        subtitle: s.get('enable_local_dns_desc'),
                        value: _enableLocalDns,
                        onChanged: (v) => setState(() => _enableLocalDns = v),
                      ),
                      if (_enableLocalDns) ...[
                        const Divider(
                          height: 1,
                          indent: 56,
                          endIndent: 16,
                          color: Colors.white10,
                        ),
                        _buildTextFieldTile(
                          icon: Icons.settings_ethernet_rounded,
                          title: s.get('local_dns_port'),
                          subtitle: s.get('local_dns_port_desc'),
                          controller: _localDnsPortController,
                          hintText: '10853',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ],
                    ],
                  ),
                  _buildSectionTitle(s.get('dns_hosts')),
                  _buildCard(
                    children: [
                      _buildTextFieldTile(
                        icon: Icons.edit_note_rounded,
                        title: s.get('dns_hosts'),
                        subtitle: s.get('dns_hosts_desc'),
                        controller: _dnsHostsController,
                        hintText: 'domain:address',
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withOpacity(0.8),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        widget.onSave(
                          _remoteDnsController.text,
                          _domesticDnsController.text,
                          _fakeDns,
                          _enableLocalDns,
                          int.tryParse(_localDnsPortController.text) ?? 10853,
                          _enableIPv6,
                          _dnsHostsController.text,
                        );
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        s.get('save'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 24, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: Colors.grey.shade400),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              onChanged: (v) {
                HapticFeedback.lightImpact();
                onChanged(v);
              },
              activeColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFieldTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    VoidCallback? onPresetTap,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: Colors.grey.shade400),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (onPresetTap != null)
                TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onPresetTap();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    S.of(context, ref).get('preset'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
