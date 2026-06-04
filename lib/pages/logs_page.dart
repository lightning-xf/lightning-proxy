import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/log_provider.dart';
import 'package:intl/intl.dart';

class LogsPageState {
  final bool autoScroll;
  final String filterLevel;

  LogsPageState({this.autoScroll = true, this.filterLevel = 'all'});

  LogsPageState copyWith({bool? autoScroll, String? filterLevel}) {
    return LogsPageState(
      autoScroll: autoScroll ?? this.autoScroll,
      filterLevel: filterLevel ?? this.filterLevel,
    );
  }
}

class LogsPageNotifier extends StateNotifier<LogsPageState> {
  LogsPageNotifier() : super(LogsPageState());

  void toggleAutoScroll() =>
      state = state.copyWith(autoScroll: !state.autoScroll);
  void setFilterLevel(String level) =>
      state = state.copyWith(filterLevel: level);
}

final logsPageUIProvider =
    StateNotifierProvider<LogsPageNotifier, LogsPageState>(
      (ref) => LogsPageNotifier(),
    );

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(logsPageUIProvider);
    final allLogs = ref.watch(logProvider);
    final logs = uiState.filterLevel == 'all'
        ? allLogs
        : allLogs.where((l) => l.level == uiState.filterLevel).toList();
    final theme = Theme.of(context);
    final s = S.of(context, ref);
    final bool isMobile = MediaQuery.of(context).size.width < 720;

    // Auto scroll when logs change
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(uiState.autoScroll),
    );

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
              title: Text(
                s.get('realtime_logs'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.filter_list_rounded,
                    color: uiState.filterLevel == 'all'
                        ? Colors.grey
                        : theme.colorScheme.primary,
                    size: 22,
                  ),
                  onSelected: (v) =>
                      ref.read(logsPageUIProvider.notifier).setFilterLevel(v),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'all', child: Text('全部日志')),
                    const PopupMenuItem(value: 'debug', child: Text('DEBUG')),
                    const PopupMenuItem(value: 'info', child: Text('INFO')),
                    const PopupMenuItem(
                      value: 'warning',
                      child: Text('WARNING'),
                    ),
                    const PopupMenuItem(value: 'error', child: Text('ERROR')),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    uiState.autoScroll
                        ? Icons.unfold_less_rounded
                        : Icons.unfold_more_rounded,
                    size: 22,
                    color: uiState.autoScroll
                        ? theme.colorScheme.primary
                        : Colors.grey,
                  ),
                  onPressed: () {
                    ref.read(logsPageUIProvider.notifier).toggleAutoScroll();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 20),
                  onPressed: () {
                    final text = logs
                        .map(
                          (l) =>
                              '[${l.timestamp}] ${l.level.toUpperCase()}: ${l.message}',
                        )
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('日志已复制到剪贴板'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, size: 22),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ref.read(logProvider.notifier).clearLogs();
                  },
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          if (!isMobile) _buildHeader(context, ref, logs, s, theme, uiState),
          Expanded(
            child: logs.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final color = _getLevelColor(log.level);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[${DateFormat('HH:mm:ss').format(log.timestamp)}] ',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                log.level.toUpperCase(),
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                log.message,
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom(bool autoScroll) {
    if (autoScroll && _scrollController.hasClients) {
      _scrollController.animateTo(
        0, // Since it's a reversed list or we prepend logs, 0 is the top (newest)
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    List<LogEntry> logs,
    S s,
    ThemeData theme,
    LogsPageState uiState,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            s.get('realtime_logs'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.filter_list_rounded,
              color: uiState.filterLevel == 'all'
                  ? Colors.grey
                  : theme.colorScheme.primary,
              size: 22,
            ),
            onSelected: (v) =>
                ref.read(logsPageUIProvider.notifier).setFilterLevel(v),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('全部日志')),
              const PopupMenuItem(value: 'debug', child: Text('DEBUG')),
              const PopupMenuItem(value: 'info', child: Text('INFO')),
              const PopupMenuItem(value: 'warning', child: Text('WARNING')),
              const PopupMenuItem(value: 'error', child: Text('ERROR')),
            ],
          ),
          IconButton(
            icon: Icon(
              uiState.autoScroll
                  ? Icons.unfold_less_rounded
                  : Icons.unfold_more_rounded,
              size: 22,
              color: uiState.autoScroll
                  ? theme.colorScheme.primary
                  : Colors.grey,
            ),
            onPressed: () {
              ref.read(logsPageUIProvider.notifier).toggleAutoScroll();
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, size: 20),
            onPressed: () {
              final text = logs
                  .map(
                    (l) =>
                        '[${l.timestamp}] ${l.level.toUpperCase()}: ${l.message}',
                  )
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('日志已复制到剪贴板'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, size: 22),
            onPressed: () {
              HapticFeedback.mediumImpact();
              ref.read(logProvider.notifier).clearLogs();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal_rounded, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 20),
          Text(
            '暂无日志记录',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '启动代理后将在此显示运行日志',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
