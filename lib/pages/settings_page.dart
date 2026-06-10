import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/vpn_manager_provider.dart';
import 'package:lightning/core/vpn_manager_interface.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/routing_provider.dart';
import 'package:lightning/core/geo_updater.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:lightning/main.dart';
import 'package:lightning/pages/routing_page.dart';
import 'package:lightning/pages/app_splitting_page.dart';
import 'package:lightning/widgets/dns_settings_sheet.dart';
import 'package:lightning/widgets/uwp_exemption_dialog.dart';
import 'package:lightning/widgets/animated_logo.dart';
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
  final bool enableTun;
  final bool systemProxyEnabled;
  final bool enableFragment; // 新增：Fragment 防阻断开关
  final bool hideToTray; // 新增：隐藏到托盘
  final String showHideHotkey; // 新增：显隐快捷键 (e.g., "Alt+Q")
  final bool enableSniffing; // 新增：流量嗅探
  final String domainStrategy; // 新增：域名解析策略 (AsIs, IPIfNonMatch, IPOnDemand)
  final String tunStack; // 新增：TUN 栈 (gVisor, System, Mixed)
  final bool cleanProxyOnExit; // 新增：退出时清理系统代理
  final int apiPort; // 新增：内核 API 端口

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
    this.enableTun = false,
    this.systemProxyEnabled = true,
    this.enableFragment = false,
    this.hideToTray = true,
    this.showHideHotkey = 'Alt+Q',
    this.enableSniffing = true,
    this.domainStrategy = 'IPIfNonMatch',
    this.tunStack = 'gVisor',
    this.cleanProxyOnExit = true,
    this.apiPort = 10085,
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
    bool? enableTun,
    bool? systemProxyEnabled,
    bool? enableFragment,
    bool? hideToTray,
    String? showHideHotkey,
    bool? enableSniffing,
    String? domainStrategy,
    String? tunStack,
    bool? cleanProxyOnExit,
    int? apiPort,
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
      enableTun: enableTun ?? this.enableTun,
      systemProxyEnabled: systemProxyEnabled ?? this.systemProxyEnabled,
      enableFragment: enableFragment ?? this.enableFragment,
      hideToTray: hideToTray ?? this.hideToTray,
      showHideHotkey: showHideHotkey ?? this.showHideHotkey,
      enableSniffing: enableSniffing ?? this.enableSniffing,
      domainStrategy: domainStrategy ?? this.domainStrategy,
      tunStack: tunStack ?? this.tunStack,
      cleanProxyOnExit: cleanProxyOnExit ?? this.cleanProxyOnExit,
      apiPort: apiPort ?? this.apiPort,
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
        'enable_tun': enableTun,
        'system_proxy_enabled': systemProxyEnabled,
        'enable_fragment': enableFragment,
        'hide_to_tray': hideToTray,
        'show_hide_hotkey': showHideHotkey,
        'enable_sniffing': enableSniffing,
        'domain_strategy': domainStrategy,
        'tun_stack': tunStack,
        'clean_proxy_on_exit': cleanProxyOnExit,
        'api_port': apiPort,
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
        enableTun: json['enable_tun'] ?? false,
        systemProxyEnabled: json['system_proxy_enabled'] ?? true,
        enableFragment: json['enable_fragment'] ?? false,
        hideToTray: json['hide_to_tray'] ?? true,
        showHideHotkey: json['show_hide_hotkey'] ?? 'Alt+Q',
        enableSniffing: json['enable_sniffing'] ?? true,
        domainStrategy: json['domain_strategy'] ?? 'IPIfNonMatch',
        tunStack: json['tun_stack'] ?? 'gVisor',
        cleanProxyOnExit: json['clean_proxy_on_exit'] ?? true,
        apiPort: json['api_port'] ?? 10085,
      );
}

class VpnSettingsNotifier extends StateNotifier<VpnSettings> {
  final Ref _ref;
  VpnSettingsNotifier(this._ref) : super(VpnSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('vpn_settings');
    if (json != null) {
      state = VpnSettings.fromJson(jsonDecode(json));
      // Sync initial settings to native manager
      await _ref.read(vpnManagerProvider).updateSettings(
            autoStart: state.autoStart,
            autoReconnect: state.autoReconnect,
            showTraffic: state.showTraffic,
            useSystemProxy: state.systemProxyEnabled,
          );
    }
  }

  Future<void> update(VpnSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vpn_settings', jsonEncode(settings.toJson()));

    // Sync to native prefs for BootReceiver and Notification
    await _ref.read(vpnManagerProvider).updateSettings(
          autoStart: settings.autoStart,
          autoReconnect: settings.autoReconnect,
          showTraffic: settings.showTraffic,
          useSystemProxy: settings.systemProxyEnabled,
        );
  }
}

final vpnSettingsProvider =
    StateNotifierProvider<VpnSettingsNotifier, VpnSettings>((ref) {
  return VpnSettingsNotifier(ref);
});

final geoUpdateProgressProvider = StateProvider<double?>((ref) => null);

final coreVersionProvider = FutureProvider<String>((ref) async {
  return await ref.read(vpnManagerProvider).getCoreVersion();
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
                _buildSection(context, s.get('ui_display'), [
                  _buildSettingTile(
                    context,
                    Icons.palette_rounded,
                    s.get('appearance'),
                    themeMode == ThemeMode.dark
                        ? s.get('dark_mode')
                        : s.get('light_mode'),
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                    helpText: s.get('appearance_help'),
                    s: s,
                  ),
                  _buildSettingTile(
                    context,
                    Icons.language_rounded,
                    s.get('language'),
                    locale.languageCode == 'zh' ? '简体中文' : 'English',
                    onTap: () => _showLanguagePicker(context, ref, s),
                    helpText: s.get('language_help'),
                    s: s,
                  ),
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
                    onTap: null,
                    helpText: s.get('kernel_info_help'),
                    s: s,
                  ),
                  _buildDropdownTile<String>(
                    context,
                    Icons.bug_report_rounded,
                    s.get('log_level'),
                    vpnSettings.logLevel.toUpperCase(),
                    ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'NONE'],
                    (v) => ref.read(vpnSettingsProvider.notifier).update(
                          vpnSettings.copyWith(logLevel: v.toLowerCase()),
                        ),
                    helpText: s.get('log_level_help'),
                    s: s,
                  ),
                  _buildSwitchTile(
                    context,
                    Icons.alt_route_rounded,
                    s.get('mux_title'),
                    s.get('mux_desc'),
                    vpnSettings.muxEnabled,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(muxEnabled: v)),
                    helpText: s.get('mux_enabled_help'),
                    s: s,
                  ),
                  _buildSwitchTile(
                    context,
                    Icons.reorder_rounded,
                    s.get('fragment_title'),
                    s.get('fragment_desc'),
                    vpnSettings.enableFragment,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(enableFragment: v)),
                    helpText: s.get('fragment_help'),
                    s: s,
                  ),
                  _buildDropdownTile<String>(
                    context,
                    Icons.speed_rounded,
                    s.get('tcp_congestion'),
                    vpnSettings.tcpCongestion.toUpperCase(),
                    ['bbr', 'cubic', 'reno'],
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(tcpCongestion: v)),
                    helpText: s.get('tcp_congestion_help'),
                    s: s,
                  ),
                  _buildSwitchTile(
                    context,
                    Icons.radar_rounded,
                    s.get('sniffing_title'),
                    s.get('sniffing_desc'),
                    vpnSettings.enableSniffing,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(enableSniffing: v)),
                    helpText: s.get('sniffing_help'),
                    s: s,
                  ),
                  _buildDropdownTile<String>(
                    context,
                    Icons.language_rounded,
                    s.get('domain_strategy_title'),
                    vpnSettings.domainStrategy,
                    ['AsIs', 'IPIfNonMatch', 'IPOnDemand'],
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(domainStrategy: v)),
                    helpText: s.get('domain_strategy_help'),
                    s: s,
                  ),
                ]),
                _buildSection(context, s.get('rules_db_manage'), [
                  _buildGeoUpdateTile(context, ref, vpnSettings, s),
                ]),
                _buildSection(context, s.get('conn_automation'), [
                  if (Platform.isWindows) ...[
                    _buildSwitchTile(
                      context,
                      Icons.launch_rounded,
                      s.get('auto_start'),
                      s.get('auto_start_help'),
                      vpnSettings.autoStart,
                      (v) async {
                        if (v) {
                          await LaunchAtStartup.instance.enable();
                        } else {
                          await LaunchAtStartup.instance.disable();
                        }
                        ref
                            .read(vpnSettingsProvider.notifier)
                            .update(vpnSettings.copyWith(autoStart: v));
                      },
                      helpText: s.get('auto_start_tip'),
                      s: s,
                    ),
                    _buildSwitchTile(
                      context,
                      Icons.visibility_off_rounded,
                      s.get('hide_to_tray_title'),
                      s.get('hide_to_tray_desc'),
                      vpnSettings.hideToTray,
                      (v) => ref
                          .read(vpnSettingsProvider.notifier)
                          .update(vpnSettings.copyWith(hideToTray: v)),
                      helpText: s.get('hide_to_tray_help'),
                      s: s,
                    ),
                    _buildSwitchTile(
                      context,
                      Icons.cleaning_services_rounded,
                      s.get('clean_proxy_on_exit_title'),
                      s.get('clean_proxy_on_exit_desc'),
                      vpnSettings.cleanProxyOnExit,
                      (v) => ref
                          .read(vpnSettingsProvider.notifier)
                          .update(vpnSettings.copyWith(cleanProxyOnExit: v)),
                      helpText: s.get('clean_proxy_on_exit_help'),
                      s: s,
                    ),
                  ],
                  if (!Platform.isWindows)
                    _buildSwitchTile(
                      context,
                      Icons.power_settings_new_rounded,
                      s.get('auto_start'),
                      s.get('auto_start_help'),
                      vpnSettings.autoStart,
                      (v) => ref
                          .read(vpnSettingsProvider.notifier)
                          .update(vpnSettings.copyWith(autoStart: v)),
                      helpText: s.get('auto_start_help'),
                      s: s,
                    ),
                  if (!Platform.isWindows)
                    _buildSwitchTile(
                      context,
                      Icons.verified_user_rounded,
                      s.get('keep_alive'),
                      s.get('keep_alive_help'),
                      vpnSettings.keepAlive,
                      (v) => ref
                          .read(vpnSettingsProvider.notifier)
                          .update(vpnSettings.copyWith(keepAlive: v)),
                      helpText: s.get('keep_alive_help'),
                      s: s,
                    ),
                  _buildSwitchTile(
                    context,
                    Icons.refresh_rounded,
                    s.get('auto_reconnect'),
                    s.get('auto_reconnect_help'),
                    vpnSettings.autoReconnect,
                    (v) => ref
                        .read(vpnSettingsProvider.notifier)
                        .update(vpnSettings.copyWith(autoReconnect: v)),
                    helpText: s.get('auto_reconnect_help'),
                    s: s,
                  ),
                  if (Platform.isWindows)
                    _buildSettingTile(
                      context,
                      Icons.keyboard_rounded,
                      s.get('hotkey_title'),
                      vpnSettings.showHideHotkey,
                      onTap: () =>
                          _showHotkeyEditor(context, ref, vpnSettings, s),
                      helpText: s.get('hotkey_help'),
                      s: s,
                    ),
                  if (!Platform.isWindows)
                    _buildSwitchTile(
                      context,
                      Icons.speed_rounded,
                      s.get('show_traffic'),
                      s.get('show_traffic_help'),
                      vpnSettings.showTraffic,
                      (v) => ref
                          .read(vpnSettingsProvider.notifier)
                          .update(vpnSettings.copyWith(showTraffic: v)),
                      helpText: s.get('show_traffic_help'),
                      s: s,
                    ),
                ]),
                _buildSection(context, s.get('route_splitting'), [
                  if (Platform.isWindows) ...[
                    _buildSwitchTile(
                      context,
                      Icons.language_rounded,
                      s.get('system_proxy_title'),
                      s.get('system_proxy_desc'),
                      vpnSettings.systemProxyEnabled,
                      (v) => ref
                          .read(vpnSettingsProvider.notifier)
                          .update(vpnSettings.copyWith(systemProxyEnabled: v)),
                      helpText: s.get('system_proxy_help'),
                      s: s,
                    ),
                    _buildSwitchTile(
                      context,
                      Icons.security_rounded,
                      s.get('tun_service_mode'),
                      s.get('tun_mode_desc'),
                      vpnSettings.enableTun,
                      (v) => ref
                          .read(vpnSettingsProvider.notifier)
                          .update(vpnSettings.copyWith(enableTun: v)),
                      helpText: s.get('tun_mode_desc'),
                      s: s,
                    ),
                    if (Platform.isWindows && vpnSettings.enableTun)
                      _buildDropdownTile<String>(
                        context,
                        Icons.layers_rounded,
                        s.get('tun_stack_title'),
                        vpnSettings.tunStack,
                        ['gVisor', 'System', 'Mixed'],
                        (v) => ref
                            .read(vpnSettingsProvider.notifier)
                            .update(vpnSettings.copyWith(tunStack: v)),
                        helpText: s.get('tun_stack_help'),
                        s: s,
                      ),
                  ],
                  _buildSettingTile(
                    context,
                    Icons.alt_route_rounded,
                    s.get('routing_strategy'),
                    '${s.get('current_mode')}: ${_getModeName(vpnSettings.mode, s)}',
                    onTap: () => _showModePicker(context, ref, vpnSettings, s),
                    helpText: s.get('routing_strategy_help'),
                    s: s,
                  ),
                  _buildSettingTile(
                    context,
                    Icons.rule_rounded,
                    s.get('rules_manage'),
                    s.get('rules_manage_desc'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RoutingPage()),
                    ),
                    helpText: s.get('rules_manage_help'),
                    s: s,
                  ),
                  if (!Platform.isWindows)
                    _buildSettingTile(
                      context,
                      Icons.apps_rounded,
                      s.get('app_split'),
                      s.get('app_split_desc'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppSplittingPage(),
                        ),
                      ),
                      s: s,
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
                    helpText: s.get('bypass_local_help'),
                    s: s,
                  ),
                  _buildAllowLanTile(context, ref, vpnSettings, s),
                ]),
                _buildSection(context, s.get('adv_network'), [
                  if (Platform.isWindows)
                    _buildSettingTile(
                      context,
                      Icons.apps_outage_rounded,
                      s.get('uwp_exemption_title'),
                      s.get('uwp_exemption_desc'),
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => const UwpExemptionDialog(),
                      ),
                      helpText: s.get('uwp_exemption_help'),
                      s: s,
                    ),
                  _buildSettingTile(
                    context,
                    Icons.settings_ethernet_rounded,
                    s.get('inbound_ports_title'),
                    s.get('inbound_ports_desc', args: {
                      'socks': vpnSettings.socksPort,
                      'http': vpnSettings.httpPort,
                    }),
                    onTap: () => _showPortsDialog(context, ref, vpnSettings, s),
                    helpText: s.get('inbound_ports_help'),
                    s: s,
                  ),
                  _buildSettingTile(
                    context,
                    Icons.dns_rounded,
                    s.get('dns_settings'),
                    s.get('remote_dns'),
                    onTap: () =>
                        _showDnsSettingsSheet(context, ref, vpnSettings),
                    helpText: s.get('dns_settings_help'),
                    s: s,
                  ),
                ]),
                _buildSection(context, s.get('backup_restore'), [
                  _buildSettingTile(
                    context,
                    Icons.cloud_sync_rounded,
                    s.get('backup_restore'),
                    s.get('backup_restore_desc'),
                    onTap: () => _showBackupRestoreDialog(context, ref, s),
                    helpText: s.get('backup_restore_help'),
                    s: s,
                  ),
                  _buildSettingTile(
                    context,
                    Icons.info_rounded,
                    s.get('about'),
                    s.get('about_desc'),
                    onTap: () => _showAboutDialog(context, s),
                    helpText: s.get('about_help'),
                    s: s,
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
    ValueChanged<T> onChanged, {
    String? helpText,
    VoidCallback? helpTextOnTap,
    required S s,
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
                  onTap: helpTextOnTap ??
                      () {
                        _showHelpDialog(context, s, title, helpText!);
                      },
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
      helpTextOnTap: () async {
        final ip = await _getLocalIp();
        if (context.mounted) {
          _showLanDetailsDialog(context, s, ip, vpnSettings);
        }
      },
      s: s,
    );
  }

  void _showLanDetailsDialog(
    BuildContext context,
    S s,
    String ip,
    VpnSettings settings,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.lan_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(s.get('allow_lan')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.get('allow_lan_help').replaceAll('{ip}', ip).replaceAll(
                    '{port}',
                    settings.httpPort.toString(),
                  ),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _buildLanDialogInfoItem(
              context,
              'HTTP Proxy',
              '$ip:${settings.httpPort}',
              s,
            ),
            const SizedBox(height: 12),
            _buildLanDialogInfoItem(
              context,
              'Socks5 Proxy',
              '$ip:${settings.socksPort}',
              s,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('got_it')),
          ),
        ],
      ),
    );
  }

  Widget _buildLanDialogInfoItem(
    BuildContext context,
    String title,
    String value,
    S s,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.1)
              : Theme.of(context).dividerTheme.color ??
                  Colors.black.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(s.get('link_copied_success')),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                  width: 200,
                ),
              );
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeoUpdateTile(
    BuildContext context,
    WidgetRef ref,
    VpnSettings vpnSettings,
    S s,
  ) {
    final progress = ref.watch(geoUpdateProgressProvider);
    final isUpdating = progress != null;

    return _buildSettingTile(
      context,
      Icons.system_update_rounded,
      s.get('sync_geodata'),
      isUpdating
          ? s.get('updating_geodata',
              args: {'progress': (progress * 100).toStringAsFixed(0)})
          : s.get('sync_geodata_desc'),
      onTap: isUpdating
          ? null
          : () async {
              final vpnState = ref.read(vpnProvider);
              if (vpnState.isRunning) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(s.get('disconnect_before_update')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

              ref.read(geoUpdateProgressProvider.notifier).state = 0.0;
              try {
                await GeoUpdater().updateGeoFiles(
                  onProgress: (p) =>
                      ref.read(geoUpdateProgressProvider.notifier).state = p,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(s.get('update_geodata_success')),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          s.get('update_geodata_failed', args: {'error': e})),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } finally {
                ref.read(geoUpdateProgressProvider.notifier).state = null;
              }
            },
      trailing: isUpdating
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress > 0 ? progress : null,
              ),
            )
          : null,
      helpText: s.get('sync_geodata_help'),
      s: s,
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 24, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.04)
                  : theme.dividerTheme.color ?? Colors.black.withOpacity(0.12),
            ),
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
    String subtitle, {
    VoidCallback? onTap,
    String? helpText,
    VoidCallback? helpTextOnTap,
    Widget? trailing,
    required S s,
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
                  onTap: helpTextOnTap ??
                      () {
                        _showHelpDialog(context, s, title, helpText!);
                      },
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
          trailing: trailing ??
              (onTap != null
                  ? Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey.shade700,
                      size: 18,
                    )
                  : null),
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
    ValueChanged<bool> onChanged, {
    String? helpText,
    VoidCallback? helpTextOnTap,
    required S s,
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
                  onTap: helpTextOnTap ??
                      () {
                        _showHelpDialog(context, s, title, helpText!);
                      },
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

  void _showHelpDialog(
      BuildContext context, S s, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('got_it')),
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
            Text(s.get('keep_alive_guide_desc')),
            const SizedBox(height: 16),
            Text(s.get('keep_alive_step1')),
            Text(s.get('keep_alive_step2')),
            Text(s.get('keep_alive_step3')),
            Text(s.get('keep_alive_step4')),
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
              // In a real app, this would use a native method to open settings
              // For now, we show a success message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(s.get('redirecting_to_settings')),
                  behavior: SnackBarBehavior.floating,
                ),
              );
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
                ref.read(localizationProvider.notifier).setLocale(
                      const Locale('zh', 'CN'),
                    );
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('English'),
              value: 'en',
              groupValue: ref.watch(localizationProvider).languageCode,
              onChanged: (v) {
                ref.read(localizationProvider.notifier).setLocale(
                      const Locale('en', 'US'),
                    );
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('backup_restore')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload_rounded),
              title: Text(s.get('export_config')),
              onTap: () async {
                Navigator.pop(context);
                await _exportConfig(context, ref, s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download_rounded),
              title: Text(s.get('import_config')),
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
            child: Text(s.get('cancel')),
          ),
        ],
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
      await Clipboard.setData(ClipboardData(text: jsonStr));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('config_backed_up')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('backup_failed', args: {'error': e})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _importConfig(BuildContext context, WidgetRef ref, S s) async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text == null) return;

      final Map<String, dynamic> config = jsonDecode(data!.text!);
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
            content: Text(s.get('config_restored')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.get('import_failed_invalid')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
        title: const Text('入站端口设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: socksController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Socks 端口',
                hintText: '默认 10808',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: httpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'HTTP 端口',
                hintText: '默认 10809',
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
          onSave: (
            remoteDns,
            domesticDns,
            fakeDns,
            enableLocalDns,
            localDnsPort,
            enableIPv6,
            dnsHosts,
          ) {
            ref.read(vpnSettingsProvider.notifier).update(
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
        title: const Text(
          '关于 Lightning',
          style: TextStyle(fontWeight: FontWeight.w900),
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
                      const AnimatedLogo(size: 80), // 🚀 使用统一的动画 Logo
                      const SizedBox(height: 16),
                      const Text(
                        'Lightning VPN',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '版本：16.9.15',
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
                  'Lightning 是一款高性能、多协议的代理客户端，致力于提供极速、稳定且安全的网络访问体验。',
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
                  '核心技术',
                  '基于 Xray-core 构建',
                ),
                _buildAboutInfoRow(
                  Icons.security_rounded,
                  '协议支持',
                  'VMess, VLESS, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard',
                ),
                _buildAboutInfoRow(
                  Icons.link_rounded,
                  '开源地址',
                  'https://github.com/lightning-xf/lightning-proxy',
                  isLink: true,
                ),
                _buildAboutInfoRow(Icons.gavel_rounded, '开源协议', 'GNU AGPLv3'),
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
            child: const Text(
              '项目主页',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
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

  void _showHotkeyEditor(
    BuildContext context,
    WidgetRef ref,
    VpnSettings settings,
    S s,
  ) {
    final controller = TextEditingController(text: settings.showHideHotkey);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('hotkey_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: s.get('hotkey_input_label'),
                hintText: 'e.g. Alt+Q, Ctrl+Shift+S',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () => controller.clear(),
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              s.get('hotkey_format_hint'),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
              final newHotkey = controller.text.trim();
              if (newHotkey.isNotEmpty) {
                ref
                    .read(vpnSettingsProvider.notifier)
                    .update(settings.copyWith(showHideHotkey: newHotkey));
              }
              Navigator.pop(context);
            },
            child: Text(s.get('confirm')),
          ),
        ],
      ),
    );
  }
}
