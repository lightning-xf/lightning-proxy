import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/uwp_exemption_manager.dart';
import 'package:lightning/core/localization_provider.dart';

class UwpExemptionDialog extends ConsumerStatefulWidget {
  const UwpExemptionDialog({super.key});

  @override
  ConsumerState<UwpExemptionDialog> createState() => _UwpExemptionDialogState();
}

class _UwpExemptionDialogState extends ConsumerState<UwpExemptionDialog> {
  List<UwpApp> _allApps = [];
  List<UwpApp> _filteredApps = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _isLoading = true);
    final apps = await UwpExemptionManager.getUwpApps();
    if (mounted) {
      setState(() {
        _allApps = apps;
        _filteredApps = apps;
        _isLoading = false;
      });
    }
  }

  void _filterApps(String query) {
    setState(() {
      _searchQuery = query;
      _filteredApps = _allApps
          .where((app) =>
              app.name.toLowerCase().contains(query.toLowerCase()) ||
              app.packageFamilyName.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _toggleExemption(UwpApp app, bool value) async {
    final success =
        await UwpExemptionManager.setExemption(app.packageFamilyName, value);
    if (success) {
      _loadApps();
    } else {
      if (mounted) {
        final s = S.of(context, ref);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.get('operation_failed_need_admin'))),
        );
      }
    }
  }

  Future<void> _setAll(bool exempt) async {
    setState(() => _isLoading = true);
    final pfns = _filteredApps.map((e) => e.packageFamilyName).toList();
    await UwpExemptionManager.setAllExemption(pfns, exempt);
    await _loadApps();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context, ref);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : Colors.white,
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.apps_outage_rounded,
                      color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.get('uwp_exemption_title'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        s.get('uwp_exemption_desc'),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              onChanged: _filterApps,
              decoration: InputDecoration(
                hintText: s.get('search_apps_hint'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: theme.brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.02),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _setAll(true),
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                  label: Text(s.get('exempt_all')),
                  style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _setAll(false),
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: Text(s.get('clear_all')),
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.redAccent),
                ),
                const Spacer(),
                Text(
                  s
                      .get('scanned_apps_count')
                      .replaceAll('{count}', '${_allApps.length}'),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredApps.isEmpty
                      ? Center(child: Text(s.get('no_apps_found')))
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _filteredApps.length,
                          itemBuilder: (context, index) {
                            final app = _filteredApps[index];
                            return ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              title: Text(
                                app.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                app.packageFamilyName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.5),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Switch(
                                value: app.isExempted,
                                onChanged: (val) => _toggleExemption(app, val),
                                activeColor: theme.colorScheme.primary,
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.get('uwp_exemption_warning'),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
