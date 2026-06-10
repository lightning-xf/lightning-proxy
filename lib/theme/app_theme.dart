import 'package:flutter/material.dart';

class AppTheme {
  static const Color bgLight = Color(0xFFF1F5F9);
  static const Color bgDark = Color(0xFF0F172A);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color textMain = Color(0xFF0F172A);
  static const Color textDark = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textDisabled = Color(0xFF64748B);
  static const Color strokeColor =
      Color(0x26000000); // 增加不透明度从 0x1A (10%) 到 0x26 (15%)

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      onPrimary: Colors.white,
      secondary: primaryBlue,
      onSecondary: Colors.white,
      surface: Colors.white,
      background: bgLight,
    ),
    scaffoldBackgroundColor: bgLight,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 18,
        color: textMain,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: textMain,
      ),
      titleSmall: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: textSecondary,
      ),
      bodyLarge: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: textMain,
      ),
      bodyMedium: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: textMain,
      ),
      bodySmall: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: textSecondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: textMain,
        letterSpacing: -0.5,
      ),
      iconTheme: IconThemeData(color: primaryBlue, size: 24),
    ),
    cardTheme: CardThemeData(
      color: Colors.white, // 使用纯白，增加对比度
      elevation: 2, // 减小 elevation 以获得更清晰的边框感
      shadowColor: Colors.black.withValues(alpha: 0.08), // 稍微加深阴影
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: strokeColor, width: 1.2), // 增加边框粗细和对比度
      ),
    ),
    dividerTheme: const DividerThemeData(color: strokeColor, thickness: 1),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      onPrimary: Colors.white,
      secondary: primaryBlue,
      onSecondary: Colors.white,
      surface: bgDark,
    ),
    scaffoldBackgroundColor: bgDark,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 18,
        color: textDark,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: textDark,
      ),
      titleSmall: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: textSecondary,
      ),
      bodyLarge: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: textDark,
      ),
      bodyMedium: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: textDark,
      ),
      bodySmall: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: textSecondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: textDark,
        letterSpacing: -0.5,
      ),
      iconTheme: IconThemeData(color: primaryBlue, size: 24),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E293B),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.05),
      thickness: 1,
    ),
  );
}
