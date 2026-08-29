import 'package:flutter/material.dart';

/// Premium dark-mode design system for GuardianHer.
///
/// Visual identity: deep midnight navy / near-black background, electric purple
/// and violet accent gradients, white + soft-lavender typography, subtle
/// glassmorphism.  The aesthetic draws from cybersecurity dashboards, modern
/// emergency-response systems, and high-end fintech applications.
///
/// Light variant is included for system-compatibility but the product always
/// runs in dark mode (see [ThemeMode.dark] in [GuardianHerApp]).
abstract final class AppTheme {
  AppTheme._();

  // ── Palette ──────────────────────────────────────────────────────────────
  static const Color navyBase = Color(0xFF0B0F1E);
  static const Color navySurface = Color(0xFF131830);
  static const Color navySurfaceVariant = Color(0xFF1A1F3D);
  static const Color navyElevated = Color(0xFF1E2448);

  static const Color violet = Color(0xFF7C3AED);
  static const Color violetLight = Color(0xFF8B5CF6);
  static const Color violetDark = Color(0xFF5B21B6);
  static const Color magenta = Color(0xFFD946EF);
  static const Color purpleGlow = Color(0xFFA855F7);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFFCBD5E1);
  static const Color textLavender = Color(0xFFC4B5FD);
  static const Color textMuted = Color(0xFF94A3B8);

  static const Color sosRed = Color(0xFFEF4444);
  static const Color sosRedDark = Color(0xFFDC2626);
  static const Color sosRedGlow = Color(0x40EF4444);
  static const Color successGreen = Color(0xFF22C55E);
  static const Color successGreenDark = Color(0xFF16A34A);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color infoCyan = Color(0xFF06B6D4);

  static const Color glassBorder = Color(0x1FFFFFFF);
  static const Color glassFill = Color(0x0DFFFFFF);
  static const Color glassFillElevated = Color(0x1AFFFFFF);

  // ── Brand seed (Material 3) ─────────────────────────────────────────────
  static const Color seedColor = Color(0xFF7C3AED);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  // ── Theming ─────────────────────────────────────────────────────────────
  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? violet : seedColor,
      onPrimary: isDark ? textPrimary : Colors.white,
      primaryContainer: isDark ? violetDark : const Color(0xFFEDE9FE),
      secondary: isDark ? magenta : const Color(0xFFD946EF),
      onSecondary: isDark ? textPrimary : Colors.white,
      surface: isDark ? navySurface : const Color(0xFFFFF8FB),
      onSurface: isDark ? textPrimary : const Color(0xFF1E293B),
      onSurfaceVariant: isDark ? textLavender : const Color(0xFF64748B),
      error: isDark ? sosRed : const Color(0xFFDC2626),
      onError: isDark ? textPrimary : Colors.white,
      outline: isDark ? const Color(0xFF4C4678) : const Color(0xFFE2E8F0),
      surfaceContainerHighest: isDark ? navyElevated : const Color(0xFFF1F5F9),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? navyBase : scheme.surface,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: isDark ? textPrimary : scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(
          color: isDark ? textSecondary : scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? navySurface : Colors.white,
        indicatorColor: isDark
            ? violet.withValues(alpha: 0.25)
            : scheme.primaryContainer,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? (isDark ? violetLight : scheme.primary)
                : (isDark ? textMuted : scheme.onSurfaceVariant),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected
                ? (isDark ? violetLight : scheme.primary)
                : (isDark ? textMuted : scheme.onSurfaceVariant),
          );
        }),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? navySurfaceVariant : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark
              ? const BorderSide(color: glassBorder, width: 0.5)
              : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(
            color: isDark ? violetLight : scheme.outline,
            width: 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textTheme: _buildTextTheme(brightness),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? navyElevated : scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: isDark ? textPrimary : scheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final color = brightness == Brightness.dark ? textPrimary : const Color(0xFF1E293B);
    final secondary = brightness == Brightness.dark ? textSecondary : const Color(0xFF64748B);
    final lavender = brightness == Brightness.dark ? textLavender : const Color(0xFF7C3AED);

    return TextTheme(
      displayLarge: TextStyle(color: color, fontWeight: FontWeight.w700),
      displayMedium: TextStyle(color: color, fontWeight: FontWeight.w700),
      displaySmall: TextStyle(color: color, fontWeight: FontWeight.w700),
      headlineLarge: TextStyle(color: color, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(color: color, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      headlineSmall: TextStyle(color: color, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      titleLarge: TextStyle(color: color, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: lavender, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(color: lavender, fontWeight: FontWeight.w500, fontSize: 13),
      bodyLarge: TextStyle(color: secondary, fontSize: 15, height: 1.5),
      bodyMedium: TextStyle(color: secondary, height: 1.5),
      bodySmall: TextStyle(color: secondary, fontSize: 12, height: 1.4),
      labelLarge: TextStyle(color: lavender, fontWeight: FontWeight.w600, fontSize: 13),
      labelMedium: TextStyle(color: lavender, fontSize: 12),
      labelSmall: TextStyle(color: secondary, fontSize: 11),
    );
  }
}
