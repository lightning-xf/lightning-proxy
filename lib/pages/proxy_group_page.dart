import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/proxy_group_model.dart';
import 'package:lightning/core/proxy_group_provider.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/core/localization_provider.dart';

class ProxyGroupPage extends ConsumerStatefulWidget {
  const ProxyGroupPage({super.key});

  @override
  ConsumerState<ProxyGroupPage> createState() => _ProxyGroupPageState();
}

class _ProxyGroupPageState extends ConsumerState<ProxyGroupPage> {
  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(proxyGroupProvider);
    final nodes = ref.watch(nodeProvider);
    final theme = Theme.of(context);
    final s = S.of(context, ref);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(s.get('proxy_groups')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateGroupDialog(),
          ),
        ],
      ),
      body: groups.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.group_work,
                    size: 80,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.get('no_groups'),
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.get('create_group_hint'),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return _buildGroupCard(group, nodes, theme, s);
              },
            ),
    );
  }

  Widget _buildGroupCard(
    ProxyGroupModel group,
    List<NodeModel> allNodes,
    ThemeData theme,
    S s,
  ) {
    final nodeMap = {for (final n in allNodes) n.id: n};
    final groupNodes = group.proxies
        .where((id) => nodeMap.containsKey(id))
        .map((id) => nodeMap[id]!)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getGroupIcon(group.type),
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_getGroupTypeName(group.type, s)} • ${groupNodes.length} ${s.get('nodes')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 20),
                          const SizedBox(width: 8),
                          Text(s.get('edit')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Row(
                        children: [
                          const Icon(Icons.copy, size: 20),
                          const SizedBox(width: 8),
                          Text(s.get('duplicate')),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete, size: 20, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            s.get('delete'),
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) => _handleGroupAction(value, group),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (groupNodes.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: groupNodes.length,
                  itemBuilder: (context, index) {
                    final node = groupNodes[index];
                    return _buildNodeChip(node, theme);
                  },
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showEditGroupDialog(group),
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text(s.get('manage_nodes')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      foregroundColor: theme.colorScheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeChip(NodeModel node, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            node.protocol.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.primary.withOpacity(0.7),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getGroupIcon(ProxyGroupType type) {
    switch (type) {
      case ProxyGroupType.select:
        return Icons.radio_button_checked;
      case ProxyGroupType.urlTest:
        return Icons.speed;
      case ProxyGroupType.fallback:
        return Icons.swap_horiz;
      case ProxyGroupType.loadBalance:
        return Icons.shuffle;
      case ProxyGroupType.relay:
        return Icons.link;
    }
  }

  String _getGroupTypeName(ProxyGroupType type, S s) {
    switch (type) {
      case ProxyGroupType.select:
        return s.get('select');
      case ProxyGroupType.urlTest:
        return s.get('url_test');
      case ProxyGroupType.fallback:
        return s.get('fallback');
      case ProxyGroupType.loadBalance:
        return s.get('load_balance');
      case ProxyGroupType.relay:
        return s.get('relay');
    }
  }

  void _handleGroupAction(String action, ProxyGroupModel group) {
    switch (action) {
      case 'edit':
        _showEditGroupDialog(group);
        break;
      case 'duplicate':
        final newGroup = group.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '${group.name} (Copy)',
        );
        ref.read(proxyGroupProvider.notifier).addGroup(newGroup);
        break;
      case 'delete':
        _showDeleteConfirmDialog(group);
        break;
    }
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => _GroupDialog(
        onSave: (group) {
          ref.read(proxyGroupProvider.notifier).addGroup(group);
        },
      ),
    );
  }

  void _showEditGroupDialog(ProxyGroupModel group) {
    showDialog(
      context: context,
      builder: (context) => _GroupDialog(
        group: group,
        onSave: (updatedGroup) {
          ref.read(proxyGroupProvider.notifier).updateGroup(updatedGroup);
        },
      ),
    );
  }

  void _showDeleteConfirmDialog(ProxyGroupModel group) {
    final s = S.of(context, ref);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('delete_group')),
        content: Text('${s.get('delete_group_confirm')} "${group.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(proxyGroupProvider.notifier).removeGroup(group.id);
              Navigator.pop(context);
            },
            child: Text(s.get('delete')),
          ),
        ],
      ),
    );
  }
}

class _GroupDialog extends ConsumerStatefulWidget {
  final ProxyGroupModel? group;
  final void Function(ProxyGroupModel) onSave;

  const _GroupDialog({
    this.group,
    required this.onSave,
  });

  @override
  ConsumerState<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends ConsumerState<_GroupDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _intervalController = TextEditingController(text: '300');
  final _toleranceController = TextEditingController(text: '150');
  ProxyGroupType _type = ProxyGroupType.select;
  String _strategy = 'round-robin';
  final List<String> _selectedNodes = [];
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    if (widget.group != null) {
      final group = widget.group!;
      _nameController.text = group.name;
      _type = group.type;
      _urlController.text = group.url ?? 'http://www.gstatic.com/generate_204';
      _intervalController.text = (group.interval ?? 300).toString();
      _toleranceController.text = (group.tolerance ?? 150).toString();
      _strategy = group.strategy ?? 'round-robin';
      _selectedNodes.addAll(group.proxies);
      _hidden = group.hidden;
    } else {
      _urlController.text = 'http://www.gstatic.com/generate_204';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _intervalController.dispose();
    _toleranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allNodes = ref.watch(nodeProvider);
    final s = S.of(context, ref);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.group != null ? s.get('edit_group') : s.get('create_group')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: s.get('group_name'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildTypeSelector(theme, s),
              const SizedBox(height: 16),
              if (_type == ProxyGroupType.urlTest || _type == ProxyGroupType.fallback) ...[
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: s.get('test_url'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: s.get('interval_seconds'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_type == ProxyGroupType.urlTest) ...[
                TextField(
                  controller: _toleranceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: s.get('tolerance_ms'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_type == ProxyGroupType.loadBalance) ...[
                _buildStrategySelector(theme, s),
                const SizedBox(height: 16),
              ],
              SwitchListTile(
                title: Text(s.get('hidden')),
                value: _hidden,
                onChanged: (value) => setState(() => _hidden = value),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              Text(
                s.get('select_nodes'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _buildNodeSelector(allNodes, theme, s),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.get('cancel')),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(s.get('save')),
        ),
      ],
    );
  }

  Widget _buildTypeSelector(ThemeData theme, S s) {
    final types = [
      ProxyGroupType.select,
      ProxyGroupType.urlTest,
      ProxyGroupType.fallback,
      ProxyGroupType.loadBalance,
      ProxyGroupType.relay,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.get('group_type'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: types.map((type) {
            final isSelected = _type == type;
            return FilterChip(
              label: Text(_getGroupTypeName(type, s)),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _type = type);
                }
              },
              selectedColor: theme.colorScheme.primary.withOpacity(0.2),
              checkmarkColor: theme.colorScheme.primary,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStrategySelector(ThemeData theme, S s) {
    final strategies = ['round-robin', 'consistent-hashing'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.get('strategy'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: strategies.map((strategy) {
            final isSelected = _strategy == strategy;
            return FilterChip(
              label: Text(strategy),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _strategy = strategy);
                }
              },
              selectedColor: theme.colorScheme.primary.withOpacity(0.2),
              checkmarkColor: theme.colorScheme.primary,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNodeSelector(List<NodeModel> allNodes, ThemeData theme, S s) {
    if (allNodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(s.get('no_nodes_available')),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        borderRadius: BorderRadius.circular(12),
      ),
      height: 200,
      child: ListView.builder(
        itemCount: allNodes.length,
        itemBuilder: (context, index) {
          final node = allNodes[index];
          final isSelected = _selectedNodes.contains(node.id);
          return CheckboxListTile(
            title: Text(node.name),
            subtitle: Text(node.protocol.toUpperCase()),
            value: isSelected,
            onChanged: (selected) {
              setState(() {
                if (selected == true) {
                  _selectedNodes.add(node.id);
                } else {
                  _selectedNodes.remove(node.id);
                }
              });
            },
            dense: true,
          );
        },
      ),
    );
  }

  String _getGroupTypeName(ProxyGroupType type, S s) {
    switch (type) {
      case ProxyGroupType.select:
        return s.get('select');
      case ProxyGroupType.urlTest:
        return s.get('url_test');
      case ProxyGroupType.fallback:
        return s.get('fallback');
      case ProxyGroupType.loadBalance:
        return s.get('load_balance');
      case ProxyGroupType.relay:
        return s.get('relay');
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入组名')),
      );
      return;
    }

    final group = ProxyGroupModel(
      id: widget.group?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: _type,
      proxies: List.from(_selectedNodes),
      url: _type == ProxyGroupType.urlTest || _type == ProxyGroupType.fallback
          ? _urlController.text
          : null,
      interval: _type == ProxyGroupType.urlTest || _type == ProxyGroupType.fallback
          ? int.tryParse(_intervalController.text)
          : null,
      tolerance: _type == ProxyGroupType.urlTest
          ? int.tryParse(_toleranceController.text)
          : null,
      strategy: _type == ProxyGroupType.loadBalance ? _strategy : null,
      hidden: _hidden,
      order: widget.group?.order ?? 0,
    );

    widget.onSave(group);
    Navigator.pop(context);
  }
}
