import 'package:flutter/material.dart';

/// 视觉语言的单一事实来源。
///
/// 用一套手工微调的小色板（冷蓝强调色）而不是照搬 Material 默认值，几乎不做
/// 主题定制就能让天气卡片看起来是经过设计的。
class AppTheme {
  AppTheme._();

  static const Color _accent = Color(0xFF3D7BF7);
  static const Color _bgLight = Color(0xFFF4F6FA);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bgLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: _bgLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: TextStyle(color: Colors.grey.shade500),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.zero),
    );
  }
}
