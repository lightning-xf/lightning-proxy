import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/routing_provider.dart';
import 'package:lightning/core/rule_model.dart';
import 'package:lightning/core/localization_provider.dart';

class RoutingPage extends ConsumerWidget {
  const RoutingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(routingProvider);
    final theme = Theme.of(context);
    final s = S.of(context, ref);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          s.get('routing_rules'),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        actions: [
          _buildCleanEnginePopup(context, ref, s),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRuleDialog(context, ref, s),
        label: Text(s.get('add_rule')),
        icon: const Icon(Icons.add_rounded),
      ),
      body: rules.isEmpty
          ? _buildEmptyState(context, ref)
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
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      hoverColor: theme.brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.04)
                          : Colors.black.withOpacity(0.02),
                      onTap: Platform.isWindows
                          ? () {
                              _showRuleOptions(context, ref, rule, s);
                            }
                          : null,
                      onSecondaryTapDown: (details) {
                        if (Platform.isWindows) {
                          _showRuleContextMenu(
                              context, ref, rule, details.globalPosition, s);
                        }
                      },
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
                            _getRuleSummary(rule, s),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: rule.enabled,
                              onChanged: (v) {
                                if (!Platform.isWindows) {
                                  HapticFeedback.lightImpact();
                                }
                                ref
                                    .read(routingProvider.notifier)
                                    .toggleRule(rule.id);
                              },
                              activeColor: theme.colorScheme.primary,
                            ),
                            if (Platform.isWindows) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: Colors.grey.shade500,
                                  size: 20,
                                ),
                                onPressed: () {
                                  _showRuleOptions(context, ref, rule, s);
                                },
                                tooltip: s.get('more_actions'),
                              ),
                            ],
                          ],
                        ),
                        onLongPress: Platform.isWindows
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                _showRuleOptions(context, ref, rule, s);
                              },
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildCleanEnginePopup(BuildContext context, WidgetRef ref, S s) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tooltip: s.get('more_actions'),
      onSelected: (value) async {
        if (value == 'clear_all') {
          // TODO: Implement clear all rules if needed
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'clear_all',
          child: _PopupItem(Icons.delete_sweep_rounded, s.get('delete_rule')),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final s = S.of(context, ref);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rule_folder_rounded,
              size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 20),
          Text(
            s.get('no_custom_rules'),
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.get('click_add_rule'),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showRuleOptions(
      BuildContext context, WidgetRef ref, RuleModel rule, S s) {
    if (Platform.isWindows) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(s.get('rule_options'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: Text(s.get('delete_rule'),
                    style: const TextStyle(color: Colors.red)),
                onTap: () {
                  ref.read(routingProvider.notifier).removeRule(rule.id);
                  Navigator.pop(context);
                },
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
      return;
    }

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
              title: Text(s.get('delete_rule'),
                  style: const TextStyle(color: Colors.red)),
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

  String _getRuleSummary(RuleModel rule, S s) {
    List<String> parts = [];
    if (rule.domain != null)
      parts.add('${s.get('domain_label')}: ${rule.domain!.join(", ")}');
    if (rule.ip != null)
      parts.add('${s.get('ip_label')}: ${rule.ip!.join(", ")}');
    if (rule.port != null)
      parts.add('${s.get('port_label')}: ${rule.port!.join(", ")}');
    if (rule.network != null)
      parts.add('${s.get('network_label')}: ${rule.network!.join(", ")}');
    return parts.join(' | ');
  }

  void _showAddRuleDialog(BuildContext context, WidgetRef ref, S s) {
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
          title: Text(
            s.get('add_rule'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: domainController,
                  decoration: InputDecoration(
                    labelText: s.get('domain_comma'),
                    hintText: 'geosite:cn, google.com',
                  ),
                ),
                TextField(
                  controller: ipController,
                  decoration: InputDecoration(
                    labelText: s.get('ip_comma'),
                    hintText: 'geoip:cn, 1.1.1.1',
                  ),
                ),
                TextField(
                  controller: portController,
                  decoration: InputDecoration(
                    labelText: s.get('port_comma'),
                    hintText: '80, 443, 1000-2000',
                  ),
                ),
                TextField(
                  controller: networkController,
                  decoration: InputDecoration(
                    labelText: s.get('protocol_comma'),
                    hintText: 'tcp, udp',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: outboundTag,
                  decoration: InputDecoration(labelText: s.get('action')),
                  items: [
                    DropdownMenuItem(
                      value: 'direct',
                      child: Text(s.get('direct_action')),
                    ),
                    DropdownMenuItem(
                        value: 'proxy', child: Text(s.get('proxy_action'))),
                    DropdownMenuItem(
                        value: 'block', child: Text(s.get('block_action'))),
                  ],
                  onChanged: (v) => setState(() => outboundTag = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.get('cancel')),
            ),
            ElevatedButton(
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(s.get('enter_at_least_one')),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
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
              child: Text(s.get('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  void _showRuleContextMenu(
    BuildContext context,
    WidgetRef ref,
    RuleModel rule,
    Offset offset,
    S s,
  ) async {
    final RelativeRect position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy,
      offset.dx + 1,
      offset.dy + 1,
    );

    final String? selected = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: _PopupItem(Icons.delete_outline_rounded, s.get('delete_rule'),
              color: Colors.redAccent),
        ),
      ],
    );

    if (selected == 'delete') {
      ref.read(routingProvider.notifier).removeRule(rule.id);
    }
  }
}

class _PopupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _PopupItem(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? primaryColor),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
