import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/app_channel.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:lightning/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSplittingPage extends ConsumerStatefulWidget {
  const AppSplittingPage({super.key});

  @override
  ConsumerState<AppSplittingPage> createState() => _AppSplittingPageState();
}

class _AppSplittingPageState extends ConsumerState<AppSplittingPage> {
  List<AppInfo> _apps = [];
  Set<String> _proxyApps = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    final apps = await AppChannel.getInstalledApps();
    final prefs = await SharedPreferences.getInstance();
    final proxyList = prefs.getStringList('proxy_apps') ?? [];

    setState(() {
      _apps = apps..sort((a, b) => a.name.compareTo(b.name));
      _proxyApps = proxyList.toSet();
      _isLoading = false;
    });
  }

  Future<void> _saveApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('proxy_apps', _proxyApps.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context, ref);
    final filteredApps = _apps
        .where(
          (app) =>
              app.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              app.packageName.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ),
        )
        .toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          s.get('app_split'),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                if (_proxyApps.length == _apps.length) {
                  _proxyApps.clear();
                } else {
                  _proxyApps.addAll(_apps.map((e) => e.packageName));
                }
              });
              _saveApps();
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(140),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Consumer(
                  builder: (context, ref, child) {
                    final settings = ref.watch(vpnSettingsProvider);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            settings.bypassApps
                                ? Icons.block_rounded
                                : Icons.vpn_lock_rounded,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              settings.bypassApps
                                  ? s.get('bypass_apps_desc')
                                  : s.get('proxy_apps_desc'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Switch(
                            value: settings.bypassApps,
                            onChanged: (v) {
                              ref
                                  .read(vpnSettingsProvider.notifier)
                                  .update(settings.copyWith(bypassApps: v));
                            },
                            activeColor: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: s.get('search_installed_apps'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: theme.cardTheme.color,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: filteredApps.length,
              itemBuilder: (context, index) {
                final app = filteredApps[index];
                final isSelected = _proxyApps.contains(app.packageName);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary.withOpacity(0.3)
                          : Colors.white.withOpacity(0.02),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.android_rounded,
                        size: 28,
                        color: Colors.grey,
                      ),
                    ),
                    title: Text(
                      app.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      app.packageName,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: theme.colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (v) {
                        HapticFeedback.lightImpact();
                        setState(() {
                          if (v == true) {
                            _proxyApps.add(app.packageName);
                          } else {
                            _proxyApps.remove(app.packageName);
                          }
                        });
                        _saveApps();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
