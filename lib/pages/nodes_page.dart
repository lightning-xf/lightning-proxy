import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lightning/core/link_parser.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/log_provider.dart';
import 'package:lightning/core/consistency_checker.dart';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/subscription_provider.dart';
import 'package:lightning/core/subscription_model.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lightning/pages/node_edit_dialog.dart';

class _PopupItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PopupItem(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class NodesPageState {
  final Set<String> selectedIds;
  final bool isSelectionMode;
  final bool isSearching;
  final String searchQuery;

  NodesPageState({
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.isSearching = false,
    this.searchQuery = '',
  });

  NodesPageState copyWith({
    Set<String>? selectedIds,
    bool? isSelectionMode,
    bool? isSearching,
    String? searchQuery,
  }) {
    return NodesPageState(
      selectedIds: selectedIds ?? this.selectedIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      isSearching: isSearching ?? this.isSearching,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class NodesPageNotifier extends StateNotifier<NodesPageState> {
  NodesPageNotifier() : super(NodesPageState());

  void setSearching(bool searching) => state = state.copyWith(
    isSearching: searching,
    searchQuery: searching ? state.searchQuery : '',
  );
  void setSearchQuery(String query) => state = state.copyWith(searchQuery: query);
  void setSelectionMode(bool selectionMode) => state = state.copyWith(
    isSelectionMode: selectionMode,
    selectedIds: selectionMode ? state.selectedIds : {},
  );
  void toggleSelection(String id) {
    final newIds = Set<String>.from(state.selectedIds);
    if (newIds.contains(id)) {
      newIds.remove(id);
    } else {
      newIds.add(id);
    }
    state = state.copyWith(selectedIds: newIds, isSelectionMode: newIds.isNotEmpty);
  }
  void selectAll(List<String> ids) => state = state.copyWith(selectedIds: Set.from(ids), isSelectionMode: true);
  void clearSelection() => state = state.copyWith(selectedIds: {}, isSelectionMode: false);
}

final nodesPageUIProvider = StateNotifierProvider<NodesPageNotifier, NodesPageState>((ref) => NodesPageNotifier());

class NodesPage extends ConsumerStatefulWidget {
  const NodesPage({super.key});

  @override
  ConsumerState<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends ConsumerState<NodesPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(nodesPageUIProvider);
    final selectedNode = ref.watch(selectedNodeProvider);
    final theme = Theme.of(context);
    final s = S.of(context, ref);
    final allNodes = ref.watch(nodeProvider);
    final subscriptions = ref.watch(subscriptionProvider);
    
    // Grouping logic
    final filteredNodes = uiState.searchQuery.isEmpty
        ? allNodes
        : allNodes
              .where(
                (n) =>
                    n.name.toLowerCase().contains(uiState.searchQuery.toLowerCase()) ||
                    n.address.toLowerCase().contains(
                      uiState.searchQuery.toLowerCase(),
                    ),
              )
              .toList();

    // Group nodes by subscriptionId
    final Map<String?, List<NodeModel>> groupedNodes = {};
    for (var node in filteredNodes) {
      groupedNodes.putIfAbsent(node.subscriptionId, () => []).add(node);
    }

    // Prepare groups for display
    final List<MapEntry<String?, List<NodeModel>>> visibleGroups = [];
    
    // 1. Subscription groups first
    for (var sub in subscriptions) {
      if (groupedNodes.containsKey(sub.id)) {
        visibleGroups.add(MapEntry(sub.id, groupedNodes[sub.id]!));
      }
    }

    // 2. Manual group (null subscriptionId) last
    if (groupedNodes.containsKey(null)) {
      visibleGroups.add(MapEntry(null, groupedNodes[null]!));
    }

    final bool isMobile = MediaQuery.of(context).size.width < 720;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: isMobile
          ? AppBar(
              leading: IconButton(
                icon: Icon(Icons.menu_rounded, color: theme.colorScheme.primary),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Scaffold.of(context).openDrawer();
                },
              ),
              titleSpacing: 0,
              title: uiState.isSearching
                  ? Container(
                      height: 40,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '搜索节点...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                        ),
                        onChanged: (v) => ref.read(nodesPageUIProvider.notifier).setSearchQuery(v),
                      ),
                    )
                  : Text(
                      uiState.isSelectionMode
                          ? '已选择 ${uiState.selectedIds.length}'
                          : s.get('nodes_manage'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
              actions: [
                if (!uiState.isSelectionMode) ...[
                  if (uiState.isSearching)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        ref.read(nodesPageUIProvider.notifier).setSearching(false);
                        _searchController.clear();
                      },
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.search_rounded, size: 22),
                      onPressed: () => ref.read(nodesPageUIProvider.notifier).setSearching(true),
                    ),
                  if (!uiState.isSearching) ...[
                    PopupMenuButton<String>(
                      offset: const Offset(0, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                      onSelected: (value) {
                        HapticFeedback.lightImpact();
                        _handleAddAction(value);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'import_link',
                          child: _PopupItem(Icons.content_paste_rounded, '导入剪贴板链接'),
                        ),
                        const PopupMenuItem(
                          value: 'import_file',
                          child: _PopupItem(Icons.file_open_rounded, '从文件导入'),
                        ),
                        const PopupMenuItem(
                          value: 'scan_qr',
                          child: _PopupItem(Icons.qr_code_scanner_rounded, '扫描二维码'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'sort_latency',
                          child: _PopupItem(Icons.sort_rounded, '按延迟排序'),
                        ),
                        const PopupMenuItem(
                          value: 'sort_name',
                          child: _PopupItem(Icons.sort_by_alpha_rounded, '按名称排序'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'manual_vmess',
                          child: _PopupItem(Icons.add_rounded, '手动添加 VMess'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_vless',
                          child: _PopupItem(Icons.add_rounded, '手动添加 VLESS'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_trojan',
                          child: _PopupItem(Icons.add_rounded, '手动添加 Trojan'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_ss',
                          child: _PopupItem(Icons.add_rounded, '手动添加 Shadowsocks'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_socks',
                          child: _PopupItem(Icons.add_rounded, '手动添加 SOCKS'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_hysteria2',
                          child: _PopupItem(Icons.add_rounded, '手动添加 Hysteria2'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_tuic',
                          child: _PopupItem(Icons.add_rounded, '手动添加 TUIC'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_wireguard',
                          child: _PopupItem(Icons.add_rounded, '手动添加 WireGuard'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'deduplicate',
                          child: _PopupItem(Icons.cleaning_services_rounded, '自动去重'),
                        ),
                      ],
                    ),
                  ],
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.share_rounded, size: 20),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      _batchExport(uiState.selectedIds);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      _batchDelete(uiState.selectedIds);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.select_all_rounded, size: 20),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ref.read(nodesPageUIProvider.notifier).selectAll(allNodes.map((n) => n.id).toList());
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ref.read(nodesPageUIProvider.notifier).clearSelection();
                    },
                  ),
                ],
              ],
            )
          : null,
      body: Column(
        children: [
          if (!isMobile) _buildHeader(theme, uiState, filteredNodes, s),
          Expanded(
            child: visibleGroups.isEmpty && uiState.searchQuery.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: visibleGroups.length,
                    itemBuilder: (context, groupIndex) {
                      final entry = visibleGroups[groupIndex];
                      final subId = entry.key;
                      final groupNodes = entry.value;
                      
                      String title;
                      String subtitle;
                      IconData icon;
                      
                      if (subId == null) {
                        title = '手动导入';
                        subtitle = '${groupNodes.length} 个节点';
                        icon = Icons.input_rounded;
                      } else {
                        final sub = subscriptions.firstWhere((s) => s.id == subId);
                        title = sub.name;
                        subtitle = sub.url;
                        icon = Icons.rss_feed_rounded;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.05),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                          clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
                          child: Theme(
                            data: theme.copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                            key: PageStorageKey(subId ?? 'manual'),
                            initiallyExpanded: false,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, color: theme.colorScheme.primary, size: 20),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${groupNodes.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 11, 
                                color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.speed_rounded, color: theme.colorScheme.primary.withOpacity(0.7), size: 20),
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                _showLatencyTestOptions(groupNodes);
                              },
                              tooltip: '测试该组延迟',
                            ),
                            childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            children: groupNodes.map((node) {
                              final isSelected = selectedNode?.id == node.id;
                              final isMultiSelected = uiState.selectedIds.contains(node.id);
                              
                              return _buildNodeItem(context, node, isSelected, isMultiSelected, uiState, theme);
                            }).toList(),
                          ),
                        ),
                      ),
                    );
                  },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeItem(
    BuildContext context, 
    NodeModel node, 
    bool isSelected, 
    bool isMultiSelected, 
    NodesPageState uiState, 
    ThemeData theme
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary.withOpacity(0.08)
            : theme.colorScheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.4)
              : Colors.white.withOpacity(0.04),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
        child: InkWell(
          onTap: () {
            if (uiState.isSelectionMode) {
              ref.read(nodesPageUIProvider.notifier).toggleSelection(node.id);
            } else {
              ref.read(selectedNodeProvider.notifier).setNode(node);
              // Quick switch if VPN is running
              if (ref.read(vpnProvider).isRunning) {
                ref.read(vpnProvider.notifier).toggleVpn(node);
              }
            }
          },
          onLongPress: () {
            if (uiState.isSelectionMode) {
              ref.read(nodesPageUIProvider.notifier).toggleSelection(node.id);
            } else {
              HapticFeedback.heavyImpact();
              _showNodeOptions(node);
            }
          },
          child: Container(
            key: ValueKey(node.id),
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            child: Row(
              children: [
                uiState.isSelectionMode
                    ? _buildSelectionIndicator(isMultiSelected, theme)
                    : _buildProtocolIcon(node),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        node.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 14,
                          color: isSelected ? theme.colorScheme.primary : theme.textTheme.titleMedium?.color,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                node.protocol.toUpperCase(),
                                style: TextStyle(
                                  color: theme.colorScheme.primary.withOpacity(0.7),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                node.address,
                                style: TextStyle(
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildTrailing(node),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, NodesPageState uiState, List<NodeModel> nodes, S s) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (!uiState.isSearching) ...[
            Text(
              uiState.isSelectionMode ? '已选择 ${uiState.selectedIds.length}' : s.get('nodes_manage'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
          if (uiState.isSearching)
            Expanded(
              child: Container(
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '搜索节点...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  onChanged: (v) => ref.read(nodesPageUIProvider.notifier).setSearchQuery(v),
                ),
              ),
            )
          else
            const Spacer(),
          if (!uiState.isSelectionMode) ...[
            if (uiState.isSearching)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  ref.read(nodesPageUIProvider.notifier).setSearching(false);
                  _searchController.clear();
                },
              )
            else
              IconButton(
                icon: const Icon(Icons.search_rounded, size: 22),
                onPressed: () => ref.read(nodesPageUIProvider.notifier).setSearching(true),
              ),
            if (!uiState.isSearching) ...[
              PopupMenuButton<String>(
                offset: const Offset(0, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                onSelected: (value) {
                  HapticFeedback.lightImpact();
                  _handleAddAction(value);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'import_link',
                    child: _PopupItem(Icons.content_paste_rounded, '导入剪贴板链接'),
                  ),
                  const PopupMenuItem(
                    value: 'scan_qr',
                    child: _PopupItem(Icons.qr_code_scanner_rounded, '扫描二维码'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'sort_latency',
                    child: _PopupItem(Icons.sort_rounded, '按延迟排序'),
                  ),
                  const PopupMenuItem(
                    value: 'sort_name',
                    child: _PopupItem(Icons.sort_by_alpha_rounded, '按名称排序'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'manual_vmess',
                    child: _PopupItem(Icons.add_rounded, '手动添加 VMess'),
                  ),
                  const PopupMenuItem(
                    value: 'manual_vless',
                    child: _PopupItem(Icons.add_rounded, '手动添加 VLESS'),
                  ),
                  const PopupMenuItem(
                    value: 'manual_trojan',
                    child: _PopupItem(Icons.add_rounded, '手动添加 Trojan'),
                  ),
                  const PopupMenuItem(
                    value: 'manual_ss',
                    child: _PopupItem(Icons.add_rounded, '手动添加 Shadowsocks'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'deduplicate',
                    child: _PopupItem(Icons.cleaning_services_rounded, '自动去重'),
                  ),
                ],
              ),
            ],
          ] else ...[
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
              onPressed: () {
                HapticFeedback.mediumImpact();
                _batchExport(uiState.selectedIds);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: () {
                HapticFeedback.mediumImpact();
                _batchDelete(uiState.selectedIds);
              },
            ),
            IconButton(
              icon: const Icon(Icons.select_all_rounded, size: 20),
              onPressed: () {
                HapticFeedback.lightImpact();
                ref.read(nodesPageUIProvider.notifier).selectAll(nodes.map((n) => n.id).toList());
              },
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () {
                HapticFeedback.lightImpact();
                ref.read(nodesPageUIProvider.notifier).clearSelection();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_rounded, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 20),
          Text(
            '暂无可用节点',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角按钮添加或导入',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionIndicator(bool isSelected, ThemeData theme) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? theme.colorScheme.primary : Colors.grey.shade800,
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 24)
          : null,
    );
  }

  Widget _buildProtocolIcon(NodeModel node) {
    final color = _getProtocolColor(node.protocol);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          node.protocol[0].toUpperCase(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildTrailing(NodeModel node) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (node.latency != null)
          GestureDetector(
            onTap: () => ref.read(nodeProvider.notifier).testLatency(node.id, useTcpPing: false),
            onLongPress: () {
              HapticFeedback.selectionClick();
              ref.read(nodeProvider.notifier).testLatency(node.id, useTcpPing: true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已触发快速 TCP 测延迟'), duration: Duration(seconds: 1)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _getLatencyColor(node.latency!).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: node.latency == -1
                  ? const _TestingAnimation()
                  : Text(
                      node.latency == -2 ? '超时' : '${node.latency}ms',
                      style: TextStyle(
                        color: _getLatencyColor(node.latency!),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(
            node.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 24,
            color: node.isFavorite ? Colors.amber : Colors.grey.shade700,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(nodeProvider.notifier).toggleFavorite(node.id);
          },
        ),
      ],
    );
  }

  Color _getLatencyColor(int latency) {
    if (latency == -1) return Colors.blue;
    if (latency == -2) return Colors.red;
    if (latency < 200) return const Color(0xFF4ADE80);
    if (latency < 500) return Colors.orange;
    return Colors.red;
  }

  Color _getProtocolColor(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'vmess': return Colors.blueAccent;
      case 'vless': return Colors.orangeAccent;
      case 'trojan': return Colors.purpleAccent;
      case 'shadowsocks':
      case 'ss': return Colors.greenAccent;
      default: return Colors.grey;
    }
  }

  void _showNodeOptions(NodeModel node) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑节点'),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(node, node.protocol);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制链接'),
              onTap: () {
                final link = _generateLink(node);
                Clipboard.setData(ClipboardData(text: link));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('链接已复制到剪贴板'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded),
              title: const Text('二维码分享'),
              onTap: () {
                Navigator.pop(context);
                _showShareDialog(node);
              },
            ),
            ListTile(
              leading: const Icon(Icons.select_all_outlined),
              title: const Text('多选模式'),
              onTap: () {
                Navigator.pop(context);
                ref.read(nodesPageUIProvider.notifier).toggleSelection(node.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除节点', style: TextStyle(color: Colors.red)),
              onTap: () {
                ref.read(nodeProvider.notifier).removeNode(node.id);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _batchDelete(Set<String> selectedIds) {
    for (final id in selectedIds) {
      ref.read(nodeProvider.notifier).removeNode(id);
    }
    ref.read(nodesPageUIProvider.notifier).clearSelection();
  }

  void _batchExport(Set<String> selectedIds) {
    final nodes = ref.read(nodeProvider);
    final selectedNodes = nodes
        .where((n) => selectedIds.contains(n.id))
        .toList();
    if (selectedNodes.isEmpty) return;

    final List<String> links = [];
    for (var node in selectedNodes) {
      links.add(_generateLink(node));
    }

    final String exportText = links.join('\n');
    Clipboard.setData(ClipboardData(text: exportText));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已将 ${selectedNodes.length} 个节点导出到剪贴板'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    ref.read(nodesPageUIProvider.notifier).clearSelection();
  }

  void _showShareDialog(NodeModel node) {
    final link = _generateLink(node);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(node.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '扫描二维码导入节点',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('链接已复制到剪贴板'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('复制链接'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _generateLink(NodeModel node) {
    if (node.protocol == 'vmess') {
      // Use rawData as base to ensure 100% fidelity for non-modified fields
      final Map<String, dynamic> data = node.rawData != null 
          ? Map<String, dynamic>.from(node.rawData!) 
          : {
              "v": "2",
              "aid": "0",
            };
      
      // Overlay current values from node model (which might have been edited)
      data["ps"] = node.name;
      data["add"] = node.address;
      data["port"] = node.port;
      data["id"] = node.uuid;
      data["net"] = node.network;
      data["type"] = node.type ?? "none";
      data["host"] = node.host;
      data["path"] = node.path;
      data["tls"] = node.security == 'tls' ? 'tls' : '';
      data["sni"] = node.sni;
      data["scy"] = node.encryption ?? "auto";

      final exportedJson = jsonEncode(data);
      final exportedLink = "vmess://${base64.encode(utf8.encode(exportedJson))}";
      
      // Consistency check: If we have rawData, compare key fields
      if (node.rawData != null) {
        final originalJson = jsonEncode(node.rawData);
        if (originalJson != exportedJson) {
          debugPrint("VMess configuration consistency note: Fields might have been updated by user or model.");
        }
      }

      return exportedLink;
    }

    final query = node.rawData != null 
        ? Map<String, String>.from(node.rawData!.map((k, v) => MapEntry(k, v.toString()))) 
        : <String, String>{};
    
    // Overlay current values
    if (node.network != null) query['type'] = node.network!;
    if (node.security != null) query['security'] = node.security!;
    if (node.sni != null && node.sni!.isNotEmpty) query['sni'] = node.sni!;
    if (node.host != null && node.host!.isNotEmpty) query['host'] = node.host!;
    if (node.path != null && node.path!.isNotEmpty) query['path'] = node.path!;
    if (node.type != null && node.type != 'none') query['headerType'] = node.type!;
    if (node.publicKey != null && node.publicKey!.isNotEmpty) query['pbk'] = node.publicKey!;
    if (node.fingerPrint != null && node.fingerPrint!.isNotEmpty) query['fp'] = node.fingerPrint!;
    if (node.flow != null && node.flow!.isNotEmpty) query['flow'] = node.flow!;
    if (node.serviceName != null && node.serviceName!.isNotEmpty) query['serviceName'] = node.serviceName!;
    if (node.encryption != null && node.encryption != 'none') query['encryption'] = node.encryption!;

    final uri = Uri(
      scheme: node.protocol,
      userInfo: node.protocol == 'shadowsocks' || node.protocol == 'ss'
          ? "${node.method}:${node.password}"
          : (node.uuid ?? node.password ?? node.username),
      host: node.address,
      port: node.port,
      queryParameters: query.isEmpty ? null : query,
      fragment: Uri.encodeComponent(node.name),
    );

    return uri.toString();
  }

  void _testAllLatencies(List<NodeModel> nodes, {bool useTcpPing = false}) async {
    final isRunning = ref.read(vpnProvider).isRunning;
    
    if (!useTcpPing && isRunning && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('测延迟提示'),
          content: const Text('进行真实链路测延迟会暂时断开当前的 VPN 连接，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final modeText = useTcpPing ? 'TCP Ping' : '真实链路';
    ref
        .read(logProvider.notifier)
        .addLog('info', '开始针对该组节点测延迟($modeText)，共 ${nodes.length} 个节点');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在开始 $modeText 测延迟...'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Only test latencies for the specified group of nodes
    for (var node in nodes) {
      ref.read(nodeProvider.notifier).testLatency(node.id, useTcpPing: useTcpPing);
      // Optional: add a small delay to avoid overwhelming the system
      await Future.delayed(const Duration(milliseconds: 100));
    }

    ref.read(logProvider.notifier).addLog('info', '该组测延迟任务已完成');

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('测延迟任务已开始')));
    }
  }

  void _showLatencyTestOptions(List<NodeModel> nodes) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.speed_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  '批量节点测延迟',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildTestOption(
              context: context,
              icon: Icons.bolt_rounded,
              title: 'TCP Ping (快速测试)',
              subtitle: '测试服务器连接性，速度快，不消耗流量',
              color: Colors.amber,
              onTap: () {
                Navigator.pop(context);
                _testAllLatencies(nodes, useTcpPing: true);
              },
            ),
            const SizedBox(height: 16),
            _buildTestOption(
              context: context,
              icon: Icons.language_rounded,
              title: '真实连接 (延迟测试)',
              subtitle: '模拟真实网页访问，结果准确，会消耗少量流量',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                _testAllLatencies(nodes, useTcpPing: false);
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTestOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(16),
          color: color.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ],
        ),
      ),
    );
  }

  void _handleAddAction(String action) {
    switch (action) {
      case 'scan_qr':
        _scanQRCode();
        break;
      case 'import_link':
        _importFromClipboard();
        break;
      case 'manual_vmess':
        _showEditDialog(null, 'vmess');
        break;
      case 'manual_vless':
        _showEditDialog(null, 'vless');
        break;
      case 'manual_trojan':
        _showEditDialog(null, 'trojan');
        break;
      case 'manual_ss':
        _showEditDialog(null, 'shadowsocks');
        break;
      case 'manual_socks':
        _showEditDialog(null, 'socks');
        break;
      case 'manual_hysteria2':
        _showEditDialog(null, 'hysteria2');
        break;
      case 'manual_tuic':
        _showEditDialog(null, 'tuic');
        break;
      case 'manual_wireguard':
        _showEditDialog(null, 'wireguard');
        break;
      case 'import_file':
        _importFromFile();
        break;
      case 'deduplicate':
        _deduplicate();
        break;
      case 'sort_latency':
        ref.read(nodeProvider.notifier).sortByLatency();
        break;
      case 'sort_name':
        ref.read(nodeProvider.notifier).sortByName();
        break;
    }
  }

  void _showEditDialog(NodeModel? node, String protocol) {
    showDialog(
      context: context,
      builder: (context) => NodeEditDialog(node: node, initialProtocol: protocol),
    );
  }

  void _deduplicate() {
    ref.read(nodeProvider.notifier).deduplicate();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已自动清理重复节点'), behavior: SnackBarBehavior.floating),
    );
  }

  void _scanQRCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('扫描二维码')),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                Navigator.pop(context, barcode.rawValue);
              }
            },
          ),
        ),
      ),
    );

    if (result != null && result is String) {
      _importNode(result);
    }
  }

  void _importFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      // 1. Check if it's a URL (Subscription link)
      final bool isUrl = text.startsWith(RegExp(r'https?://', caseSensitive: false));
      
      if (isUrl) {
        // If it's a URL, directly add to subscriptions
        final subs = ref.read(subscriptionProvider);
        if (subs.any((s) => s.url == text)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('该订阅链接已存在')),
            );
          }
          return;
        }

        final newSub = SubscriptionModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '新订阅 ${DateTime.now().month}/${DateTime.now().day}',
          url: text,
        );

        ref.read(subscriptionProvider.notifier).addSubscription(newSub);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('检测到订阅链接，已自动添加到“订阅管理”'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // 2. Otherwise, try to parse as nodes
      final nodes = LinkParser.parse(text);
      if (nodes.isNotEmpty) {
        ref.read(nodeProvider.notifier).addNodes(nodes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功从剪贴板导入 ${nodes.length} 个节点')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('剪贴板中未发现有效节点或订阅内容')),
          );
        }
      }
    }
  }

  void _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final nodes = LinkParser.parse(content);
        
        if (nodes.isNotEmpty) {
          ref.read(nodeProvider.notifier).addNodes(nodes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('成功从文件导入 ${nodes.length} 个节点')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件中未发现有效节点')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件导入失败: $e')),
        );
      }
    }
  }

  void _importNode(String text) {
    final nodes = LinkParser.parse(text);
    if (nodes.isNotEmpty) {
      ref.read(nodeProvider.notifier).addNodes(nodes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 ${nodes.length} 个节点'), behavior: SnackBarBehavior.floating),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法解析链接'), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

class _TestingAnimation extends StatefulWidget {
  const _TestingAnimation();

  @override
  State<_TestingAnimation> createState() => _TestingAnimationState();
}

class _TestingAnimationState extends State<_TestingAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse
              Container(
                width: 14 * _controller.value,
                height: 14 * _controller.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.blue.withOpacity(1 - _controller.value),
                    width: 1.5,
                  ),
                ),
              ),
              // Inner dot
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
