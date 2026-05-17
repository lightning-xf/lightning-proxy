import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/core/subscription_model.dart';
import 'package:lightning/core/subscription_provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

class SubscriptionsPage extends ConsumerWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(subscriptionProvider);

    // Listen for update results
    ref.listen(subscriptionProvider, (previous, next) {
      if (previous == null) return;

      for (final sub in next) {
        final prevSub = previous.firstWhere(
          (p) => p.id == sub.id,
          orElse: () => sub,
        );

        // Just finished updating
        if (prevSub.isUpdating && !sub.isUpdating) {
          if (sub.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('订阅 "${sub.name}" 更新失败: ${sub.error}'),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('订阅 "${sub.name}" 更新成功'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    });

    final theme = Theme.of(context);
    final s = S.of(context, ref);
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
              title: Text(
                s.get('sub_settings'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: '全部更新',
                  icon: const Icon(Icons.refresh_rounded, size: 22),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    for (final sub in subscriptions) {
                      ref
                          .read(subscriptionProvider.notifier)
                          .updateSubscription(sub.id);
                    }
                  },
                ),
                PopupMenuButton<String>(
                  offset: const Offset(0, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                  onSelected: (value) {
                    HapticFeedback.lightImpact();
                    _handleAddAction(context, ref, s, value);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'manual',
                      child: _PopupItem(Icons.edit_note_rounded, '手动输入'),
                    ),
                    const PopupMenuItem(
                      value: 'clipboard',
                      child: _PopupItem(Icons.content_paste_rounded, '从剪贴板导入'),
                    ),
                    const PopupMenuItem(
                      value: 'file',
                      child: _PopupItem(Icons.file_open_rounded, '从文件导入'),
                    ),
                  ],
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          if (!isMobile) _buildHeader(context, ref, subscriptions, s, theme),
          Expanded(
            child: subscriptions.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: subscriptions.length,
                    itemBuilder: (context, index) {
                      final sub = subscriptions[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.05),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                          clipBehavior: Clip.antiAlias, // 修复点击时的暗色三角问题
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  12,
                                  12,
                                ),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.rss_feed_rounded,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        sub.name,
                                        style: TextStyle(
                                          color: theme
                                              .textTheme
                                              .titleMedium
                                              ?.color,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    if (sub.autoUpdate)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Text(
                                          '自动更新',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    sub.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.textTheme.bodySmall?.color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                trailing: sub.isUpdating
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : IconButton(
                                        icon: Icon(
                                          Icons.refresh_rounded,
                                          color: theme.colorScheme.primary,
                                          size: 26,
                                        ),
                                        onPressed: () {
                                          HapticFeedback.mediumImpact();
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '正在更新订阅: ${sub.name}...',
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              duration: const Duration(
                                                seconds: 1,
                                              ),
                                            ),
                                          );
                                          ref
                                              .read(
                                                subscriptionProvider.notifier,
                                              )
                                              .updateSubscription(sub.id);
                                        },
                                      ),
                                onLongPress: () {
                                  HapticFeedback.mediumImpact();
                                  _showSubscriptionOptions(
                                    context,
                                    ref,
                                    sub,
                                    s,
                                  );
                                },
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                child: Divider(height: 1),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  16,
                                ),
                                child: Column(
                                  children: [
                                    if (sub.totalData != null) ...[
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '流量使用',
                                            style: TextStyle(
                                              color: theme
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '${_formatData(sub.usedData ?? 0)} / ${_formatData(sub.totalData ?? 0)}',
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value:
                                              (sub.usedData ?? 0) /
                                              (sub.totalData ?? 1),
                                          backgroundColor: theme
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.1),
                                          valueColor: AlwaysStoppedAnimation(
                                            theme.colorScheme.primary,
                                          ),
                                          minHeight: 6,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.access_time_rounded,
                                              size: 14,
                                              color: theme
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color
                                                  ?.withOpacity(0.7),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              sub.lastUpdate != null
                                                  ? '最后更新: ${DateFormat('yyyy/MM/dd HH:mm').format(sub.lastUpdate!)}'
                                                  : '从未更新',
                                              style: TextStyle(
                                                color: theme
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color
                                                    ?.withOpacity(0.6),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (sub.error != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(
                                                0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.error_outline_rounded,
                                                  size: 12,
                                                  color: Colors.redAccent,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  '更新失败',
                                                  style: TextStyle(
                                                    color: Colors.redAccent,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    List<SubscriptionModel> subscriptions,
    S s,
    ThemeData theme,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            s.get('sub_settings'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '全部更新',
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () {
              HapticFeedback.mediumImpact();
              for (final sub in subscriptions) {
                ref
                    .read(subscriptionProvider.notifier)
                    .updateSubscription(sub.id);
              }
            },
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            onSelected: (value) {
              HapticFeedback.lightImpact();
              _handleAddAction(context, ref, s, value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'manual',
                child: _PopupItem(Icons.edit_note_rounded, '手动输入'),
              ),
              const PopupMenuItem(
                value: 'clipboard',
                child: _PopupItem(Icons.content_paste_rounded, '从剪贴板导入'),
              ),
              const PopupMenuItem(
                value: 'file',
                child: _PopupItem(Icons.file_open_rounded, '从文件导入'),
              ),
            ],
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
          Icon(Icons.rss_feed_rounded, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 20),
          Text(
            '暂无订阅内容',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角按钮添加订阅链接',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _formatData(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return "${(bytes / math.pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}";
  }

  void _importFromClipboard(BuildContext context, WidgetRef ref, S s) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('剪贴板为空'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Support multiple links separated by newlines, take the first one that looks like a URL
    final lines = text.split(RegExp(r'[\n\r]+'));
    String? foundUrl;
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('http')) {
        foundUrl = trimmed;
        break;
      }
    }

    if (foundUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('剪贴板中没有有效的订阅链接 (需以 http 开头)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    _showAddSubscriptionDialog(context, ref, s, initialUrl: foundUrl);
  }

  void _showAddSubscriptionDialog(
    BuildContext context,
    WidgetRef ref,
    S s, {
    String? initialUrl,
    String? initialName,
    bool isFile = false,
  }) {
    final nameController = TextEditingController(
      text: initialName ?? (initialUrl != null ? '新订阅' : ''),
    );
    final urlController = TextEditingController(text: initialUrl ?? '');
    bool autoUpdate = true;
    int interval = 24;
    bool currentIsFile = isFile;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initialUrl != null ? '确认订阅信息' : '添加订阅'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '订阅名称',
                    hintText: '给订阅起个名字',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                          labelText: currentIsFile ? '文件路径' : '订阅链接',
                          hintText: currentIsFile
                              ? '/path/to/config.yaml'
                              : 'http://...',
                          prefixIcon: Icon(
                            currentIsFile
                                ? Icons.file_present_rounded
                                : Icons.link_rounded,
                          ),
                        ),
                      ),
                    ),
                    if (currentIsFile)
                      IconButton(
                        icon: const Icon(Icons.folder_open_rounded),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.any,
                          );
                          if (result != null &&
                              result.files.single.path != null) {
                            setState(() {
                              urlController.text = result.files.single.path!;
                              if (nameController.text.isEmpty ||
                                  nameController.text == '新订阅') {
                                nameController.text = result.files.single.name;
                              }
                            });
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text(
                    '自动更新',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    currentIsFile ? '定期重新读取文件内容' : '定期同步云端节点',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: autoUpdate,
                  onChanged: (v) => setState(() => autoUpdate = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (autoUpdate)
                  Row(
                    children: [
                      const Icon(
                        Icons.update_rounded,
                        size: 20,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      const Text('更新间隔 (小时): ', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: interval,
                        items: [1, 6, 12, 24, 48, 72]
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => interval = v!),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (urlController.text.isEmpty) return;
                final sub = SubscriptionModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.isEmpty
                      ? '未命名订阅'
                      : nameController.text,
                  url: urlController.text.trim(),
                  autoUpdate: autoUpdate,
                  updateInterval: interval,
                  isFile: currentIsFile,
                );
                ref.read(subscriptionProvider.notifier).addSubscription(sub);
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubscriptionOptions(
    BuildContext context,
    WidgetRef ref,
    SubscriptionModel sub,
    S s,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('编辑订阅'),
            onTap: () {
              Navigator.pop(context);
              _showEditSubscriptionDialog(context, ref, sub, s);
            },
          ),
          ListTile(
            leading: Icon(
              sub.autoUpdate ? Icons.sync_disabled_rounded : Icons.sync_rounded,
            ),
            title: Text(sub.autoUpdate ? '关闭自动更新' : '开启自动更新'),
            onTap: () {
              ref
                  .read(subscriptionProvider.notifier)
                  .toggleAutoUpdate(sub.id, !sub.autoUpdate);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('复制订阅链接'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: sub.url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('订阅链接已复制到剪贴板'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
            title: const Text(
              '删除订阅',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirm(context, ref, sub);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _showEditSubscriptionDialog(
    BuildContext context,
    WidgetRef ref,
    SubscriptionModel sub,
    S s,
  ) {
    final nameController = TextEditingController(text: sub.name);
    final urlController = TextEditingController(text: sub.url);
    bool autoUpdate = sub.autoUpdate;
    int interval = sub.updateInterval;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('编辑订阅'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '订阅名称',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                          labelText: sub.isFile ? '文件路径' : '订阅链接',
                          prefixIcon: Icon(
                            sub.isFile
                                ? Icons.file_present_rounded
                                : Icons.link_rounded,
                          ),
                        ),
                      ),
                    ),
                    if (sub.isFile)
                      IconButton(
                        icon: const Icon(Icons.folder_open_rounded),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.any,
                          );
                          if (result != null &&
                              result.files.single.path != null) {
                            setState(() {
                              urlController.text = result.files.single.path!;
                            });
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text(
                    '自动更新',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  value: autoUpdate,
                  onChanged: (v) => setState(() => autoUpdate = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (autoUpdate)
                  Row(
                    children: [
                      const Icon(
                        Icons.update_rounded,
                        size: 20,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      const Text('更新间隔 (小时): ', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: interval,
                        items: [1, 6, 12, 24, 48, 72]
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => interval = v!),
                      ),
                    ],
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
                final updated = sub.copyWith(
                  name: nameController.text,
                  url: urlController.text.trim(),
                  autoUpdate: autoUpdate,
                  updateInterval: interval,
                );
                ref
                    .read(subscriptionProvider.notifier)
                    .updateSubscriptionModel(updated);
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(
    BuildContext context,
    WidgetRef ref,
    SubscriptionModel sub,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订阅'),
        content: Text('确定要删除订阅 "${sub.name}" 吗？相关的节点也将被移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(subscriptionProvider.notifier)
                  .removeSubscription(sub.id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _handleAddAction(
    BuildContext context,
    WidgetRef ref,
    S s,
    String action,
  ) {
    switch (action) {
      case 'manual':
        _showAddSubscriptionDialog(context, ref, s);
        break;
      case 'clipboard':
        _importFromClipboard(context, ref, s);
        break;
      case 'file':
        _importFromFile(context, ref, s);
        break;
    }
  }

  void _importFromFile(BuildContext context, WidgetRef ref, S s) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType
            .any, // Allow any file type as some configs might not have .yaml or .txt
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;
        _showAddSubscriptionDialog(
          context,
          ref,
          s,
          initialUrl: path,
          initialName: name,
          isFile: true,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('选择文件失败: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Define _PopupItem inside SubscriptionsPage or as a private class if not defined
}

class _PopupItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PopupItem(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
