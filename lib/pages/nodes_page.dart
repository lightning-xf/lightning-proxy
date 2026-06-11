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
import 'package:lightning/core/config_generator.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/subscription_provider.dart';
import 'package:lightning/core/subscription_model.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lightning/pages/node_edit_dialog.dart';

// --- Flattening Model Start ---
abstract class DisplayItem {}

class GroupHeaderItem extends DisplayItem {
  final String? subId;
  final String title;
  final String subtitle;
  final IconData icon;
  final int count;
  final bool isExpanded;
  final List<NodeModel> groupNodes;

  GroupHeaderItem({
    required this.subId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.count,
    required this.isExpanded,
    required this.groupNodes,
  });
}

class NodeCardItem extends DisplayItem {
  final NodeModel node;
  final List<NodeModel> groupNodes;

  NodeCardItem({required this.node, required this.groupNodes});
}
// --- Flattening Model End ---

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
  final Set<String> expandedGroupIds; // 记录展开的分组 ID

  NodesPageState({
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.isSearching = false,
    this.searchQuery = '',
    this.expandedGroupIds = const {'manual'}, // 默认展开手动导入
  });

  NodesPageState copyWith({
    Set<String>? selectedIds,
    bool? isSelectionMode,
    bool? isSearching,
    String? searchQuery,
    Set<String>? expandedGroupIds,
  }) {
    return NodesPageState(
      selectedIds: selectedIds ?? this.selectedIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      isSearching: isSearching ?? this.isSearching,
      searchQuery: searchQuery ?? this.searchQuery,
      expandedGroupIds: expandedGroupIds ?? this.expandedGroupIds,
    );
  }
}

class NodesPageNotifier extends StateNotifier<NodesPageState> {
  NodesPageNotifier() : super(NodesPageState());

  void toggleGroupExpansion(String groupId) {
    final newExpanded = Set<String>.from(state.expandedGroupIds);
    if (newExpanded.contains(groupId)) {
      newExpanded.remove(groupId);
    } else {
      newExpanded.add(groupId);
    }
    state = state.copyWith(expandedGroupIds: newExpanded);
  }

  void setSearching(bool searching) => state = state.copyWith(
    isSearching: searching,
    searchQuery: searching ? state.searchQuery : '',
  );
  void setSearchQuery(String query) =>
      state = state.copyWith(searchQuery: query);
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
    state = state.copyWith(
      selectedIds: newIds,
      isSelectionMode: newIds.isNotEmpty,
    );
  }

  void selectAll(List<String> ids) =>
      state = state.copyWith(selectedIds: Set.from(ids), isSelectionMode: true);
  void clearSelection() =>
      state = state.copyWith(selectedIds: {}, isSelectionMode: false);
}

final nodesPageUIProvider =
    StateNotifierProvider<NodesPageNotifier, NodesPageState>(
      (ref) => NodesPageNotifier(),
    );

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
                    n.name.toLowerCase().contains(
                      uiState.searchQuery.toLowerCase(),
                    ) ||
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

    // --- Build Flat List Start ---
    final List<DisplayItem> flatDisplayList = [];
    for (final entry in visibleGroups) {
      final subId = entry.key;
      final groupNodes = entry.value;
      final groupId = subId ?? 'manual';
      final isExpanded = uiState.expandedGroupIds.contains(groupId);

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

      // Add Header
      flatDisplayList.add(
        GroupHeaderItem(
          subId: subId,
          title: title,
          subtitle: subtitle,
          icon: icon,
          count: groupNodes.length,
          isExpanded: isExpanded,
          groupNodes: groupNodes,
        ),
      );

      // Add Nodes if expanded
      if (isExpanded) {
        for (final node in groupNodes) {
          flatDisplayList.add(NodeCardItem(node: node, groupNodes: groupNodes));
        }
      }
    }
    // --- Build Flat List End ---

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
              titleSpacing: 0,
              title: uiState.isSearching
                  ? Container(
                      height: 40,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withOpacity(
                          0.3,
                        ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                        ),
                        onChanged: (v) => ref
                            .read(nodesPageUIProvider.notifier)
                            .setSearchQuery(v),
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
                        ref
                            .read(nodesPageUIProvider.notifier)
                            .setSearching(false);
                        _searchController.clear();
                      },
                    )
                  else
                    IconButton(
                      icon: uiState.isSearching
                          ? const Icon(Icons.close_rounded)
                          : const Icon(Icons.search_rounded, size: 22),
                      onPressed: () {
                        if (uiState.isSearching) {
                          ref
                              .read(nodesPageUIProvider.notifier)
                              .setSearching(false);
                        } else {
                          ref
                              .read(nodesPageUIProvider.notifier)
                              .setSearching(true);
                        }
                      },
                    ),
                  Consumer(
                    builder: (context, ref, child) {
                      final isTesting = ref
                          .watch(nodeProvider.notifier)
                          .isTesting;
                      if (isTesting) {
                        return IconButton(
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                          onPressed: () {
                            HapticFeedback.heavyImpact();
                            ref.read(nodeProvider.notifier).stopTesting();
                          },
                          tooltip: '停止测速',
                        );
                      }
                      return _buildCleanEnginePopup(context, ref, s);
                    },
                  ),
                  if (!uiState.isSearching) ...[
                    PopupMenuButton<String>(
                      offset: const Offset(0, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 22,
                      ),
                      onSelected: (value) {
                        HapticFeedback.lightImpact();
                        _handleAddAction(value);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'import_link',
                          child: _PopupItem(
                            Icons.content_paste_rounded,
                            '导入剪贴板链接',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'import_file',
                          child: _PopupItem(Icons.file_open_rounded, '从文件导入'),
                        ),
                        const PopupMenuItem(
                          value: 'scan_qr',
                          child: _PopupItem(
                            Icons.qr_code_scanner_rounded,
                            '扫描二维码',
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'sort_latency',
                          child: _PopupItem(Icons.sort_rounded, '按延迟排序'),
                        ),
                        const PopupMenuItem(
                          value: 'sort_name',
                          child: _PopupItem(
                            Icons.sort_by_alpha_rounded,
                            '按名称排序',
                          ),
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
                          child: _PopupItem(
                            Icons.add_rounded,
                            '手动添加 Shadowsocks',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'manual_socks',
                          child: _PopupItem(Icons.add_rounded, '手动添加 SOCKS'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_hysteria2',
                          child: _PopupItem(
                            Icons.add_rounded,
                            '手动添加 Hysteria2',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'manual_tuic',
                          child: _PopupItem(Icons.add_rounded, '手动添加 TUIC'),
                        ),
                        const PopupMenuItem(
                          value: 'manual_wireguard',
                          child: _PopupItem(
                            Icons.add_rounded,
                            '手动添加 WireGuard',
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'deduplicate',
                          child: _PopupItem(
                            Icons.cleaning_services_rounded,
                            '自动去重',
                          ),
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
                      ref
                          .read(nodesPageUIProvider.notifier)
                          .selectAll(allNodes.map((n) => n.id).toList());
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
                    cacheExtent: 400, // 铁证：视窗下方 400 像素缓冲区，预载即将滑入的卡片
                    itemExtent: null, // 我们有不同高度的 Item，所以不能用 itemExtent
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries:
                        false, // 我们已经在子项里手动挂载了 RepaintBoundary
                    itemCount: flatDisplayList.length,
                    itemBuilder: (context, index) {
                      final item = flatDisplayList[index];

                      if (item is GroupHeaderItem) {
                        return _buildGroupHeader(context, theme, item);
                      } else if (item is NodeCardItem) {
                        final isSelected = selectedNode?.id == item.node.id;
                        final isMultiSelected = uiState.selectedIds.contains(
                          item.node.id,
                        );

                        return _buildNodeItem(
                          context,
                          item.node,
                          isSelected,
                          isMultiSelected,
                          uiState,
                          theme,
                          item.groupNodes,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(
    BuildContext context,
    ThemeData theme,
    GroupHeaderItem item,
  ) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, top: 4),
        height: 64, // 铁证：分组头部也注入固定高度，彻底消除布局抖动
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.none, // 铁证：物理清洗 ClipRRect
          child: InkWell(
            borderRadius: BorderRadius.circular(24), // [Fix] 铁证：显式同步圆角，防止水波纹溢出
            onTap: () {
              HapticFeedback.lightImpact();
              ref
                  .read(nodesPageUIProvider.notifier)
                  .toggleGroupExpansion(item.subId ?? 'manual');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.icon,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center, // 铁证：垂直居中
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${item.count}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.speed_rounded,
                      color: theme.colorScheme.primary.withOpacity(0.7),
                      size: 20,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      _showLatencyTestOptions(item.groupNodes);
                    },
                    tooltip: '测试该组延迟',
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    item.isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.grey.shade500,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCleanEnginePopup(BuildContext context, WidgetRef ref, S s) {
    final bool isProcessing = ref.watch(nodeProvider.notifier).isProcessing;

    return PopupMenuButton<String>(
      icon: isProcessing
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cleaning_services_rounded, size: 22),
      enabled: !isProcessing, // 铁证：正在处理时置灰菜单，彻底杜绝连击
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tooltip: '节点大扫除',
      onSelected: (value) async {
        HapticFeedback.mediumImpact();
        int count = 0;
        String message = "";

        if (value == 'clear_timeout') {
          count = await ref.read(nodeProvider.notifier).clearTimeoutNodes();
          // [Fix] 异步守卫：await 结束后立刻检查 mounted，防止 ref 崩溃
          if (!mounted) return;
          message = "已物理清除 $count 个失效节点";
        } else if (value == 'deduplicate') {
          count = await ref
              .read(nodeProvider.notifier)
              .manualDeduplicateNodes();
          // [Fix] 异步守卫：await 结束后立刻检查 mounted，防止 ref 崩溃
          if (!mounted) return;
          message = "已成功合并 $count 个重复节点";
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'clear_timeout',
          child: _PopupItem(Icons.timer_off_outlined, '清除超时节点'),
        ),
        const PopupMenuItem(
          value: 'deduplicate',
          child: _PopupItem(Icons.auto_fix_high_rounded, '节点强力去重'),
        ),
      ],
    );
  }

  Widget _buildNodeItem(
    BuildContext context,
    NodeModel node,
    bool isSelected,
    bool isMultiSelected,
    NodesPageState uiState,
    ThemeData theme,
    List<NodeModel> groupNodes,
  ) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
        height: 72, // 铁证：固定高度计算优化，提升 ListView 布局效率
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.08)
              : theme.colorScheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(18),
          // 铁证：物理移除扩散型 BoxShadow，改用低成本 Border 实现扁平化视觉
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
          clipBehavior: Clip.none, // 铁证：物理清洗 ClipRRect，减轻 GPU 像素合并负担
          child: InkWell(
            borderRadius: BorderRadius.circular(18), // [Fix] 铁证：显式同步圆角，防止水波纹溢出
            onTap: () {
              if (uiState.isSelectionMode) {
                ref.read(nodesPageUIProvider.notifier).toggleSelection(node.id);
              } else {
                ref.read(selectedNodeProvider.notifier).setNode(node);
                if (ref.read(vpnProvider).isRunning) {
                  ref.read(vpnProvider.notifier).toggleVpn(node: node);
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
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  uiState.isSelectionMode
                      ? _buildSelectionIndicator(isMultiSelected, theme)
                      : _buildProtocolIcon(node),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center, // 铁证：垂直居中
                      children: [
                        Text(
                          node.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.w700,
                            fontSize: 14,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.textTheme.titleMedium?.color,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1, // [Fix] 铁证：垂直溢出熔断
                          overflow: TextOverflow.ellipsis,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(
                                    0.05,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  node.protocol.toUpperCase(),
                                  style: TextStyle(
                                    color: theme.colorScheme.primary
                                        .withOpacity(0.7),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  maxLines: 1, // [Fix] 铁证：物理封锁
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  node.address,
                                  style: TextStyle(
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withOpacity(0.7),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1, // [Fix] 铁证：横向/垂直双熔断
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8), // 铁证：常驻间距使用 const
                  _buildTrailing(node, groupNodes),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    NodesPageState uiState,
    List<NodeModel> nodes,
    S s,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (!uiState.isSearching) ...[
            Text(
              uiState.isSelectionMode
                  ? '已选择 ${uiState.selectedIds.length}'
                  : s.get('nodes_manage'),
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
                  onChanged: (v) =>
                      ref.read(nodesPageUIProvider.notifier).setSearchQuery(v),
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
                onPressed: () =>
                    ref.read(nodesPageUIProvider.notifier).setSearching(true),
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
                ref
                    .read(nodesPageUIProvider.notifier)
                    .selectAll(nodes.map((n) => n.id).toList());
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

  Widget _buildTrailing(NodeModel node, List<NodeModel> groupNodes) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (node.latency != null)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _testAllLatencies(groupNodes, useTcpPing: false);
            },
            onLongPress: () {
              HapticFeedback.selectionClick();
              _testAllLatencies(groupNodes, useTcpPing: true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已针对该组触发快速 TCP 测延迟'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _getLatencyColor(node.latency!).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: node.latency == -3
                  ? const _TestingAnimation()
                  : Text(
                      (node.latency == -2 || node.latency == -1)
                          ? '超时'
                          : '${node.latency}ms',
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
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
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
    if (latency == -3) return Colors.blue;
    if (latency == -2 || latency == -1) return Colors.red;
    if (latency < 200) return const Color(0xFF4ADE80);
    if (latency < 500) return Colors.orange;
    return Colors.red;
  }

  Color _getProtocolColor(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'vmess':
        return Colors.blueAccent;
      case 'vless':
        return Colors.orangeAccent;
      case 'trojan':
        return Colors.purpleAccent;
      case 'shadowsocks':
      case 'ss':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  void _showNodeOptions(NodeModel node) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                Icons.edit_outlined,
                color: theme.colorScheme.primary.withOpacity(0.8),
              ),
              title: Text(
                '编辑节点',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(node, node.protocol);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.copy_outlined,
                color: theme.colorScheme.primary.withOpacity(0.8),
              ),
              title: Text(
                '复制链接',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
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
              leading: Icon(
                Icons.qr_code_2_rounded,
                color: theme.colorScheme.primary.withOpacity(0.8),
              ),
              title: Text(
                '二维码分享',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showShareDialog(node);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.output_rounded,
                color: theme.colorScheme.primary.withOpacity(0.8),
              ),
              title: Text(
                '导出完整配置',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              onTap: () {
                final jsonConfig = ConfigGenerator.exportNodeConfig(node);
                Clipboard.setData(ClipboardData(text: jsonConfig));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('完整 JSON 配置已导出至剪贴板'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.select_all_outlined,
                color: theme.colorScheme.primary.withOpacity(0.8),
              ),
              title: Text(
                '多选模式',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                ref.read(nodesPageUIProvider.notifier).toggleSelection(node.id);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: Text(
                '删除节点',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.redAccent,
                  letterSpacing: -0.2,
                ),
              ),
              onTap: () {
                ref.read(nodeProvider.notifier).removeNode(node.id);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),
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
          : {"v": "2", "aid": "0"};

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
      final exportedLink =
          "vmess://${base64.encode(utf8.encode(exportedJson))}";

      // Consistency check: If we have rawData, compare key fields
      if (node.rawData != null) {
        final originalJson = jsonEncode(node.rawData);
        if (originalJson != exportedJson) {
          debugPrint(
            "VMess configuration consistency note: Fields might have been updated by user or model.",
          );
        }
      }

      return exportedLink;
    }

    final query = node.rawData != null
        ? Map<String, String>.from(
            node.rawData!.map((k, v) => MapEntry(k, v.toString())),
          )
        : <String, String>{};

    // Overlay current values
    if (node.network != null) query['type'] = node.network!;
    if (node.security != null) query['security'] = node.security!;
    if (node.sni != null && node.sni!.isNotEmpty) query['sni'] = node.sni!;
    if (node.host != null && node.host!.isNotEmpty) query['host'] = node.host!;
    if (node.path != null && node.path!.isNotEmpty) query['path'] = node.path!;
    if (node.type != null && node.type != 'none')
      query['headerType'] = node.type!;
    if (node.publicKey != null && node.publicKey!.isNotEmpty)
      query['pbk'] = node.publicKey!;
    if (node.fingerPrint != null && node.fingerPrint!.isNotEmpty)
      query['fp'] = node.fingerPrint!;
    if (node.flow != null && node.flow!.isNotEmpty) query['flow'] = node.flow!;
    if (node.serviceName != null && node.serviceName!.isNotEmpty)
      query['serviceName'] = node.serviceName!;
    if (node.encryption != null && node.encryption != 'none')
      query['encryption'] = node.encryption!;

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

  void _testAllLatencies(
    List<NodeModel> nodes, {
    bool useTcpPing = false,
  }) async {
    // [Fix] 物理防抖：如果正在测试中，直接拦截连发请求，防止 Worker Pool 溢出
    if (ref.read(nodeProvider.notifier).isTesting) return;

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
      // [Fix] 生命周期守卫：await 之后必须检查 mounted，防止 ref 崩溃
      if (!mounted || confirm != true) return;
    }

    final modeText = useTcpPing ? 'TCP Ping' : '真实链路';
    // [Fix] 再次确认 mounted 状态
    if (!mounted) return;

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

    // Use optimized batch testing for the group
    await ref
        .read(nodeProvider.notifier)
        .testAllLatencies(
          useTcpPing: useTcpPing,
          ids: nodes.map((n) => n.id).toList(),
        );

    // [Fix] 生命周期守卫：核心测速 await 结束后必须检查 mounted，严禁使用失效 ref
    if (!mounted) return;

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
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
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
      builder: (context) =>
          NodeEditDialog(node: node, initialProtocol: protocol),
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

    // [Fix] 异步守卫：页面跳转返回后必须检查 mounted，严禁使用失效 ref
    if (!mounted) return;

    if (result != null && result is String) {
      _importNode(result);
    }
  }

  void _importFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    // [Fix] 异步守卫：读取剪贴板后检查 mounted，严禁使用失效 ref
    if (!mounted) return;

    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      // 1. Check if it's a URL (Subscription link)
      final bool isUrl = text.startsWith(
        RegExp(r'https?://', caseSensitive: false),
      );

      if (isUrl) {
        // If it's a URL, directly add to subscriptions
        final subs = ref.read(subscriptionProvider);
        if (subs.any((s) => s.url == text)) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('该订阅链接已存在')));
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('剪贴板中未发现有效节点或订阅内容')));
        }
      }
    }
  }

  void _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      // [Fix] 异步守卫：文件选择后检查 mounted，严禁使用失效 ref
      if (!mounted) return;

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        // [Fix] 异步守卫：文件读取后检查 mounted，严禁使用失效 ref
        if (!mounted) return;

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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('文件中未发现有效节点')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('文件导入失败: $e')));
      }
    }
  }

  void _importNode(String text) {
    final nodes = LinkParser.parse(text);
    if (nodes.isNotEmpty) {
      ref.read(nodeProvider.notifier).addNodes(nodes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功导入 ${nodes.length} 个节点'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法解析链接'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _TestingAnimation extends StatefulWidget {
  const _TestingAnimation();

  @override
  State<_TestingAnimation> createState() => _TestingAnimationState();
}

class _TestingAnimationState extends State<_TestingAnimation>
    with SingleTickerProviderStateMixin {
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
