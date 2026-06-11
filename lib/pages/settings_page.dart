import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/proxy_channel.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/main.dart';
import 'package:lightning/pages/routing_page.dart';
import 'package:lightning/pages/app_splitting_page.dart';
import 'package:lightning/pages/proxy_group_page.dart';
import 'package:lightning/pages/rule_set_page.dart';
import 'package:lightning/widgets/dns_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class VpnSettings {
  final int socksPort;
  final int httpPort;
  final String dns;
  final bool fakeDns;
  final String remoteDns;
  final String domesticDns;
  final bool enableLocalDns;
  final int localDnsPort;
  final bool enableIPv6;
  final String dnsHosts;
  final bool bypassLocal;
  final String logLevel;
  final bool autoStart;
  final bool keepAlive;
  final bool autoReconnect;
  final bool showTraffic;
  final VpnMode mode;
  final bool bypassApps;
  final bool muxEnabled;
  final String tcpCongestion;
  final bool allowLan;
  final bool useProxyGroup;
  // Mux 高级参数
  final int muxConcurrency;
  final bool muxPadding;
  final String muxProtocol;

  VpnSettings({
    this.socksPort = 10808,
    this.httpPort = 10809,
    this.dns = '8.8.8.8, 1.1.1.1',
    this.fakeDns = true,
    this.remoteDns = '1.1.1.1, 1.0.0.1',
    this.domesticDns = '223.5.5.5, 223.6.6.6',
    this.enableLocalDns = false,
    this.localDnsPort = 10853,
    this.enableIPv6 = true,
    this.dnsHosts = '',
    this.bypassLocal = true,
    this.logLevel = 'info',
    this.autoStart = true,
    this.keepAlive = true,
    this.autoReconnect = true,
    this.showTraffic = true,
    this.mode = VpnMode.rule,
    this.bypassApps = false,
    this.muxEnabled = false,
    this.tcpCongestion = 'bbr',
    this.allowLan = false,
    this.useProxyGroup = false,
    // Mux 默认参数
    this.muxConcurrency = 8,
    this.muxPadding = true,
    this.muxProtocol = 'h2',
  });

  VpnSettings copyWith({
    int? socksPort,
    int? httpPort,
    String? dns,
    bool? fakeDns,
    String? remoteDns,
    String? domesticDns,
    bool? enableLocalDns,
    int? localDnsPort,
    bool? enableIPv6,
    String? dnsHosts,
    bool? bypassLocal,
    String? logLevel,
    bool? autoStart,
    bool? keepAlive,
    bool? autoReconnect,
    bool? showTraffic,
    VpnMode? mode,
    bool? bypassApps,
    bool? muxEnabled,
    String? tcpCongestion,
    bool? allowLan,
    bool? useProxyGroup,
    // Mux 参数
    int? muxConcurrency,
    bool? muxPadding,
    String? muxProtocol,
  }) {
    return VpnSettings(
      socksPort: socksPort ?? this.socksPort,
      httpPort: httpPort ?? this.httpPort,
      dns: dns ?? this.dns,
      fakeDns: fakeDns ?? this.fakeDns,
      remoteDns: remoteDns ?? this.remoteDns,
      domesticDns: domesticDns ?? this.domesticDns,
      enableLocalDns: enableLocalDns ?? this.enableLocalDns,
      localDnsPort: localDnsPort ?? this.localDnsPort,
      enableIPv6: enableIPv6 ?? this.enableIPv6,
      dnsHosts: dnsHosts ?? this.dnsHosts,
      bypassLocal: bypassLocal ?? this.bypassLocal,
      logLevel: logLevel ?? this.logLevel,
      autoStart: autoStart ?? this.autoStart,
      keepAlive: keepAlive ?? this.keepAlive,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      showTraffic: showTraffic ?? this.showTraffic,
      mode: mode ?? this.mode,
      bypassApps: bypassApps ?? this.bypassApps,
      muxEnabled: muxEnabled ?? this.muxEnabled,
      tcpCongestion: tcpCongestion ?? this.tcpCongestion,
      allowLan: allowLan ?? this.allowLan,
      useProxyGroup: useProxyGroup ?? this.useProxyGroup,
      muxConcurrency: muxConcurrency ?? this.muxConcurrency,
      muxPadding: muxPadding ?? this.muxPadding,
      muxProtocol: muxProtocol ?? this.muxProtocol,
    );
  }

  Map<String, dynamic> toJson() => {
    'socks_port': socksPort,
    'http_port': httpPort,
    'dns': dns,
    'fake_dns': fakeDns,
    'remote_dns': remoteDns,
    'domestic_dns': domesticDns,
    'enable_local_dns': enableLocalDns,
    'local_dns_port': localDnsPort,
    'enable_ipv6': enableIPv6,
    'dns_hosts': dnsHosts,
    'bypass_local': bypassLocal,
    'log_level': logLevel,
    'auto_start': autoStart,
    'keep_alive': keepAlive,
    'auto_reconnect': autoReconnect,
    'show_traffic': showTraffic,
    'vpn_mode': mode.index,
    'bypass_apps': bypassApps,
    'mux_enabled': muxEnabled,
    'tcp_congestion': tcpCongestion,
    'allow_lan': allowLan,
    'use_proxy_group': useProxyGroup,
    'mux_concurrency': muxConcurrency,
    'mux_padding': muxPadding,
    'mux_protocol': muxProtocol,
  };

  factory VpnSettings.fromJson(Map<String, dynamic> json) => VpnSettings(
    socksPort: json['socks_port'] ?? 10808,
    httpPort: json['http_port'] ?? 10809,
    dns: json['dns'] ?? '8.8.8.8, 1.1.1.1',
    fakeDns: json['fake_dns'] ?? true,
    remoteDns: json['remote_dns'] ?? '1.1.1.1, 1.0.0.1',
    domesticDns: json['domestic_dns'] ?? '223.5.5.5, 223.6.6.6',
    enableLocalDns: json['enable_local_dns'] ?? false,
    localDnsPort: json['local_dns_port'] ?? 10853,
    enableIPv6: json['enable_ipv6'] ?? true,
    dnsHosts: json['dns_hosts'] ?? '',
    bypassLocal: json['bypass_local'] ?? true,
    logLevel: json['log_level'] ?? 'info',
    autoStart: json['auto_start'] ?? true,
    keepAlive: json['keep_alive'] ?? true,
    autoReconnect: json['auto_reconnect'] ?? true,
    showTraffic: json['show_traffic'] ?? true,
    mode: VpnMode.values[json['vpn_mode'] ?? VpnMode.rule.index],
    bypassApps: json['bypass_apps'] ?? false,
    muxEnabled: json['mux_enabled'] ?? false,
    tcpCongestion: json['tcp_congestion'] ?? 'bbr',
    allowLan: json['allow_lan'] ?? false,
    useProxyGroup: json['use_proxy_group'] ?? false,
    muxConcurrency: json['mux_concurrency'] ?? 8,
    muxPadding: json['mux_padding'] ?? true,
    muxProtocol: json['mux_protocol'] ?? 'h2',
  );
}

class VpnSettingsNotifier extends StateNotifier<VpnSettings> {
  VpnSettingsNotifier() : super(VpnSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('vpn_settings');
    if (json != null) {
      state = VpnSettings.fromJson(jsonDecode(json));
    }
  }

  Future<void> update(VpnSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vpn_settings', jsonEncode(settings.toJson()));

    // Sync to Android native prefs for BootReceiver and Notification
    await ProxyChannel.updateSettings(
      autoStart: settings.autoStart,
      autoReconnect: settings.autoReconnect,
      showTraffic: settings.showTraffic,
    );
  }
}

final vpnSettingsProvider =
    StateNotifierProvider<VpnSettingsNotifier, VpnSettings>((ref) {
      return VpnSettingsNotifier();
    });

final coreVersionProvider = FutureProvider<String>((ref) async {
  return await ProxyChannel.getCoreVersion();
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localizationProvider);
    final s = S.of(context, ref);
    final vpnSettings = ref.watch(vpnSettingsProvider);
    final coreVersion = ref.watch(coreVersionProvider);
    final theme = Theme.of(context);
    final bool isMobile = MediaQuery.of(context).size.width < 720;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: isMobile
          ? AppBar(
              leading: IconButton(
                icon: Icon(
                  Icons.menu_rounded,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Scaffold.of(context).openDrawer();
                },
              ),
              centerTitle: true,
              title: Text(
                s.get('advanced_config'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          if (!isMobile) _buildHeader(context, ref, s, theme, isMobile),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                  _buildSettingTile(
                    context,
                    Icons.palette_rounded,
                    s.get('appearance'),
                    themeMode == ThemeMode.dark
                        ? s.get('dark_mode')
                        : s.get('light_mode'),
                    s,
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.language_rounded,
                    s.get('language'),
                    locale.languageCode == 'zh' ? '简体中文' : 'English',
                    s,
                    onTap: () => _showLanguagePicker(context, ref, s),
                    helpText: s.get('language_help'),
                  ),
                _buildSection(context, s.get('conn_automation'), [
                  _buildSwitchTile(
                    context,
                    Icons.power_settings_new_rounded,
                    s.get('auto_start'),
                    s.get('auto_start_desc'),
                    vpnSettings.autoStart,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(autoStart: v)),
                    s,
                    helpText: s.get('auto_start_help'),
                  ),
                  _buildSwitchTile(
                    context,
                    Icons.verified_user_rounded,
                    s.get('keep_alive'),
                    s.get('keep_alive_desc'),
                    vpnSettings.keepAlive,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(keepAlive: v)),
                    s,
                    helpText: s.get('keep_alive_help'),
                  ),
                  _buildSwitchTile(
                    context,
                    Icons.refresh_rounded,
                    s.get('auto_reconnect'),
                    s.get('auto_reconnect_desc'),
                    vpnSettings.autoReconnect,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(autoReconnect: v)),
                    s,
                    helpText: s.get('auto_reconnect_help'),
                  ),
                  _buildSwitchTile(
                    context,
                    Icons.speed_rounded,
                    s.get('show_traffic'),
                    s.get('show_traffic_desc'),
                    vpnSettings.showTraffic,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(showTraffic: v)),
                    s,
                    helpText: s.get('show_traffic_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.battery_saver_rounded,
                    s.get('ignore_battery'),
                    s.get('ignore_battery_desc'),
                    s,
                    onTap: () => ProxyChannel.requestBatteryOptimization(),
                    helpText: s.get('ignore_battery_help'),
                  ),
                ]),
                _buildSection(context, s.get('route_splitting'), [
                  _buildSwitchTile(
                    context,
                    Icons.group_work_rounded,
                    s.get('use_proxy_group'),
                    s.get('use_proxy_group_desc'),
                    vpnSettings.useProxyGroup,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(useProxyGroup: v)),
                    s,
                    helpText: s.get('use_proxy_group_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.account_tree_rounded,
                    s.get('proxy_group'),
                    s.get('proxy_group_desc'),
                    s,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProxyGroupPage()),
                    ),
                    helpText: s.get('proxy_group_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.list_alt_rounded,
                    s.get('rule_sets'),
                    s.get('create_rule_set_hint'),
                    s,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RuleSetPage()),
                    ),
                    helpText: s.get('rule_set_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.alt_route_rounded,
                    s.get('routing_strategy'),
                    '${s.get('routing_strategy_desc')}${_getModeName(vpnSettings.mode, s)}',
                    s,
                    onTap: () => _showModePicker(context, ref, vpnSettings, s),
                    helpText: s.get('routing_strategy_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.rule_rounded,
                    s.get('rules_manage'),
                    s.get('rules_manage_desc'),
                    s,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RoutingPage()),
                    ),
                    helpText: s.get('routing_rules_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.apps_rounded,
                    s.get('app_split'),
                    s.get('app_split_desc'),
                    s,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AppSplittingPage(),
                      ),
                    ),
                    helpText: s.get('app_splitting_help'),
                  ),
                  _buildSwitchTile(
                    context,
                    Icons.lan_rounded,
                    s.get('bypass_local'),
                    s.get('bypass_local_desc'),
                    vpnSettings.bypassLocal,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(bypassLocal: v)),
                    s,
                    helpText: s.get('bypass_local_help'),
                  ),
                  _buildAllowLanTile(context, ref, vpnSettings, s),
                ]),
                _buildSection(context, s.get('protocol_kernel'), [
                  _buildSettingTile(
                    context,
                    Icons.memory_rounded,
                    s.get('kernel_info'),
                    coreVersion.when(
                      data: (v) => 'Xray-Core $v',
                      loading: () => '...',
                      error: (_, __) => 'Xray-Core Unknown',
                    ),
                    s,
                    onTap: null,
                    helpText: s.get('kernel_info_help'),
                  ),
                  _buildDropdownTile<String>(
                    context,
                    Icons.bug_report_rounded,
                    s.get('log_level'),
                    vpnSettings.logLevel.toUpperCase(),
                    ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'NONE'],
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(
                          vpnSettings.copyWith(logLevel: v.toLowerCase()),
                        ),
                    s,
                    helpText: s.get('log_level_help'),
                  ),
                  _buildSwitchTile(
                    context,
                    Icons.bolt_rounded,
                    s.get('mux_enabled'),
                    s.get('mux_enabled_desc'),
                    vpnSettings.muxEnabled,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(muxEnabled: v)),
                    s,
                    helpText: s.get('mux_enabled_help'),
                  ),
                  // Mux 高级设置
                  _buildSettingTile(
                    context,
                    Icons.tune_rounded,
                    s.get('mux_advanced'),
                    '${s.get('mux_concurrency')}: ${vpnSettings.muxConcurrency}, ${s.get('protocol')}: ${vpnSettings.muxProtocol.toUpperCase()}',
                    s,
                    onTap: vpnSettings.muxEnabled
                        ? () => _showMuxAdvancedDialog(context, ref, vpnSettings, s)
                        : null,
                    helpText: s.get('mux_advanced_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.speed_rounded,
                    s.get('tcp_congestion'),
                    '${s.get('tcp_congestion_desc')}${vpnSettings.tcpCongestion.toUpperCase()}',
                    s,
                    onTap: () =>
                        _showTcpCongestionDialog(context, ref, vpnSettings, s),
                    helpText: s.get('tcp_congestion_help'),
                  ),
                ]),
                _buildSection(context, s.get('adv_network'), [
                  _buildSettingTile(
                    context,
                    Icons.settings_ethernet_rounded,
                    s.get('inbound_ports'),
                    'Socks: ${vpnSettings.socksPort} | HTTP: ${vpnSettings.httpPort}',
                    s,
                    onTap: () => _showPortsDialog(context, ref, vpnSettings, s),
                    helpText: s.get('inbound_ports_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.dns_rounded,
                    s.get('dns_settings'),
                    s.get('remote_dns'),
                    s,
                    onTap: () =>
                        _showDnsSettingsSheet(context, ref, vpnSettings),
                    helpText: s.get('dns_settings_help'),
                  ),
                ]),
                _buildSection(context, s.get('backup_restore'), [
                  _buildSettingTile(
                    context,
                    Icons.cloud_sync_rounded,
                    s.get('backup_restore'),
                    s.get('backup_restore_desc'),
                    s,
                    onTap: () => _showBackupRestoreDialog(context, ref, s),
                    helpText: s.get('backup_restore_help'),
                  ),
                  _buildSettingTile(
                    context,
                    Icons.info_rounded,
                    s.get('about'),
                    s.get('about_desc'),
                    s,
                    onTap: () => _showAboutDialog(context, s),
                    helpText: s.get('about_help'),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownTile<T>(
    BuildContext context,
    IconData icon,
    String title,
    String currentDisplay,
    List<T> options,
    ValueChanged<T> onChanged,
    S s, {
    String? helpText,
    VoidCallback? helpTextOnTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: Colors.grey.shade400),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (helpText != null || helpTextOnTap != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap:
                      helpTextOnTap ??
                      () => _showHelpDialog(context, title, helpText!, s),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.5),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            currentDisplay,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: PopupMenuButton<T>(
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.grey.shade700,
            ),
            onSelected: (value) {
              HapticFeedback.lightImpact();
              onChanged(value);
            },
            itemBuilder: (context) => options
                .map(
                  (o) => PopupMenuItem<T>(value: o, child: Text(o.toString())),
                )
                .toList(),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    S s,
    ThemeData theme,
    bool isMobile,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            s.get('advanced_config'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getLocalIp() async {
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) return wifiIP;

      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '192.168.x.x';
  }

  Widget _buildAllowLanTile(
    BuildContext context,
    WidgetRef ref,
    VpnSettings vpnSettings,
    S s,
  ) {
    return _buildSwitchTile(
      context,
      Icons.share_rounded,
      s.get('allow_lan'),
      s.get('allow_lan_desc'),
      vpnSettings.allowLan,
      (v) => ref
          .read(vpnSettingsProvider.notifier)
          .update(vpnSettings.copyWith(allowLan: v)),
      s,
      helpTextOnTap: () async {
        final ip = await _getLocalIp();
        final port = vpnSettings.httpPort.toString();
        if (context.mounted) {
          _showHelpDialog(
            context,
            s.get('allow_lan'),
            s
                .get('allow_lan_help')
                .replaceAll('{ip}', ip)
                .replaceAll('{port}', port),
            s,
          );
        }
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
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
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    S s, {
    VoidCallback? onTap,
    String? helpText,
    VoidCallback? helpTextOnTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
        child: ListTile(
          onTap: onTap != null
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: Colors.grey.shade400),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (helpText != null || helpTextOnTap != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap:
                      helpTextOnTap ??
                      () => _showHelpDialog(context, title, helpText!, s),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.5),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: onTap != null
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade700,
                  size: 18,
                )
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    S s, {
    String? helpText,
    VoidCallback? helpTextOnTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: Colors.grey.shade400),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (helpText != null || helpTextOnTap != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap:
                      helpTextOnTap ??
                      () => _showHelpDialog(context, title, helpText!, s),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.5),
                  ),
                ),
              ],
            ],
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context, String title, String content, S s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showKeepAliveGuide(BuildContext context, S s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('keep_alive_guide')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.get('keep_alive_guide_content')),
            const SizedBox(height: 16),
            Text('1. ${s.get('keep_alive_step1')}'),
            Text('2. ${s.get('keep_alive_step2')}'),
            Text('3. ${s.get('keep_alive_step3')}'),
            Text('4. ${s.get('keep_alive_step4')}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // ProxyChannel.openSystemSettings();
            },
            child: Text(s.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, S s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('简体中文'),
              value: 'zh',
              groupValue: ref.watch(localizationProvider).languageCode,
              onChanged: (v) {
                ref
                    .read(localizationProvider.notifier)
                    .setLocale(const Locale('zh', 'CN'));
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('English'),
              value: 'en',
              groupValue: ref.watch(localizationProvider).languageCode,
              onChanged: (v) {
                ref
                    .read(localizationProvider.notifier)
                    .setLocale(const Locale('en', 'US'));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTcpCongestionDialog(
    BuildContext context,
    WidgetRef ref,
    VpnSettings settings,
    S s,
  ) {
    final algos = ['bbr', 'cubic', 'reno'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('tcp_congestion')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: algos
              .map(
                (a) => RadioListTile<String>(
                  title: Text(a.toUpperCase()),
                  value: a,
                  groupValue: settings.tcpCongestion,
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .update(settings.copyWith(tcpCongestion: v));
                    }
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _showBackupRestoreDialog(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          s.get('backup_restore'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBackupOptionCard(
              context: context,
              icon: Icons.cloud_upload_rounded,
              title: s.get('backup_export'),
              subtitle: 'Backup Config (Export)',
              primaryColor: Colors.green,
              onTap: () async {
                Navigator.pop(context);
                await _exportConfig(context, ref, s);
              },
            ),
            const SizedBox(height: 12),
            _buildBackupOptionCard(
              context: context,
              icon: Icons.cloud_download_rounded,
              title: s.get('backup_import'),
              subtitle: 'Restore Config (Import)',
              primaryColor: theme.colorScheme.primary,
              onTap: () async {
                Navigator.pop(context);
                await _importConfig(context, ref, s);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              s.get('cancel'),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupOptionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color primaryColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: primaryColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Colors.grey[500],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportConfig(BuildContext context, WidgetRef ref, S s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> config = {};
      for (final key in prefs.getKeys()) {
        config[key] = prefs.get(key);
      }
      final jsonStr = jsonEncode(config);
      final encoded = base64Encode(utf8.encode(jsonStr));
      await Clipboard.setData(ClipboardData(text: 'LIGHTNING_CONFIG:$encoded'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('backup_success')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('backup_fail').replaceAll('{error}', e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _importConfig(BuildContext context, WidgetRef ref, S s) async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text == null || !data!.text!.startsWith('LIGHTNING_CONFIG:')) {
        throw Exception('Invalid config');
      }

      final encoded = data.text!.substring('LIGHTNING_CONFIG:'.length);
      final jsonStr = utf8.decode(base64Decode(encoded));
      final Map<String, dynamic> config = jsonDecode(jsonStr);
      final prefs = await SharedPreferences.getInstance();

      for (final entry in config.entries) {
        final val = entry.value;
        if (val is String) {
          await prefs.setString(entry.key, val);
        } else if (val is int) {
          await prefs.setInt(entry.key, val);
        } else if (val is bool) {
          await prefs.setBool(entry.key, val);
        } else if (val is double) {
          await prefs.setDouble(entry.key, val);
        } else if (val is List<String>) {
          await prefs.setStringList(entry.key, val);
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('restore_success')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('restore_fail')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showMuxAdvancedDialog(
    BuildContext context,
    WidgetRef ref,
    VpnSettings settings,
    S s,
  ) {
    final concurrencyController = TextEditingController(
      text: settings.muxConcurrency.toString(),
    );
    final theme = Theme.of(context);
    bool localPadding = settings.muxPadding;
    String localProtocol = settings.muxProtocol;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              s.get('mux_advanced'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            content: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 并发数设置
                  Text(
                    s.get('mux_concurrency_label'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: concurrencyController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: s.get('default_hint').replaceAll('{value}', '8'),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Mux 协议选择
                  Text(
                    s.get('mux_protocol_label'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...['h2', 'h2c', 'wechat-video'].map((proto) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: RadioListTile<String>(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 0,
                          ),
                          value: proto,
                          groupValue: localProtocol,
                          activeColor: theme.colorScheme.primary,
                          title: Text(
                            proto.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() {
                                localProtocol = v;
                              });
                            }
                          },
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 12),
                  // Mux 填充选项
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            s.get('mux_padding_label'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Switch(
                          value: localPadding,
                          activeColor: theme.colorScheme.primary,
                          onChanged: (v) {
                            setDialogState(() {
                              localPadding = v;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  s.get('cancel'),
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final concurrency = int.tryParse(concurrencyController.text) ?? 8;
                  ref.read(vpnSettingsProvider.notifier).update(
                        settings.copyWith(
                          muxConcurrency: concurrency,
                          muxPadding: localPadding,
                          muxProtocol: localProtocol,
                        ),
                      );
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(s.get('confirm')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLogLevelDialog(
    BuildContext context,
    WidgetRef ref,
    VpnSettings settings,
    S s,
  ) {
    final levels = ['debug', 'info', 'warning', 'error', 'none'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('log_level')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: levels
              .map(
                (l) => RadioListTile<String>(
                  title: Text(l.toUpperCase()),
                  value: l,
                  groupValue: settings.logLevel,
                  onChanged: (v) {
                    ref
                        .read(vpnSettingsProvider.notifier)
                        .update(settings.copyWith(logLevel: v));
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  String _getModeName(VpnMode mode, S s) {
    switch (mode) {
      case VpnMode.global:
        return s.get('global_mode');
      case VpnMode.rule:
        return s.get('rule_mode');
      case VpnMode.direct:
        return s.get('direct_mode');
    }
  }

  void _showModePicker(
    BuildContext context,
    WidgetRef ref,
    VpnSettings settings,
    S s,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('routing_strategy')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: VpnMode.values
              .map(
                (m) => RadioListTile<VpnMode>(
                  title: Text(_getModeName(m, s)),
                  value: m,
                  groupValue: settings.mode,
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .update(settings.copyWith(mode: v));
                    }
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _showPortsDialog(
    BuildContext context,
    WidgetRef ref,
    VpnSettings settings,
    S s,
  ) {
    final socksController = TextEditingController(
      text: settings.socksPort.toString(),
    );
    final httpController = TextEditingController(
      text: settings.httpPort.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('inbound_settings')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: socksController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: s.get('socks_port_label'),
                hintText: s.get('default_hint').replaceAll('{value}', '10808'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: httpController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: s.get('http_port_label'),
                hintText: s.get('default_hint').replaceAll('{value}', '10809'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final socks = int.tryParse(socksController.text) ?? 10808;
              final http = int.tryParse(httpController.text) ?? 10809;
              ref
                  .read(vpnSettingsProvider.notifier)
                  .update(settings.copyWith(socksPort: socks, httpPort: http));
              Navigator.pop(context);
            },
            child: Text(s.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showDnsSettingsSheet(
    BuildContext context,
    WidgetRef ref,
    VpnSettings settings,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => DnsSettingsSheet(
          remoteDns: settings.remoteDns,
          domesticDns: settings.domesticDns,
          fakeDns: settings.fakeDns,
          enableLocalDns: settings.enableLocalDns,
          localDnsPort: settings.localDnsPort,
          enableIPv6: settings.enableIPv6,
          dnsHosts: settings.dnsHosts,
          onSave:
              (
                remoteDns,
                domesticDns,
                fakeDns,
                enableLocalDns,
                localDnsPort,
                enableIPv6,
                dnsHosts,
              ) {
                ref
                    .read(vpnSettingsProvider.notifier)
                    .update(
                      settings.copyWith(
                        remoteDns: remoteDns,
                        domesticDns: domesticDns,
                        fakeDns: fakeDns,
                        enableLocalDns: enableLocalDns,
                        localDnsPort: localDnsPort,
                        enableIPv6: enableIPv6,
                        dnsHosts: dnsHosts,
                      ),
                    );
              },
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context, S s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          s.get('about_lightning'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'icon.png',
                          width: 80,
                          height: 80,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Icon(
                                  Icons.bolt_rounded,
                                  size: 48,
                                  color: Colors.amber,
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.get('app_name'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '${s.get('version_label')}：1.0.0',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  s.get('desc_content'),
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withOpacity(0.9),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                _buildAboutInfoRow(
                  Icons.code_rounded,
                  s.get('core_technology'),
                  s.get('based_on_xray'),
                ),
                _buildAboutInfoRow(
                  Icons.security_rounded,
                  s.get('protocol_support'),
                  'VMess, VLESS, Trojan, SS, Hy2, TUIC',
                ),
                _buildAboutInfoRow(
                  Icons.link_rounded,
                  s.get('open_source_address'),
                  'https://github.com/lightning-xf/lightning-proxy',
                  isLink: true,
                ),
                _buildAboutInfoRow(Icons.gavel_rounded, s.get('open_source_license'), 'GNU AGPLv3'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final url = Uri.parse(
                'https://github.com/lightning-xf/lightning-proxy',
              );
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Text(
              s.get('project_home'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('close')),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutInfoRow(
    IconData icon,
    String label,
    String value, {
    bool isLink = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isLink ? Colors.blue.shade400 : null,
                    decoration: isLink ? TextDecoration.underline : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutItem(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
