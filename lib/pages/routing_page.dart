import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/routing_provider.dart';
import 'package:lightning/core/rule_model.dart';

class RoutingPage extends ConsumerWidget {
  const RoutingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(routingProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          '路由规则',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
            onPressed: () {
              HapticFeedback.lightImpact();
              _showAddRuleDialog(context, ref);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: rules.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: rules.length,
              itemBuilder: (context, index) {
                final rule = rules[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      title: Text(
                        rule.outboundTag.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _getRuleSummary(rule),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      trailing: Switch(
                        value: rule.enabled,
                        onChanged: (v) {
                          HapticFeedback.lightImpact();
                          ref
                              .read(routingProvider.notifier)
                              .toggleRule(rule.id);
                        },
                        activeColor: theme.colorScheme.primary,
                      ),
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        _showRuleOptions(context, ref, rule);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.alt_route_rounded, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 20),
          const Text(
            '暂无自定义规则',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击右上角按钮添加分流规则',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showRuleOptions(BuildContext context, WidgetRef ref, RuleModel rule) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
              ),
              title: const Text('删除规则', style: TextStyle(color: Colors.red)),
              onTap: () {
                ref.read(routingProvider.notifier).removeRule(rule.id);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getRuleSummary(RuleModel rule) {
    List<String> parts = [];
    if (rule.domain != null) parts.add('域名: ${rule.domain!.join(", ")}');
    if (rule.ip != null) parts.add('IP: ${rule.ip!.join(", ")}');
    if (rule.port != null) parts.add('端口: ${rule.port!.join(", ")}');
    if (rule.network != null) parts.add('网络: ${rule.network!.join(", ")}');
    return parts.join(' | ');
  }

  void _showAddRuleDialog(BuildContext context, WidgetRef ref) {
    final domainController = TextEditingController();
    final ipController = TextEditingController();
    final portController = TextEditingController();
    final networkController = TextEditingController();
    String outboundTag = 'direct';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            '添加规则',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: domainController,
                  decoration: const InputDecoration(
                    labelText: '域名 (逗号分隔)',
                    hintText: 'geosite:cn, google.com',
                  ),
                ),
                TextField(
                  controller: ipController,
                  decoration: const InputDecoration(
                    labelText: 'IP (逗号分隔)',
                    hintText: 'geoip:cn, 1.1.1.1',
                  ),
                ),
                TextField(
                  controller: portController,
                  decoration: const InputDecoration(
                    labelText: '端口 (逗号分隔)',
                    hintText: '80, 443, 1000-2000',
                  ),
                ),
                TextField(
                  controller: networkController,
                  decoration: const InputDecoration(
                    labelText: '协议 (逗号分隔)',
                    hintText: 'tcp, udp',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: outboundTag,
                  decoration: const InputDecoration(labelText: '动作'),
                  items: const [
                    DropdownMenuItem(
                      value: 'direct',
                      child: Text('直连 (Direct)'),
                    ),
                    DropdownMenuItem(value: 'proxy', child: Text('代理 (Proxy)')),
                    DropdownMenuItem(value: 'block', child: Text('阻断 (Block)')),
                  ],
                  onChanged: (v) => setState(() => outboundTag = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final domains = domainController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final ips = ipController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final ports = portController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final networks = networkController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();

                if (domains.isEmpty &&
                    ips.isEmpty &&
                    ports.isEmpty &&
                    networks.isEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('请输入至少一个过滤条件')));
                  return;
                }

                final rule = RuleModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  type: 'field',
                  domain: domains.isEmpty ? null : domains,
                  ip: ips.isEmpty ? null : ips,
                  port: ports.isEmpty ? null : ports,
                  network: networks.isEmpty ? null : networks,
                  outboundTag: outboundTag,
                );
                ref.read(routingProvider.notifier).addRule(rule);
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}
