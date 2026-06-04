import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lightning/core/localization_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightning/core/log_provider.dart';
import 'package:lightning/pages/home_page.dart';
import 'package:lightning/pages/splash_screen.dart';
import 'package:lightning/theme/app_theme.dart';

// Provider for showing splash screen
class SplashNotifier extends StateNotifier<bool> {
  static bool _hasShownSplash = false;
  SplashNotifier() : super(!_hasShownSplash) {
    if (!_hasShownSplash) {
      _hasShownSplash = true;
    }
  }

  void finish() {
    state = false;
  }
}

final showSplashProvider = StateNotifierProvider<SplashNotifier, bool>((ref) {
  return SplashNotifier();
});

// Provider for theme mode
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(bool? isDark)
    : super(
        isDark == null
            ? ThemeMode.system
            : (isDark ? ThemeMode.dark : ThemeMode.light),
      );

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', state == ThemeMode.dark);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return throw UnimplementedError();
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode');

  final container = ProviderContainer(
    overrides: [
      themeModeProvider.overrideWith((ref) => ThemeModeNotifier(isDark)),
    ],
  );

  // 初始化日志容器引用，以便在 LogNotifier 中访问 vpnProvider
  container.read(logProvider.notifier).setContainer(container);

  // Capture Flutter framework errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    container
        .read(logProvider.notifier)
        .addLog('error', 'Flutter Error: ${details.exceptionAsString()}');
  };

  // Capture platform-level errors (e.g. from async tasks)
  PlatformDispatcher.instance.onError = (error, stack) {
    container
        .read(logProvider.notifier)
        .addLog('error', 'Platform Error: $error');
    return true;
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LightningApp(),
    ),
  );
}

class LightningApp extends ConsumerWidget {
  const LightningApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localizationProvider);
    final showSplash = ref.watch(showSplashProvider);

    return MaterialApp(
      title: 'Lightning',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: showSplash
          ? SplashScreen(
              onFinish: () => ref.read(showSplashProvider.notifier).finish(),
            )
          : const HomePage(),
    );
  }
}
