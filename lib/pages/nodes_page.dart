import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lightning/core/link_parser.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/log_provider.dart';
import 'package:lightning/core/node_model.dart';
import 'package:lightning/core/node_provider.dart';
import 'package:lightning/core/config_generator.dart';
import 'package:lightning/core/vpn_provider.dart';
import 'package:lightning/core/subscription_provider.dart';
import 'package:lightning/core/subscription_model.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lightning/pages/node_edit_dialog.dart';
import 'package:intl/intl.dart';

import 'package:lightning/core/app_visibility_provider.dart';

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

class NodesPageState {
  final Set<String> selectedIds;
  final bool isSelectionMode;
  final bool isSearching;
  final String searchQuery;
  final Set<String> expandedGroupIds;

  NodesPageState({
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.isSearching = false,
    this.searchQuery = '',
    this.expandedGroupIds = const {'manual'},
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
    final isVisible = ref.watch(appVisibilityProvider);
    final uiState = ref.watch(nodesPageUIProvider);
    final selectedNode = ref.watch(selectedNodeProvider);
    final theme = Theme.of(context);
    final s = S.of(context, ref);
    final allNodes = ref.watch(nodeProvider);
    final subscriptions = ref.watch(subscriptionProvider);

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

    final Map<String?, List<NodeModel>> groupedNodes = {};
    for (var node in filteredNodes) {
      groupedNodes.putIfAbsent(node.subscriptionId, () => []).add(node);
    }

    final List<MapEntry<String?, List<NodeModel>>> visibleGroups = [];

    for (var sub in subscriptions) {
      if (groupedNodes.containsKey(sub.id)) {
        visibleGroups.add(MapEntry(sub.id, groupedNodes[sub.id]!));
      }
    }

    if (groupedNodes.containsKey(null)) {
      visibleGroups.add(MapEntry(null, groupedNodes[null]!));
    }

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
        title = s.get('manual_import');
        subtitle = s.get('nodes_count', args: {'count': groupNodes.length});
        icon = Icons.input_rounded;
      } else {
        final sub = subscriptions.firstWhere((s) => s.id == subId);
        title = sub.name;
        subtitle = sub.url;
        icon = Icons.rss_feed_rounded;
      }

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

      if (isExpanded) {
        for (final node in groupNodes) {
          flatDisplayList.add(NodeCardItem(node: node, groupNodes: groupNodes));
        }
      }
    }

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
                          hintText: s.get('search_nodes'),
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
                          ? s.get('selected_count',
                              args: {'count': uiState.selectedIds.length})
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
                      final isTesting = ref.watch(nodeTestingProvider);
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
                          tooltip: s.get('stop_speed_test'),
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
                        if (!Platform.isWindows) HapticFeedback.lightImpact();
                        _handleAddAction(value, s);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'import_link',
                          child: _PopupItem(
                            Icons.content_paste_rounded,
                            s.get('import_clipboard'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'import_file',
                          child: _PopupItem(
                            Icons.file_open_rounded,
                            s.get('import_from_file'),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'sort_latency',
                          child: _PopupItem(
                            Icons.sort_rounded,
                            s.get('sort_latency'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'sort_name',
                          child: _PopupItem(
                            Icons.sort_by_alpha_rounded,
                            s.get('sort_name'),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'manual_vmess',
                          child: _PopupItem(
                            Icons.add_rounded,
                            s.get('manual_add_vmess'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'manual_vless',
                          child: _PopupItem(
                            Icons.add_rounded,
                            s.get('manual_add_vless'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'manual_trojan',
                          child: _PopupItem(
                            Icons.add_rounded,
                            s.get('manual_add_trojan'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'manual_ss',
                          child: _PopupItem(
                            Icons.add_rounded,
                            s.get('manual_add_ss'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'manual_socks',
                          child: _PopupItem(
                            Icons.add_rounded,
                            s.get('manual_add_socks'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'manual_hysteria2',
                          child: _PopupItem(
                            Icons.add_rounded,
                            s.get('manual_add_hysteria2'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'manual_tuic',
                          child: _PopupItem(
                            Icons.add_rounded,
                            s.get('manual_add_tuic'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'manual_wireguard',
                          child: _PopupItem(
                            Icons.add_rounded,
                            s.get('manual_add_wireguard'),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'deduplicate',
                          child: _PopupItem(
                            Icons.cleaning_services_rounded,
                            s.get('auto_deduplicate'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.share_rounded, size: 20),
                    onPressed: () {
                      if (!Platform.isWindows) HapticFeedback.mediumImpact();
                      _batchExport(uiState.selectedIds, s);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () {
                      if (!Platform.isWindows) HapticFeedback.mediumImpact();
                      _batchDelete(uiState.selectedIds);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.select_all_rounded, size: 20),
                    onPressed: () {
                      if (!Platform.isWindows) HapticFeedback.lightImpact();
                      ref
                          .read(nodesPageUIProvider.notifier)
                          .selectAll(allNodes.map((n) => n.id).toList());
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      if (!Platform.isWindows) HapticFeedback.lightImpact();
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
                ? _buildEmptyState(context, s)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (Platform.isWindows && constraints.maxWidth > 800) {
                        return GridView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 4.5,
                          ),
                          itemCount: flatDisplayList.length,
                          itemBuilder: (context, index) {
                            final item = flatDisplayList[index];
                            return _buildAdaptiveItem(
                              context,
                              item,
                              theme,
                              uiState,
                              selectedNode,
                              s,
                              isVisible,
                            );
                          },
                        );
                      }

                      return Column(
                        children: [
                          _buildSpeedTestProgressBar(context, ref, theme, s),
                          Expanded(
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 100),
                              cacheExtent: 400,
                              itemCount: flatDisplayList.length,
                              itemBuilder: (context, index) {
                                final item = flatDisplayList[index];
                                return _buildAdaptiveItem(
                                  context,
                                  item,
                                  theme,
                                  uiState,
                                  selectedNode,
                                  s,
                                  isVisible,
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdaptiveItem(
    BuildContext context,
    dynamic item,
    ThemeData theme,
    NodesPageState uiState,
    NodeModel? selectedNode,
    S s,
    bool isVisible,
  ) {
    if (item is GroupHeaderItem) {
      return _buildGroupHeader(context, theme, item, s, isVisible);
    } else if (item is NodeCardItem) {
      final isSelected = selectedNode?.id == item.node.id;
      final isMultiSelected = uiState.selectedIds.contains(item.node.id);

      return _buildNodeItem(
        context,
        item.node,
        isSelected,
        isMultiSelected,
        uiState,
        theme,
        item.groupNodes,
        s,
        isVisible,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSpeedTestProgressBar(
      BuildContext context, WidgetRef ref, ThemeData theme, S s) {
    final progress = ref.watch(speedTestProgressProvider);
    if (progress == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                s.get('speed_test_progress'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                '${progress.completed} / ${progress.total} (${(progress.percentage * 100).toStringAsFixed(0)}%)',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.percentage,
              minHeight: 6,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              valueColor:
                  AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
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
    S s,
    bool isVisible,
  ) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, top: 4),
        height: 64,
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.05)
                : theme.dividerTheme.color ??
                    Colors.black.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.none,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            hoverColor: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
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
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
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
                      mainAxisAlignment: MainAxisAlignment.center,
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
                                ?.withValues(alpha: 0.5),
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
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
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
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      size: 20,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      _showLatencyTestOptions(item.groupNodes, s);
                    },
                    tooltip: s.get('test_group_latency'),
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
      enabled: !isProcessing,
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tooltip: s.get('nodes_cleanup'),
      onSelected: (value) async {
        HapticFeedback.mediumImpact();
        int count = 0;
        String message = "";

        if (value == 'clear_timeout') {
          count = await ref.read(nodeProvider.notifier).clearTimeoutNodes();
          if (!mounted) return;
          message =
              s.get('clear_timeout_success', args: {'count': count.toString()});
        } else if (value == 'deduplicate') {
          count =
              await ref.read(nodeProvider.notifier).manualDeduplicateNodes();
          if (!mounted) return;
          message =
              s.get('deduplicate_success', args: {'count': count.toString()});
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
        PopupMenuItem(
          value: 'clear_timeout',
          child: _PopupItem(Icons.timer_off_outlined, s.get('clear_timeout')),
        ),
        PopupMenuItem(
          value: 'deduplicate',
          child: _PopupItem(
              Icons.auto_fix_high_rounded, s.get('strong_deduplicate')),
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
    S s,
    bool isVisible,
  ) {
    return RepaintBoundary(
      child: MouseRegion(
        cursor:
            Platform.isWindows ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : (theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.02)
                    : Colors.white.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : (theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : theme.dividerTheme.color ??
                          Colors.black.withValues(alpha: 0.12)),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              hoverColor: theme.brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              onSecondaryTapDown: (details) {
                _showNodeContextMenu(node, details.globalPosition, s: s);
              },
              onTap: () {
                if (uiState.isSelectionMode) {
                  ref
                      .read(nodesPageUIProvider.notifier)
                      .toggleSelection(node.id);
                } else {
                  ref.read(selectedNodeProvider.notifier).setNode(node);
                  if (ref.read(vpnProvider).isRunning) {
                    ref.read(vpnProvider.notifier).toggleVpn(node);
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    uiState.isSelectionMode
                        ? _buildSelectionIndicator(isMultiSelected, theme)
                        : _buildProtocolIcon(node),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _buildNodeTag(
                                  node.protocol.toUpperCase(),
                                  theme.colorScheme.primary.withOpacity(0.1),
                                  theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  node.address,
                                  style: TextStyle(
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withOpacity(0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildTrailing(node, groupNodes, s, isVisible),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodeTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildProtocolIcon(NodeModel node) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.lan_rounded,
        size: 20,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildSelectionIndicator(bool isSelected, ThemeData theme) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isSelected ? Icons.check_rounded : Icons.add_rounded,
        color: isSelected ? Colors.white : theme.colorScheme.primary,
        size: 20,
      ),
    );
  }

  Widget _buildTrailing(
      NodeModel node, List<NodeModel> groupNodes, S s, bool isVisible) {
    final theme = Theme.of(context);
    final isTesting = ref.watch(nodeTestingProvider);
    final isTestingThis = node.latency == -3;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isTestingThis)
          _TestingAnimation(isVisible: isVisible)
        else if (node.latency != null)
          _buildLatencyTag(node.latency!, theme, s)
        else
          Icon(
            Icons.signal_cellular_alt_rounded,
            size: 16,
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.2),
          ),
        if (Platform.isWindows) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.more_vert_rounded,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.4),
              size: 20,
            ),
            onPressed: () => _showNodeOptions(node, s),
            tooltip: s.get('more_actions'),
          ),
        ],
      ],
    );
  }

  Widget _buildLatencyTag(int latency, ThemeData theme, S s) {
    Color color = Colors.greenAccent;
    if (latency > 500) color = Colors.orangeAccent;
    if (latency < 0) color = Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        latency > 0 ? '${latency}ms' : s.get('latency_timeout'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, NodesPageState uiState,
      List<NodeModel> filteredNodes, S s) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            uiState.isSelectionMode
                ? s.get('selected_count',
                    args: {'count': uiState.selectedIds.length})
                : s.get('nodes_manage'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const Spacer(),
          if (!uiState.isSelectionMode) ...[
            IconButton(
              tooltip: s.get('search_nodes'),
              icon: const Icon(Icons.search_rounded, size: 22),
              onPressed: () =>
                  ref.read(nodesPageUIProvider.notifier).setSearching(true),
            ),
            IconButton(
              tooltip: s.get('test_all_speed'),
              icon: const Icon(Icons.speed_rounded, size: 22),
              onPressed: () => _showLatencyTestOptions(filteredNodes, s),
            ),
            IconButton(
              tooltip: s.get('auto_select_best'),
              icon: const Icon(Icons.auto_awesome_rounded,
                  size: 20, color: Colors.orangeAccent),
              onPressed: () => _handleAutoSelect(s),
            ),
            if (Platform.isWindows)
              IconButton(
                tooltip: s.get('import_nodes'),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                onPressed: () {
                  _showImportOptions(context, s);
                },
              ),
          ],
        ],
      ),
    );
  }

  void _showImportOptions(BuildContext context, S s) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(s.get('import_nodes'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.content_paste_rounded, color: Colors.blue),
              title: Text(s.get('import_from_clipboard')),
              subtitle: Text(s.get('import_from_clipboard_desc')),
              onTap: () {
                Navigator.pop(context);
                _importFromClipboard(s);
              },
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            ListTile(
              leading:
                  const Icon(Icons.file_open_rounded, color: Colors.orange),
              title: Text(s.get('import_from_file')),
              subtitle: Text(s.get('import_from_file_desc')),
              onTap: () {
                Navigator.pop(context);
                _importFromFile(s);
              },
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add_rounded, color: Colors.green),
              title: Text(s.get('manual_add_vmess')),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(null, 'vmess');
              },
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAutoSelect(S s) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(s.get('auto_selecting')),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
      ),
    );

    try {
      await ref.read(nodeProvider.notifier).autoSelectBestNode();
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.get('auto_select_done')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.get('auto_select_failed')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildEmptyState(BuildContext context, S s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lan_rounded, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 20),
          Text(
            s.get('no_nodes_found'),
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.get('import_nodes_hint'),
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showNodeContextMenu(NodeModel node, Offset offset,
      {bool fromLongPress = false, required S s}) async {
    final RelativeRect position = fromLongPress
        ? RelativeRect.fromLTRB(
            MediaQuery.of(context).size.width / 2 - 50,
            MediaQuery.of(context).size.height / 2 - 50,
            MediaQuery.of(context).size.width / 2 + 50,
            MediaQuery.of(context).size.height / 2 + 50,
          )
        : RelativeRect.fromLTRB(
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
            value: 'edit',
            child: _PopupItem(Icons.edit_outlined, s.get('edit_node_label'))),
        PopupMenuItem(
            value: 'ping',
            child: _PopupItem(Icons.speed_rounded, s.get('test_latency'))),
        PopupMenuItem(
            value: 'copy',
            child: _PopupItem(Icons.copy_rounded, s.get('copy_link_label'))),
        PopupMenuItem(
            value: 'share',
            child: _PopupItem(Icons.qr_code_2_rounded, s.get('share_qr'))),
        PopupMenuItem(
            value: 'export',
            child:
                _PopupItem(Icons.output_rounded, s.get('export_config_label'))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: _PopupItem(
              Icons.delete_outline_rounded, s.get('physical_destroy'),
              color: Colors.redAccent),
        ),
      ],
    );

    if (selected == null) return;

    switch (selected) {
      case 'edit':
        _showEditDialog(node, node.protocol);
        break;
      case 'ping':
        ref.read(nodeProvider.notifier).testLatency(node.id);
        break;
      case 'copy':
        final link = _generateLink(node);
        Clipboard.setData(ClipboardData(text: link));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(s.get('link_copied_success')),
              behavior: SnackBarBehavior.floating),
        );
        break;
      case 'share':
        _showShareDialog(node);
        break;
      case 'export':
        final jsonConfig = ConfigGenerator.exportNodeConfig(node);
        Clipboard.setData(ClipboardData(text: jsonConfig));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(s.get('config_backed_up')),
              behavior: SnackBarBehavior.floating),
        );
        break;
      case 'delete':
        _showDeleteConfirm(node, s);
        break;
    }
  }

  void _showDeleteConfirm(NodeModel node, S s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('confirm_delete')),
        content: Text(s.get('delete_node_confirm', args: {'name': node.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('cancel')),
          ),
          TextButton(
            onPressed: () {
              ref.read(nodeProvider.notifier).removeNode(node.id);
              Navigator.pop(context);
            },
            child: Text(s.get('delete_node_label'),
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showNodeOptions(NodeModel node, S s) {
    if (Platform.isWindows) {
      _showNodeContextMenu(node, Offset.zero, fromLongPress: true, s: s);
      return;
    }
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
                color: theme.dividerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                Icons.edit_outlined,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              title: Text(
                s.get('edit_node_label'),
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
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              title: Text(
                s.get('copy_link_label'),
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
                  SnackBar(
                    content: Text(s.get('link_copied_success')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.qr_code_2_rounded,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              title: Text(
                s.get('share_qr'),
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
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              title: Text(
                s.get('export_config_label'),
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
                  SnackBar(
                    content: Text(s.get('config_backed_up')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.select_all_outlined,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              title: Text(
                s.get('multi_select'),
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
                s.get('delete_node_label'),
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

  void _batchExport(Set<String> selectedIds, S s) {
    final nodes = ref.read(nodeProvider);
    final selectedNodes =
        nodes.where((n) => selectedIds.contains(n.id)).toList();
    if (selectedNodes.isEmpty) return;

    final List<String> links = [];
    for (var node in selectedNodes) {
      links.add(_generateLink(node));
    }

    final String exportText = links.join('\n');
    Clipboard.setData(ClipboardData(text: exportText));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.get('batch_export_success',
            args: {'count': selectedNodes.length.toString()})),
        behavior: SnackBarBehavior.floating,
      ),
    );

    ref.read(nodesPageUIProvider.notifier).clearSelection();
  }

  void _showShareDialog(NodeModel node) {
    final link = _generateLink(node);
    final s = S.of(context, ref);
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
            Text(
              s.get('scan_qr_import'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
      final Map<String, dynamic> data = node.rawData != null
          ? Map<String, dynamic>.from(node.rawData!)
          : {"v": "2", "aid": "0"};

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

      return exportedLink;
    }

    final query = node.rawData != null
        ? Map<String, String>.from(
            node.rawData!.map((k, v) => MapEntry(k, v.toString())),
          )
        : <String, String>{};

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
    if (ref.read(nodeTestingProvider)) return;

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
      if (!mounted || confirm != true) return;
    }

    final modeText = useTcpPing ? 'TCP Ping' : '真实链路';
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

    await ref.read(nodeProvider.notifier).testAllLatencies(
          useTcpPing: useTcpPing,
          ids: nodes.map((n) => n.id).toList(),
        );

    if (!mounted) return;

    ref.read(logProvider.notifier).addLog('info', '该组测延迟任务已完成');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('测延迟任务已开始')),
      );
    }
  }

  void _showLatencyTestOptions(List<NodeModel> nodes, S s) {
    if (Platform.isWindows) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(s.get('batch_node_latency'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.bolt_rounded, color: Colors.amber),
                title: Text(s.get('tcp_ping_fast')),
                subtitle: Text(s.get('test_conn_speed')),
                onTap: () {
                  Navigator.pop(context);
                  _testAllLatencies(nodes, useTcpPing: true);
                },
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              ListTile(
                leading: const Icon(Icons.language_rounded, color: Colors.blue),
                title: Text(s.get('real_conn_latency')),
                subtitle: Text(s.get('simulate_web_access')),
                onTap: () {
                  Navigator.pop(context);
                  _testAllLatencies(nodes, useTcpPing: false);
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
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.speed_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  s.get('batch_node_latency'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildTestOption(
              context: context,
              icon: Icons.bolt_rounded,
              title: s.get('tcp_ping_fast'),
              subtitle: s.get('test_conn_speed_desc'),
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
              title: s.get('real_conn_latency'),
              subtitle: s.get('simulate_web_access_desc'),
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

  void _handleAddAction(String action, S s) {
    switch (action) {
      case 'import_link':
        _importFromClipboard(s);
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
        _importFromFile(s);
        break;
      case 'sort_latency':
        ref.read(nodeProvider.notifier).sortByLatency();
        break;
      case 'sort_name':
        ref.read(nodeProvider.notifier).sortByName();
        break;
      case 'deduplicate':
        ref.read(nodeProvider.notifier).manualDeduplicateNodes();
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

  void _importFromClipboard(S s) async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;

    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      final bool isUrl = text.startsWith(
        RegExp(r'https?://', caseSensitive: false),
      );

      if (isUrl) {
        final subs = ref.read(subscriptionProvider);
        if (subs.any((s) => s.url == text)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.get('sub_already_exists'))));
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
            SnackBar(
              content: Text(s.get('sub_auto_added')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final nodes = LinkParser.parse(text);
      if (nodes.isNotEmpty) {
        ref.read(nodeProvider.notifier).addNodes(nodes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(s.get('import_from_clipboard_success',
                    args: {'count': nodes.length.toString()}))),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.get('no_valid_nodes_found'))));
        }
      }
    }
  }

  void _importFromFile(S s) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (!mounted) return;

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        if (!mounted) return;

        final nodes = LinkParser.parse(content);

        if (nodes.isNotEmpty) {
          ref.read(nodeProvider.notifier).addNodes(nodes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(s.get('import_from_file_success',
                      args: {'count': nodes.length.toString()}))),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.get('no_valid_nodes_found'))));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${s.get('import_failed')}: $e')));
      }
    }
  }
}

class _TestingAnimation extends StatelessWidget {
  final bool isVisible;
  const _TestingAnimation({this.isVisible = true});

  @override
  Widget build(BuildContext context) {
    // 🚀 【性能优化】移除复杂的波纹动画，改为简单的静态指示器
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.blue.withOpacity(0.3),
                width: 1.5,
              ),
            ),
          ),
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
  }
}
