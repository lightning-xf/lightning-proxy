import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationNotifier extends StateNotifier<Locale> {
  LocalizationNotifier() : super(const Locale('zh', 'CN')) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('language_code') ?? 'zh';
    final country = prefs.getString('country_code') ?? 'CN';
    state = Locale(lang, country);
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
    await prefs.setString('country_code', locale.countryCode ?? '');
  }
}

final localizationProvider =
    StateNotifierProvider<LocalizationNotifier, Locale>((ref) {
      return LocalizationNotifier();
    });

class S {
  final Locale locale;
  S(this.locale);

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_name': 'Lightning',
      'control_panel': 'Dashboard',
      'nodes_manage': 'Nodes',
      'sub_settings': 'Subscriptions',
      'realtime_logs': 'Logs',
      'advanced_config': 'Settings',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'global_mode': 'Global Mode',
      'rule_mode': 'Rule Mode',
      'direct_mode': 'Direct Mode',
      'upload': 'Upload',
      'download': 'Download',
      'total': 'Total',
      'reset_stats': 'Reset Stats',
      'settings': 'Settings',
      'appearance': 'Appearance',
      'language': 'Language',
      'dark_mode': 'Dark Mode',
      'light_mode': 'Light Mode',
      'battery_opt': 'Battery Optimization',
      'backup_restore': 'Backup & Restore',
      'about': 'About',
      'bg_keep_alive': 'Background Keep Alive',
      'auto_start': 'Auto Start',
      'auto_start_desc': 'Auto connect on boot',
      'keep_alive': 'Keep Alive Service',
      'keep_alive_desc': 'Prevent system from killing process',
      'auto_reconnect': 'Auto Reconnect',
      'auto_reconnect_desc': 'Recover connection on network change',
      'show_traffic': 'Status Bar Display',
      'show_traffic_desc': 'Show speed and traffic in status bar',
      'keep_alive_guide': 'Keep Alive Guide',
      'keep_alive_guide_desc': 'Click to open system settings',
      'routing_split': 'Routing & Splitting',
      'routing_strategy': 'Routing Strategy',
      'routing_strategy_desc': 'Current: ',
      'rules_manage': 'Rules Management',
      'rules_manage_desc': 'Edit custom domain and IP rules',
      'app_split': 'App Splitting',
      'app_split_desc': 'Select apps to proxy or bypass',
      'bypass_local': 'Bypass Local',
      'bypass_local_desc': 'Do not proxy local network traffic',
      'core_protocol': 'Core Protocol',
      'kernel_info': 'Kernel Information',
      'auto_update': 'Auto Update Subscription',
      'auto_update_desc': 'Current: ',
      'auto_update_disabled': 'Disabled',
      'auto_update_hours': 'Every {hours} hours',
      'log_level': 'Log Level',
      'advanced_network': 'Advanced Network',
      'inbound_ports': 'Inbound Ports',
      'custom_dns': 'Custom DNS',
      'fake_dns': 'Fake DNS',
      'fake_dns_desc': 'Reduce DNS pollution, speed up connection',
      'system_opt': 'System & Optimization',
      'ignore_battery': 'Ignore Battery Optimization',
      'ignore_battery_desc': 'Maintain connection stability',
      'mux_enabled': 'Mux Multiplexing',
      'mux_enabled_desc': 'Reuse TCP connections for multiple streams',
      'tcp_congestion': 'TCP Congestion Control',
      'tcp_congestion_desc': 'Current: ',
      'allow_lan': 'Allow LAN Connection',
      'allow_lan_desc': 'Enable gateway sharing for other devices',
      'proxy_ip_hint': 'Set Proxy IP to: {ip}',
      'proxy_port_hint': 'Proxy Port: {port}',
      'advanced': 'Advanced',
      'backup_restore_desc': 'Export or import nodes and settings',
      'about_desc': 'Empowering Secure & High-Performance Connectivity',
      'version_label': 'Software Version',
      'github_label': 'Open Source Repository',
      'author_label': 'Developer Team',
      'desc_label': 'Description',
      'desc_content':
          'Lightning is a next-generation network proxy client designed for high performance, security, and extreme stability. Powered by cutting-edge core technologies.',
      'confirm': 'Confirm',
      'cancel': 'Cancel',
      'hours': 'hours',
      'every': 'Every',
      'disabled': 'Disabled',
      'ui_display': 'UI Display',
      'conn_automation': 'Connection & Automation',
      'route_splitting': 'Routing & Splitting',
      'protocol_kernel': 'Protocol & Kernel',
      'adv_network': 'Advanced Network',
      'about_maintenance': 'About & Maintenance',
      'auto_start_help':
          'Function: Automatically start Lightning and reconnect to the last used node after the system boots and the screen is unlocked.\n\nOn: Achieve 24/7 connectivity without manual operation.\n\nOff: You need to manually open the app and connect after every reboot.',
      'keep_alive_help':
          'Function: Display a persistent notification to make Lightning a "Foreground Service".\n\nOn: Significantly reduces the frequency of the system killing the app in the background, keeping the connection stable.\n\nOff: The system may kill the app process when memory is low, causing the proxy to disconnect suddenly.',
      'auto_reconnect_help':
          'Function: Monitor network changes (Wi-Fi/Data/Airplane mode) in real-time.\n\nOn: Automatically attempts to reconnect in the background when the connection is lost due to network switching, ensuring seamless transitions.\n\nOff: If the connection is lost after a network change, you must manually reconnect.',
      'show_traffic_help':
          'Function: Display real-time upload and download speeds in the system status bar or notification.\n\nOn: Monitor network load at any time and intuitively observe node performance.\n\nOff: Cleaner status bar, but unable to see real-time traffic fluctuations.',
      'ignore_battery_help':
          'Function: Guide you to add Lightning to the system\'s battery optimization whitelist (Unrestricted).\n\nOn: Prevents the system from cutting off network connections to save power when the screen is off or the device is sleeping, greatly improving stability.\n\nOff: Connections may become unstable or be disconnected by the system when the screen is off.',
      'routing_strategy_help':
          'Global Mode: All network requests go through the proxy. Suitable for scenarios where you need to hide your IP at all times, but domestic websites may be slower.\n\nRule Mode: Intelligently decides based on rule lists. Domestic sites connect directly, while overseas sites use the proxy. Recommended.\n\nDirect Mode: Do not use a proxy; connect directly to the internet.',
      'bypass_local_help':
          'Function: Identify local network addresses like 192.168.x.x.\n\nOn: Access local devices (routers, NAS, printers) directly without going through the proxy, ensuring the fastest speed and normal local access.\n\nOff: Local traffic may be redirected to the proxy server, potentially causing issues accessing local devices.',
      'mux_enabled_help':
          'Function: Multiplex multiple data streams over a single TCP connection.\n\nOn: Significantly reduces TCP handshake latency when accessing many small files (like web browsing), improving responsiveness.\n\nOff: More stable for large file downloads and may have higher bandwidth limits on some ISP networks.',
      'tcp_congestion_help':
          'BBR: Google\'s congestion control algorithm. Especially effective for high-latency, high-loss cross-border networks to maximize bandwidth.\n\nCubic/Reno: Classic TCP algorithms with good compatibility, performing well on stable networks with low packet loss.',
      'fake_dns_help':
          'Function: Respond immediately to DNS requests by returning virtual IP addresses.\n\nOn: Fundamentally solves DNS pollution and enables "instant" web page loading (no waiting for resolution). Recommended.\n\nOff: Relies on real resolution, which may be subject to ISP DNS hijacking or pollution.',
      'allow_lan_help':
          'Function: Share this device\'s proxy connection with other devices on the same Wi-Fi network.\n\nUsage Guide:\n1. Enable this switch.\n2. Check your phone\'s local IP (e.g., {ip}) and the HTTP port ({port}).\n3. On other devices (PS5, PC, TV), go to Network Settings -> Proxy.\n4. Set Proxy Server to your phone\'s IP and Port to {port}.\n\nOn: Your phone becomes a gateway for other devices.\nOff: Only this device uses the proxy.',
      'inbound_ports_help':
          'Function: Set the local ports for Socks5 and HTTP proxy services.\n\nOn: Other apps on this device or other devices in the LAN can manually use these ports to connect to the proxy.\n\nOff: No local ports will be opened, and manual proxy configuration will not be possible.',
      'custom_dns_help':
          'Function: Set the DNS server addresses used by the proxy core.\n\nOn: Custom DNS can bypass ISP DNS hijacking and potentially improve resolution speed and accuracy.',
      'kernel_info_help':
          'Function: Display the information of the core proxy engine.\n\nDetails: Lightning uses Xray-core, a high-performance and feature-rich network proxy core.',
      'log_level_help':
          'Function: Control the verbosity of logs generated by the proxy core.\n\nOn: Higher levels (DEBUG/INFO) provide more details for troubleshooting but may use more resources. ERROR/NONE minimize logs.',
      'dns_settings': 'DNS Settings',
      'remote_dns': 'Remote DNS',
      'remote_dns_desc':
          'DNS servers for overseas domains (UDP/TCP/HTTPS/QUIC)',
      'remote_dns_preset': 'Remote DNS Presets',
      'domestic_dns': 'Domestic DNS',
      'domestic_dns_desc': 'DNS servers for mainland domains',
      'domestic_dns_preset': 'Domestic DNS Presets',
      'enable_ipv6': 'Enable IPv6 DNS',
      'enable_ipv6_desc': 'Include IPv6 addresses in DNS queries',
      'local_dns': 'Local DNS',
      'enable_local_dns': 'Enable Local DNS',
      'enable_local_dns_desc': 'Process DNS through core DNS module',
      'local_dns_port': 'Local DNS Port',
      'local_dns_port_desc': 'Local DNS listening port',
      'dns_hosts': 'DNS Hosts',
      'dns_hosts_desc': 'Format: domain:address, separated by newlines',
      'preset': 'Presets',
      'save': 'Save',
    },
    'zh': {
      'app_name': 'Lightning',
      'control_panel': '控制面板',
      'nodes_manage': '节点管理',
      'sub_settings': '订阅设置',
      'realtime_logs': '实时日志',
      'advanced_config': '高级配置',
      'connected': '已连接',
      'disconnected': '未连接',
      'global_mode': '全局模式',
      'rule_mode': '规则模式',
      'direct_mode': '直连模式',
      'upload': '上传',
      'download': '下载',
      'total': '总计',
      'reset_stats': '重置统计数据',
      'settings': '设置',
      'appearance': '外观主题',
      'language': '语言设置',
      'dark_mode': '深色模式',
      'light_mode': '浅色模式',
      'battery_opt': '忽略电池优化',
      'backup_restore': '备份与恢复',
      'about': '关于',
      'bg_keep_alive': '后台保活与自启动',
      'auto_start': '开机自启动',
      'auto_start_desc': '手机开机后自动连接代理',
      'keep_alive': '后台保活服务',
      'keep_alive_desc': '锁定后台任务，防止系统误杀',
      'auto_reconnect': '断网自动重连',
      'auto_reconnect_desc': '网络环境切换后自动恢复连接',
      'show_traffic': '状态栏显示',
      'show_traffic_desc': '在系统状态栏实时显示网速和流量',
      'keep_alive_guide': '系统保活引导',
      'keep_alive_guide_desc': '点击前往设置允许后台运行',
      'routing_split': '路由与分流',
      'routing_strategy': '路由策略',
      'routing_strategy_desc': '当前：',
      'rules_manage': '分流规则管理',
      'rules_manage_desc': '编辑自定义域名和 IP 规则',
      'app_split': '应用分流',
      'app_split_desc': '选择需要代理或绕过的应用',
      'bypass_local': '绕过局域网',
      'bypass_local_desc': '开启后不代理局域网流量',
      'core_protocol': '核心协议',
      'kernel_info': '内核信息',
      'auto_update': '订阅自动更新',
      'auto_update_desc': '当前：',
      'auto_update_disabled': '已禁用',
      'auto_update_hours': '每 {hours} 小时',
      'log_level': '日志输出等级',
      'advanced_network': '网络高级设置',
      'inbound_ports': '入站端口配置',
      'custom_dns': '自定义 DNS',
      'fake_dns': 'Fake DNS',
      'fake_dns_desc': '减少 DNS 污染，提升连接速度',
      'system_opt': '系统与优化',
      'ignore_battery': '忽略电池优化',
      'ignore_battery_desc': '防止系统后台误杀，保持连接稳定',
      'mux_enabled': 'Mux 多路复用',
      'mux_enabled_desc': '在单个 TCP 连接上复用多个数据流',
      'tcp_congestion': 'TCP 拥塞控制',
      'tcp_congestion_desc': '当前：',
      'allow_lan': '允许局域网连接',
      'allow_lan_desc': '允许局域网内的其他设备通过本机上网',
      'proxy_ip_hint': '请在其他设备上设置代理 IP 为：{ip}',
      'proxy_port_hint': '代理端口：{port}',
      'advanced': '高级',
      'backup_restore_desc': '导出或恢复节点及应用配置',
      'about_desc': '致力于打造极致性能与隐私保护的连接体验',
      'version_label': '软件版本',
      'github_label': '开放源代码',
      'author_label': '开发者团队',
      'desc_label': '产品描述',
      'desc_content':
          'Lightning 是一款次世代网络代理客户端，专注于高并发性能优化与极致的连接稳定性，集成全球领先的流量混淆与传输技术。',
      'confirm': '确定',
      'cancel': '取消',
      'hours': '小时',
      'every': '每',
      'disabled': '已禁用',
      'ui_display': '界面显示',
      'conn_automation': '连接与自动化',
      'route_splitting': '路由与分流',
      'protocol_kernel': '协议与内核',
      'adv_network': '网络高级设置',
      'about_maintenance': '关于与维护',
      'auto_start_help':
          '功能：在手机系统启动完成并解锁屏幕后，自动运行 Lightning 并恢复上次断开时的连接。\n\n开启：无需手动操作即可实现全天候代理，方便省心。\n\n关闭：每次开机后需要手动打开 App 并点击连接。',
      'keep_alive_help':
          '功能：通过在通知栏显示一个常驻的通知，使 Lightning 成为“前台服务”。\n\n开启：显著降低 Android 系统在后台清理 App 的频率，保持连接不中断。\n\n关闭：系统在内存紧张时会优先杀掉 App 进程，导致代理突然断开。',
      'auto_reconnect_help':
          '功能：实时监测系统网络状态（Wi-Fi/数据/飞行模式）。\n\n开启：当网络切换导致连接断开时，App 会在后台自动尝试重连，保持网络无缝切换。\n\n关闭：网络切换后如果连接丢失，需要手动进入 App 重新连接。',
      'show_traffic_help':
          '功能：在系统状态栏或通知栏显示实时的上传和下载速度。\n\n开启：随时掌握当前的网络负载情况，直观观察节点速度。\n\n关闭：状态栏更简洁，但无法直接看到实时的流量波动。',
      'ignore_battery_help':
          '功能：引导用户将 Lightning 加入系统的电池优化白名单（不限制）。\n\n开启：防止系统在手机灭屏或休眠时为了省电而强制切断网络连接，极大提升稳定性。\n\n关闭：灭屏后连接可能变得不稳定，甚至被系统自动断开。',
      'routing_strategy_help':
          '全局模式：所有网络请求全部经过代理，适合需要全时隐藏 IP 的场景，但访问国内网站可能变慢。\n\n规则模式：基于规则列表智能判断，国内网站直连，海外网站走代理，推荐使用。\n\n直连模式：不使用代理，直接连接互联网。',
      'bypass_local_help':
          '功能：识别 192.168.x.x 等局域网地址。\n\n开启：访问家里的路由器、NAS、打印机时直接连接，不走代理，速度最快且互访正常。\n\n关闭：局域网流量也可能被重定向到代理服务器，导致无法访问本地设备。',
      'mux_enabled_help':
          '功能：在单个 TCP 连接中并发传输多个子流。\n\n开启：显著降低频繁访问小文件时的 TCP 握手延迟（如网页加载），提升响应速度。\n\n关闭：对于单个大文件下载更稳定，在某些运营商网络下带宽上限更高。',
      'tcp_congestion_help':
          'BBR：Google 开发的新型拥塞算法，特别适合高丢包、长距离的跨境网络，能榨干带宽性能。\n\nCubic/Reno：经典的 TCP 算法，兼容性好，在低丢包的稳定网络下表现良好。',
      'fake_dns_help':
          '功能：通过返回虚拟 IP 立即响应 DNS 请求。\n开启：从根本上解决 DNS 污染问题，且能实现“秒开”网页（无需等待解析完成），推荐开启。\n关闭：依赖真实解析，可能受到 ISP 的 DNS 劫持或污染。',
      'allow_lan_help':
          '功能：将本机的代理网络共享给处于同一 Wi-Fi 下的其他设备使用。\n\n使用教程：\n1. 开启此开关。\n2. 查看并记住你手机的内网 IP（如 {ip}）以及 HTTP 端口（{port}）。\n3. 在其他设备（如 PS5、Switch、电脑、电视）的“网络设置”中找到“代理设置”。\n4. 将代理服务器地址填入你手机的 IP，端口填入 {port}。\n\n开启：你的手机将变成一台代理网关，使其他设备可以通过代理上网。\n关闭：仅本机可以使用代理，其他设备无法接入。',
      'inbound_ports_help':
          '功能：设置本地 Socks5 和 HTTP 代理服务的监听端口。\n\n开启：本机其他应用或局域网内其他设备可以通过手动设置这些端口来连接代理。\n\n关闭：将不开放本地入站端口，无法进行手动代理配置。',
      'custom_dns_help':
          '功能：设置代理内核使用的 DNS 服务器地址。\n\n开启：自定义 DNS 可以绕过运营商的 DNS 劫持，并可能提升解析速度和准确性。',
      'kernel_info_help':
          '功能：显示底层代理引擎的相关信息。\n\n详情：Lightning 采用 Xray-core 作为核心，支持多种协议并具备极高的转发性能。',
      'log_level_help':
          '功能：控制代理内核输出日志的详细程度。\n\n开启：高级别（DEBUG/INFO）日志有助于排查连接问题，但会占用更多系统资源；低级别（ERROR/NONE）则能保持系统简洁。',
      'dns_settings': 'DNS 设置',
      'remote_dns': '远程 DNS',
      'remote_dns_desc': '海外域名 DNS 服务器（UDP/TCP/HTTPS/QUIC）',
      'remote_dns_preset': '远程 DNS 预设',
      'domestic_dns': '国内 DNS',
      'domestic_dns_desc': '国内域名 DNS 服务器',
      'domestic_dns_preset': '国内 DNS 预设',
      'enable_ipv6': '启用 IPv6 DNS',
      'enable_ipv6_desc': '在 DNS 查询中包含 IPv6 地址',
      'local_dns': '本地 DNS',
      'enable_local_dns': '启用本地 DNS',
      'enable_local_dns_desc': '通过内核 DNS 模块处理解析',
      'local_dns_port': '本地 DNS 端口',
      'local_dns_port_desc': '本地 DNS 监听端口',
      'dns_hosts': 'DNS Hosts',
      'dns_hosts_desc': '格式：domain:address，多个用换行分隔',
      'preset': '预设',
      'save': '保存',
    },
  };

  String get(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }

  static S of(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localizationProvider);
    return S(locale);
  }
}
