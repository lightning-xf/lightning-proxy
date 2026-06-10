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
    final s = S.of(context, ref);

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
                content: Text(s.get('sub_update_failed',
                    args: {'name': sub.name, 'error': sub.error})),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(s.get('sub_update_success', args: {'name': sub.name})),
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
                  tooltip: s.get('update_all'),
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
                    PopupMenuItem(
                      value: 'manual',
                      child: _PopupItem(
                          Icons.edit_note_rounded, s.get('manual_input')),
                    ),
                    PopupMenuItem(
                      value: 'clipboard',
                      child: _PopupItem(Icons.content_paste_rounded,
                          s.get('import_clipboard')),
                    ),
                    PopupMenuItem(
                      value: 'file',
                      child: _PopupItem(
                          Icons.file_open_rounded, s.get('import_from_file')),
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
                ? _buildEmptyState(context, ref)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (Platform.isWindows && constraints.maxWidth > 800) {
                        return GridView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 2.2,
                          ),
                          itemCount: subscriptions.length,
                          itemBuilder: (context, index) {
                            return _buildSubscriptionItem(
                              context,
                              ref,
                              subscriptions[index],
                              theme,
                              s,
                            );
                          },
                        );
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: subscriptions.length,
                        itemBuilder: (context, index) {
                          return _buildSubscriptionItem(
                            context,
                            ref,
                            subscriptions[index],
                            theme,
                            s,
                          );
                        },
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
            tooltip: s.get('update_all'),
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () {
              if (!Platform.isWindows) HapticFeedback.mediumImpact();
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
              if (!Platform.isWindows) HapticFeedback.lightImpact();
              _handleAddAction(context, ref, s, value);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'manual',
                child:
                    _PopupItem(Icons.edit_note_rounded, s.get('manual_input')),
              ),
              PopupMenuItem(
                value: 'clipboard',
                child: _PopupItem(
                    Icons.content_paste_rounded, s.get('import_clipboard')),
              ),
              PopupMenuItem(
                value: 'file',
                child: _PopupItem(
                    Icons.file_open_rounded, s.get('import_from_file')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final s = S.of(context, ref);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rss_feed_rounded, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 20),
          Text(
            s.get('no_subs_found'),
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.get('click_add_sub'),
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
        SnackBar(
          content: Text(s.get('clipboard_empty')),
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
        SnackBar(
          content: Text(s.get('no_valid_sub_link')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!Platform.isWindows) HapticFeedback.lightImpact();
    _showAddSubscriptionDialog(context, ref, s, initialUrl: foundUrl);
  }

  void _showSubscriptionContextMenu(
    BuildContext context,
    WidgetRef ref,
    SubscriptionModel sub,
    S s,
    Offset offset,
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
          value: 'edit',
          child: _PopupItem(Icons.edit_rounded, s.get('edit_subscription')),
        ),
        PopupMenuItem(
          value: 'toggle_auto',
          child: _PopupItem(
            sub.autoUpdate ? Icons.sync_disabled_rounded : Icons.sync_rounded,
            sub.autoUpdate
                ? s.get('disable_auto_update')
                : s.get('enable_auto_update'),
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: _PopupItem(Icons.copy_rounded, s.get('copy_link')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: _PopupItem(
              Icons.delete_outline_rounded, s.get('delete_subscription'),
              color: Colors.redAccent),
        ),
      ],
    );

    if (selected == null) return;

    switch (selected) {
      case 'edit':
        _showEditSubscriptionDialog(context, ref, sub, s);
        break;
      case 'toggle_auto':
        ref
            .read(subscriptionProvider.notifier)
            .toggleAutoUpdate(sub.id, !sub.autoUpdate);
        break;
      case 'copy':
        Clipboard.setData(ClipboardData(text: sub.url));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(s.get('link_copied')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;
      case 'delete':
        _showDeleteConfirm(context, ref, sub);
        break;
    }
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
    final formKey = GlobalKey<FormState>();
    bool autoUpdate = true;
    int interval = 24;
    bool currentIsFile = isFile;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initialUrl != null
              ? s.get('confirm_sub_info')
              : s.get('add_subscription')),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: s.get('sub_name'),
                      hintText: s.get('give_sub_name'),
                      prefixIcon: const Icon(Icons.label_outline_rounded),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return s.get('enter_sub_name');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: urlController,
                          decoration: InputDecoration(
                            labelText: currentIsFile
                                ? s.get('file_path')
                                : s.get('sub_link'),
                            hintText: currentIsFile
                                ? '/path/to/config.yaml'
                                : 'http://...',
                            prefixIcon: Icon(
                              currentIsFile
                                  ? Icons.file_present_rounded
                                  : Icons.link_rounded,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return currentIsFile
                                  ? s.get('enter_file_path')
                                  : s.get('enter_sub_link');
                            }
                            if (!currentIsFile) {
                              // 工业级标准 HTTP/HTTPS 链接匹配正则
                              final urlPattern =
                                  r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$';
                              final regExp = RegExp(
                                urlPattern,
                                caseSensitive: false,
                              );
                              if (!regExp.hasMatch(value.trim())) {
                                return s.get('invalid_sub_link');
                              }
                            }
                            return null;
                          },
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
                                  nameController.text =
                                      result.files.single.name;
                                }
                              });
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(
                      s.get('auto_update'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      currentIsFile
                          ? s.get('auto_reload_file')
                          : s.get('sync_cloud_nodes'),
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
                        Text(
                          s.get('update_interval_hours'),
                          style: const TextStyle(fontSize: 13),
                        ),
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.get('cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final sub = SubscriptionModel(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    url: urlController.text.trim(),
                    autoUpdate: autoUpdate,
                    updateInterval: interval,
                    isFile: currentIsFile,
                  );
                  ref.read(subscriptionProvider.notifier).addSubscription(sub);
                  Navigator.pop(context);
                }
              },
              child: Text(s.get('confirm')),
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
    if (Platform.isWindows) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(sub.name,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogOption(
                context,
                Icons.edit_rounded,
                s.get('edit_sub_label'),
                () {
                  Navigator.pop(context);
                  _showEditSubscriptionDialog(context, ref, sub, s);
                },
              ),
              _buildDialogOption(
                context,
                sub.autoUpdate
                    ? Icons.sync_disabled_rounded
                    : Icons.sync_rounded,
                sub.autoUpdate
                    ? s.get('close_auto_update')
                    : s.get('open_auto_update'),
                () {
                  ref
                      .read(subscriptionProvider.notifier)
                      .toggleAutoUpdate(sub.id, !sub.autoUpdate);
                  Navigator.pop(context);
                },
              ),
              _buildDialogOption(
                context,
                Icons.copy_rounded,
                s.get('copy_sub_link'),
                () {
                  Clipboard.setData(ClipboardData(text: sub.url));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(s.get('sub_link_copied')),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              _buildDialogOption(
                context,
                Icons.delete_outline_rounded,
                s.get('delete_sub_label'),
                () {
                  Navigator.pop(context);
                  _showDeleteConfirm(context, ref, sub);
                },
                isDestructive: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }

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
            title: Text(s.get('edit_sub_label')),
            onTap: () {
              Navigator.pop(context);
              _showEditSubscriptionDialog(context, ref, sub, s);
            },
          ),
          ListTile(
            leading: Icon(
              sub.autoUpdate ? Icons.sync_disabled_rounded : Icons.sync_rounded,
            ),
            title: Text(sub.autoUpdate
                ? s.get('close_auto_update')
                : s.get('open_auto_update')),
            onTap: () {
              ref
                  .read(subscriptionProvider.notifier)
                  .toggleAutoUpdate(sub.id, !sub.autoUpdate);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: Text(s.get('copy_sub_link')),
            onTap: () {
              Clipboard.setData(ClipboardData(text: sub.url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(s.get('sub_link_copied')),
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
            title: Text(
              s.get('delete_sub_label'),
              style: const TextStyle(color: Colors.redAccent),
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

  Widget _buildDialogOption(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.redAccent : theme.colorScheme.primary,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDestructive ? Colors.redAccent : null,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final formKey = GlobalKey<FormState>();
    bool autoUpdate = sub.autoUpdate;
    int interval = sub.updateInterval;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.get('edit_sub_label')),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: s.get('sub_name'),
                      prefixIcon: const Icon(Icons.label_outline_rounded),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return s.get('enter_sub_name_hint');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: urlController,
                          decoration: InputDecoration(
                            labelText: sub.isFile
                                ? s.get('file_path')
                                : s.get('sub_link'),
                            prefixIcon: Icon(
                              sub.isFile
                                  ? Icons.file_present_rounded
                                  : Icons.link_rounded,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return sub.isFile
                                  ? s.get('enter_file_path')
                                  : s.get('enter_sub_link');
                            }
                            if (!sub.isFile) {
                              final urlPattern =
                                  r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$';
                              final regExp = RegExp(
                                urlPattern,
                                caseSensitive: false,
                              );
                              if (!regExp.hasMatch(value.trim())) {
                                return s.get('invalid_sub_link');
                              }
                            }
                            return null;
                          },
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
                    title: Text(
                      s.get('auto_update'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
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
                        Text(
                          s.get('update_interval_hours'),
                          style: const TextStyle(fontSize: 13),
                        ),
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.get('cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final updated = sub.copyWith(
                    name: nameController.text.trim(),
                    url: urlController.text.trim(),
                    autoUpdate: autoUpdate,
                    updateInterval: interval,
                  );
                  ref
                      .read(subscriptionProvider.notifier)
                      .updateSubscriptionModel(updated);
                  Navigator.pop(context);
                }
              },
              child: Text(s.get('save')),
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
    final s = S.of(context, ref);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('delete_sub_label')),
        content: Text(s.get('delete_sub_confirm', args: {'name': sub.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('cancel')),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(subscriptionProvider.notifier)
                  .removeSubscription(sub.id);
              Navigator.pop(context);
            },
            child: Text(s.get('delete_sub_label'),
                style: const TextStyle(color: Colors.redAccent)),
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

  Widget _buildSubscriptionItem(
    BuildContext context,
    WidgetRef ref,
    SubscriptionModel sub,
    ThemeData theme,
    S s,
  ) {
    return MouseRegion(
      cursor: Platform.isWindows ? SystemMouseCursors.click : MouseCursor.defer,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? theme.dividerColor.withOpacity(0.05)
                : theme.dividerTheme.color ?? Colors.black.withOpacity(0.12),
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
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            hoverColor: theme.brightness == Brightness.dark
                ? Colors.white.withOpacity(0.04)
                : Colors.black.withOpacity(0.02),
            onTap: () {
              // Windows 端点击也可以触发详情/选项，增强易用性
              if (Platform.isWindows) {
                _showSubscriptionOptions(context, ref, sub, s);
              }
            },
            onSecondaryTapDown: (details) {
              if (Platform.isWindows) {
                _showSubscriptionContextMenu(
                    context, ref, sub, s, details.globalPosition);
              }
            },
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
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
                            color: theme.textTheme.titleMedium?.color,
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
                            borderRadius: BorderRadius.circular(6),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sub.isUpdating)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                          ),
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.refresh_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                          onPressed: () {
                            if (!Platform.isWindows) {
                              HapticFeedback.mediumImpact();
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('正在更新订阅: ${sub.name}...'),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                            ref
                                .read(subscriptionProvider.notifier)
                                .updateSubscription(sub.id);
                          },
                          tooltip: '更新订阅',
                        ),
                      if (Platform.isWindows) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.6),
                            size: 22,
                          ),
                          onPressed: () {
                            _showSubscriptionOptions(context, ref, sub, s);
                          },
                          tooltip: '更多操作',
                        ),
                      ],
                    ],
                  ),
                  onLongPress: Platform.isWindows
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          _showSubscriptionOptions(context, ref, sub, s);
                        },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    children: [
                      if (sub.totalData != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '流量使用',
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
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
                            value: (sub.usedData ?? 0) / (sub.totalData ?? 1),
                            backgroundColor:
                                theme.colorScheme.primary.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation(
                              theme.colorScheme.primary,
                            ),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: theme.textTheme.bodySmall?.color
                                    ?.withOpacity(0.7),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                sub.lastUpdate != null
                                    ? '最后更新: ${DateFormat('yyyy/MM/dd HH:mm').format(sub.lastUpdate!)}'
                                    : '从未更新',
                                style: TextStyle(
                                  color: theme.textTheme.bodySmall?.color
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
                                color: Colors.red.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
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
        ),
      ),
    );
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
