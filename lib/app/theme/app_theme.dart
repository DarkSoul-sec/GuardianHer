import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Raksha design system — safe, calm, trustworthy, minimal.
///
/// Visual identity: deep indigo primary, soft off-white background,
/// coral accent only for emergency. Clean Inter typography.
/// No pink overload, no stereotypes.
abstract final class AppTheme {
  AppTheme._();

  // ── Palette ──────────────────────────────────────────────────────────────
  // GuardianHer premium light system (spec):
  // warm off-white + deep indigo + soft lavender + coral SOS.
  static const Color guardianIndigo = Color(0xFF17134F);
  static const Color appBackground = Color(0xFFF8F7F4);
  static const Color appBackgroundAlt = Color(0xFFFAF9F6);
  static const Color appBackgroundMuted = Color(0xFFF4F2EE);
  static const Color lavenderSoft = Color(0xFFD9DAF5);
  static const Color lavenderMid = Color(0xFFC9C9EA);
  static const Color lavenderDeep = Color(0xFFBFC1E8);
  static const Color sosCoral = Color(0xFFF46B5E);
  static const Color sosCoralGlow = Color(0xFFFFD3CC);
  static const Color textBody = Color(0xFF5F5D6E);
  static const Color textFaint = Color(0xFF85838F);
  static const double cardRadius = 24;

  // Soft premium shadow shared by all light cards/nav.
  static List<BoxShadow> softShadow({double opacity = 0.08}) => [
        BoxShadow(
          color: guardianIndigo.withValues(alpha: opacity),
          blurRadius: 20,
          offset: const Offset(0, 6),
          spreadRadius: -6,
        ),
      ];

  // Primary — Deep Indigo
  static const Color indigoPrimary = Color(0xFF1E1B4B);
  static const Color indigoPrimaryLight = Color(0xFF312E81);
  static const Color indigoPrimaryDark = Color(0xFF0F0A33);

  // Background — Soft Off-White
  static const Color offWhite = Color(0xFFFFF8F5);
  static const Color offWhiteDark = Color(0xFFF5F0FF);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F0FF);

  // Accent — Coral (Emergency Only)
  static const Color coral = Color(0xFFFF6B6B);
  static const Color coralDark = Color(0xFFE85A5A);
  static const Color coralLight = Color(0xFFFF8A8A);
  static const Color coralGlow = Color(0x33FF6B6B);
  static const Color sosRedGlow = Color(0x40EF4444);

  // Text
  static const Color textPrimary = Color(0xFF1E1B4B);
  static const Color textSecondary = Color(0xFF4C4A6A);
  static const Color textMuted = Color(0xFF8A88A8);
  static const Color textOnCoral = Color(0xFFFFFFFF);
  static const Color textOnIndigo = Color(0xFFFFFFFF);

  // Semantic
  static const Color successGreen = Color(0xFF10B981);
  static const Color successGreenDark = Color(0xFF059669);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color infoCyan = Color(0xFF06B6D4);

  // Borders & Shadows
  static const Color borderLight = Color(0xFFE8E4F0);
  static const Color shadowLight = Color(0x1A1E1B4B);
  static const Color shadowMedium = Color(0x331E1B4B);

  // Glass/Card effects
  static const Color glassBorder = Color(0x1FFFFFFF);
  static const Color glassFill = Color(0x0DFFFFFF);
  static const Color glassFillElevated = Color(0x1AFFFFFF);

  // Additional text colors
  static const Color textDisabled = Color(0xFF64748B);
  static const Color textOnViolet = Color(0xFFEDE9FE);
  static const Color textLavender = Color(0xFFC4B5FD);

  // Additional colors
  static const Color magenta = Color(0xFFD946EF);
  static const Color glowDivider = Color(0x1FFFFFFF);

  // Brand seed (Material 3)
  static const Color seedColor = Color(0xFF1E1B4B);

  // ── Dark mode palette (for system compatibility) ─────────────────────────
  static const Color navyBase = Color(0xFF0B0F1E);
  static const Color navySurface = Color(0xFF131830);
  static const Color navySurfaceVariant = Color(0xFF1A1F3D);
  static const Color navyElevated = Color(0xFF1E2448);

  static const Color violet = Color(0xFF7C3AED);
  static const Color violetLight = Color(0xFF8B5CF6);
  static const Color violetDark = Color(0xFF5B21B6);

  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFFCBD5E1);
  static const Color textMutedDark = Color(0xFF94A3B8);

  static const Color sosRed = Color(0xFFEF4444);
  static const Color sosRedDark = Color(0xFFDC2626);

  // ── Theming ──────────────────────────────────────────────────────────────
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _buildDark();

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      primary: guardianIndigo,
      onPrimary: textOnIndigo,
      primaryContainer: lavenderSoft,
      secondary: guardianIndigo,
      onSecondary: textOnIndigo,
      surface: surfaceWhite,
      onSurface: guardianIndigo,
      onSurfaceVariant: textBody,
      error: sosCoral,
      onError: textOnCoral,
      outline: borderLight,
      surfaceContainerHighest: appBackgroundMuted,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: appBackground,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: GoogleFonts.inter().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: textSecondary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceWhite,
        indicatorColor: lavenderSoft,
        height: 80,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? guardianIndigo : textFaint,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? guardianIndigo : textFaint,
          );
        }),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceWhite,
        shadowColor: shadowLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: guardianIndigo,
          foregroundColor: textOnIndigo,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: indigoPrimary,
          side: const BorderSide(color: borderLight, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: _buildTextTheme(brightness),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: indigoPrimary,
        contentTextStyle: GoogleFonts.inter(color: textOnIndigo),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData _buildDark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ).copyWith(
      primary: indigoPrimary,
      onPrimary: textOnIndigo,
      primaryContainer: indigoPrimaryLight,
      secondary: violet,
      onSecondary: textPrimaryDark,
      surface: navySurface,
      onSurface: textPrimaryDark,
      onSurfaceVariant: textSecondaryDark,
      error: coral,
      onError: textOnCoral,
      outline: const Color(0xFF4C4678),
      surfaceContainerHighest: navyElevated,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: navyBase,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: GoogleFonts.inter().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          color: textPrimaryDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: textSecondaryDark),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navySurface,
        indicatorColor: violet.withValues(alpha: 0.25),
        height: 80,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? violetLight : textMutedDark,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? violetLight : textMutedDark,
          );
        }),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: navySurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF4C4678), width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: indigoPrimary,
          foregroundColor: textOnIndigo,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: violetLight,
          side: const BorderSide(color: Color(0xFF4C4678), width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: _buildTextTheme(Brightness.dark),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: navyElevated,
        contentTextStyle: GoogleFonts.inter(color: textPrimaryDark),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final color = brightness == Brightness.dark ? textPrimaryDark : guardianIndigo;
    final secondary = brightness == Brightness.dark ? textSecondaryDark : textBody;
    final muted = brightness == Brightness.dark ? textMutedDark : textFaint;

    return TextTheme(
      displayLarge: GoogleFonts.inter(color: color, fontWeight: FontWeight.w700),
      displayMedium: GoogleFonts.inter(color: color, fontWeight: FontWeight.w700),
      displaySmall: GoogleFonts.inter(color: color, fontWeight: FontWeight.w700),
      headlineLarge: GoogleFonts.inter(color: color, fontWeight: FontWeight.w700),
      headlineMedium: GoogleFonts.inter(color: color, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      headlineSmall: GoogleFonts.inter(color: color, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      titleLarge: GoogleFonts.inter(color: color, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.inter(color: secondary, fontWeight: FontWeight.w500),
      titleSmall: GoogleFonts.inter(color: secondary, fontWeight: FontWeight.w500, fontSize: 13),
      bodyLarge: GoogleFonts.inter(color: secondary, fontSize: 16, height: 1.6),
      bodyMedium: GoogleFonts.inter(color: secondary, fontSize: 16, height: 1.6),
      bodySmall: GoogleFonts.inter(color: muted, fontSize: 13, height: 1.5),
      labelLarge: GoogleFonts.inter(color: secondary, fontWeight: FontWeight.w600, fontSize: 14),
      labelMedium: GoogleFonts.inter(color: secondary, fontSize: 12),
      labelSmall: GoogleFonts.inter(color: muted, fontSize: 11),
    );
  }
}