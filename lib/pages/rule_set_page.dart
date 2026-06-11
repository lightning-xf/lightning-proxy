import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/rule_set_model.dart';
import 'package:lightning/core/rule_set_provider.dart';
import 'package:lightning/core/localization_provider.dart';

class RuleSetPage extends ConsumerStatefulWidget {
  const RuleSetPage({super.key});

  @override
  ConsumerState<RuleSetPage> createState() => _RuleSetPageState();
}

class _RuleSetPageState extends ConsumerState<RuleSetPage> {
  final Set<String> _updatingIds = {};

  // 常用规则集预设
  static const List<Map<String, String>> _presetRuleSets = [
    {
      'name': 'Loyalsoldier 中国域名规则',
      'url':
          'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt',
      'format': 'text',
      'behavior': 'domain',
    },
    {
      'name': 'Loyalsoldier 代理域名规则',
      'url':
          'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt',
      'format': 'text',
      'behavior': 'domain',
    },
    {
      'name': 'Loyalsoldier 中国IP规则',
      'url':
          'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/cncidr.txt',
      'format': 'text',
      'behavior': 'ipcidr',
    },
    {
      'name': 'Loyalsoldier 广告拦截',
      'url':
          'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt',
      'format': 'text',
      'behavior': 'domain',
    },
    {
      'name': 'ACL4SSR 完整规则集',
      'url':
          'https://github.com/ACL4SSR/ACL4SSR/raw/master/Clash/config/ACL4SSR.ini',
      'format': 'yaml',
      'behavior': 'classical',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final ruleSets = ref.watch(ruleSetProvider);
    final theme = Theme.of(context);
    final s = S.of(context, ref);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          s.get('rule_sets'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_add, size: 24),
            onPressed: () => _showPresetSelector(),
            tooltip: s.get('preset_rule_sets'),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 28),
            onPressed: () => _showCreateRuleSetDialog(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ruleSets.isEmpty
          ? _buildEmptyState(theme, s)
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: ruleSets.length,
              itemBuilder: (context, index) {
                final ruleSet = ruleSets[index];
                return _buildRuleSetCard(ruleSet, theme, s);
              },
            ),
    );
  }

  Widget _buildRuleSetCard(RuleSetModel ruleSet, ThemeData theme, S s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
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
                    _getBehaviorIcon(ruleSet.behavior),
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
                        ruleSet.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_getBehaviorName(ruleSet.behavior, s)} • ${_getFormatName(ruleSet.format, s)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: ruleSet.enabled,
                  onChanged: (value) {
                    final updated = ruleSet.copyWith(enabled: value);
                    ref.read(ruleSetProvider.notifier).updateRuleSet(updated);
                  },
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'update',
                      child: Row(
                        children: [
                          const Icon(Icons.refresh, size: 20),
                          const SizedBox(width: 8),
                          Text(s.get('update_rule_set')),
                        ],
                      ),
                    ),
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
                  onSelected: (value) => _handleRuleSetAction(value, ruleSet),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              ruleSet.url,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (ruleSet.lastUpdated != null) ...[
              const SizedBox(height: 8),
              Text(
                '${s.get('last_updated')}: ${_formatDate(ruleSet.lastUpdated!)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditRuleSetDialog(ruleSet),
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text(s.get('edit')),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                      ),
                      foregroundColor: theme.colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _updateRuleSet(ruleSet),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(s.get('update')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary.withOpacity(
                        0.1,
                      ),
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

  IconData _getBehaviorIcon(RuleSetBehavior behavior) {
    switch (behavior) {
      case RuleSetBehavior.domain:
        return Icons.domain;
      case RuleSetBehavior.ipcidr:
        return Icons.network_check;
      case RuleSetBehavior.classical:
        return Icons.rule;
    }
  }

  String _getBehaviorName(RuleSetBehavior behavior, S s) {
    switch (behavior) {
      case RuleSetBehavior.domain:
        return s.get('domain');
      case RuleSetBehavior.ipcidr:
        return s.get('ip_cidr');
      case RuleSetBehavior.classical:
        return s.get('classical');
    }
  }

  String _getFormatName(RuleSetFormat format, S s) {
    switch (format) {
      case RuleSetFormat.yaml:
        return 'YAML';
      case RuleSetFormat.json:
        return 'JSON';
      case RuleSetFormat.text:
        return 'TEXT';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _handleRuleSetAction(String action, RuleSetModel ruleSet) {
    switch (action) {
      case 'update':
        _updateRuleSet(ruleSet);
        break;
      case 'edit':
        _showEditRuleSetDialog(ruleSet);
        break;
      case 'duplicate':
        final newRuleSet = ruleSet.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '${ruleSet.name} (Copy)',
        );
        ref.read(ruleSetProvider.notifier).addRuleSet(newRuleSet);
        break;
      case 'delete':
        _showDeleteConfirmDialog(ruleSet);
        break;
    }
  }

  Future<void> _updateRuleSet(RuleSetModel ruleSet) async {
    final s = S.of(context, ref);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${s.get('updating')} ${ruleSet.name}...')),
    );
    await ref.read(ruleSetProvider.notifier).refreshRuleSet(ruleSet.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ruleSet.name} ${s.get('updated')}')),
      );
    }
  }

  void _showCreateRuleSetDialog() {
    showDialog(
      context: context,
      builder: (context) => _RuleSetDialog(
        onSave: (ruleSet) {
          ref.read(ruleSetProvider.notifier).addRuleSet(ruleSet);
        },
      ),
    );
  }

  void _showEditRuleSetDialog(RuleSetModel ruleSet) {
    showDialog(
      context: context,
      builder: (context) => _RuleSetDialog(
        ruleSet: ruleSet,
        onSave: (updated) {
          ref.read(ruleSetProvider.notifier).updateRuleSet(updated);
        },
      ),
    );
  }

  void _showDeleteConfirmDialog(RuleSetModel ruleSet) {
    final s = S.of(context, ref);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s.get('delete_rule_set')),
        content: Text('${s.get('delete_rule_set_confirm')} "${ruleSet.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              s.get('cancel'),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              ref.read(ruleSetProvider.notifier).removeRuleSet(ruleSet.id);
              Navigator.pop(context);
            },
            child: Text(s.get('delete')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, S s) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.list_alt_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              s.get('no_rule_sets'),
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey[700],
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              s.get('create_rule_set_hint'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showPresetSelector(),
              icon: const Icon(Icons.library_add),
              label: Text(s.get('add_preset_rule_set')),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPresetSelector() {
    final s = S.of(context, ref);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.get('preset_rule_sets'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: _presetRuleSets.length,
                  itemBuilder: (context, index) {
                    final preset = _presetRuleSets[index];
                    return _buildPresetCard(preset, theme, s);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetCard(Map<String, String> preset, ThemeData theme, S s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _addPresetRuleSet(preset);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.cloud_download_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset['name']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              preset['format']!.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              preset['behavior']!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.add_circle_outline_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addPresetRuleSet(Map<String, String> preset) {
    final format = _parseFormat(preset['format']!);
    final behavior = _parseBehavior(preset['behavior']!);

    final ruleSet = RuleSetModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: preset['name']!,
      url: preset['url']!,
      format: format,
      behavior: behavior,
      enabled: true,
      order: 0,
    );

    ref.read(ruleSetProvider.notifier).addRuleSet(ruleSet);
    Navigator.pop(context);

    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${preset['name']!} 已添加'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  RuleSetFormat _parseFormat(String format) {
    switch (format.toLowerCase()) {
      case 'yaml':
        return RuleSetFormat.yaml;
      case 'json':
        return RuleSetFormat.json;
      case 'text':
      default:
        return RuleSetFormat.text;
    }
  }

  RuleSetBehavior _parseBehavior(String behavior) {
    switch (behavior.toLowerCase()) {
      case 'ipcidr':
        return RuleSetBehavior.ipcidr;
      case 'classical':
        return RuleSetBehavior.classical;
      case 'domain':
      default:
        return RuleSetBehavior.domain;
    }
  }
}

class _RuleSetDialog extends ConsumerStatefulWidget {
  final RuleSetModel? ruleSet;
  final void Function(RuleSetModel) onSave;

  const _RuleSetDialog({this.ruleSet, required this.onSave});

  @override
  ConsumerState<_RuleSetDialog> createState() => _RuleSetDialogState();
}

class _RuleSetDialogState extends ConsumerState<_RuleSetDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _intervalController = TextEditingController();
  RuleSetFormat _format = RuleSetFormat.yaml;
  RuleSetBehavior _behavior = RuleSetBehavior.domain;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    if (widget.ruleSet != null) {
      final rs = widget.ruleSet!;
      _nameController.text = rs.name;
      _urlController.text = rs.url;
      _format = rs.format;
      _behavior = rs.behavior;
      _intervalController.text = rs.interval?.toString() ?? '';
      _enabled = rs.enabled;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context, ref);
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.ruleSet != null
            ? s.get('edit_rule_set')
            : s.get('create_rule_set'),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                controller: _nameController,
                label: s.get('rule_set_name'),
                hint: s.get('rule_set_name'),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _urlController,
                label: s.get('rule_set_url'),
                hint: 'https://example.com/rules.txt',
              ),
              const SizedBox(height: 16),
              _buildFormatSelector(theme, s),
              const SizedBox(height: 16),
              _buildBehaviorSelector(theme, s),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _intervalController,
                label: s.get('update_interval_hours'),
                hint: s.get('optional'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.get('enabled'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Switch(
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                      activeColor: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(s.get('save')),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
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
      ],
    );
  }

  Widget _buildFormatSelector(ThemeData theme, S s) {
    final formats = RuleSetFormat.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.get('format'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: formats.map((format) {
            final isSelected = _format == format;
            return FilterChip(
              label: Text(_getFormatName(format, s)),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _format = format);
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

  Widget _buildBehaviorSelector(ThemeData theme, S s) {
    final behaviors = RuleSetBehavior.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.get('behavior'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: behaviors.map((behavior) {
            final isSelected = _behavior == behavior;
            return FilterChip(
              label: Text(_getBehaviorName(behavior, s)),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _behavior = behavior);
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

  String _getFormatName(RuleSetFormat format, S s) {
    switch (format) {
      case RuleSetFormat.yaml:
        return 'YAML';
      case RuleSetFormat.json:
        return 'JSON';
      case RuleSetFormat.text:
        return 'TEXT';
    }
  }

  String _getBehaviorName(RuleSetBehavior behavior, S s) {
    switch (behavior) {
      case RuleSetBehavior.domain:
        return s.get('domain');
      case RuleSetBehavior.ipcidr:
        return s.get('ip_cidr');
      case RuleSetBehavior.classical:
        return s.get('classical');
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写完整信息')));
      return;
    }

    final ruleSet = RuleSetModel(
      id:
          widget.ruleSet?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      url: url,
      format: _format,
      behavior: _behavior,
      interval: _intervalController.text.isNotEmpty
          ? int.tryParse(_intervalController.text)
          : null,
      lastUpdated: widget.ruleSet?.lastUpdated,
      enabled: _enabled,
      order: widget.ruleSet?.order ?? 0,
    );

    widget.onSave(ruleSet);
    Navigator.pop(context);
  }
}
