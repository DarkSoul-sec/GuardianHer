import 'package:flutter/material.dart';

/// Centralized Material 3 theme for GuardianHer.
abstract final class AppTheme {
  AppTheme._();

  /// Brand seed color. Branding decisions can be refined without affecting
  /// consumers of this class.
  static const Color seedColor = Color(0xFF6750A4);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}