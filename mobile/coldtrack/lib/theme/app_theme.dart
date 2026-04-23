import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the ColdTrack app.
class AppColors {
  static const background = Color(0xFF0A0E1A);
  static const surface = Color(0xFF111827);
  static const card = Color(0xFF1C2537);

  static const primary = Color(0xFF00D4AA);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const safe = Color(0xFF10B981);

  static const textPrimary = Color(0xFFF9FAFB);
  static const textSecondary = Color(0xFF9CA3AF);

  static const border = Color(0xFF293145);

  /// Dot-grid texture overlay used on dark backgrounds.
  static const gridDot = Color(0x08FFFFFF); // rgba(255,255,255,0.03)
}

/// Central risk level → colour mapping.
enum RiskLevel { low, medium, high, critical, unknown }

extension RiskLevelColor on RiskLevel {
  Color get color {
    switch (this) {
      case RiskLevel.low:
        return AppColors.primary;
      case RiskLevel.medium:
        return AppColors.warning;
      case RiskLevel.high:
        return const Color(0xFFF97316);
      case RiskLevel.critical:
        return AppColors.danger;
      case RiskLevel.unknown:
        return AppColors.textSecondary;
    }
  }

  String get label {
    switch (this) {
      case RiskLevel.low:
        return 'SAFE';
      case RiskLevel.medium:
        return 'MONITOR';
      case RiskLevel.high:
        return 'WARNING';
      case RiskLevel.critical:
        return 'CRITICAL';
      case RiskLevel.unknown:
        return 'UNKNOWN';
    }
  }

  /// Pulse cadence — slow (gentle breath) when safe, fast (urgent) when critical.
  Duration get pulseDuration {
    switch (this) {
      case RiskLevel.low:
        return const Duration(milliseconds: 2400);
      case RiskLevel.medium:
        return const Duration(milliseconds: 1400);
      case RiskLevel.high:
        return const Duration(milliseconds: 900);
      case RiskLevel.critical:
        return const Duration(milliseconds: 550);
      case RiskLevel.unknown:
        return const Duration(milliseconds: 2400);
    }
  }
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    // Display numerals — Syne is very bold and wide, ideal for the gauge.
    final displayStyle = GoogleFonts.syne(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w800,
    );
    final headingStyle = GoogleFonts.spaceGrotesk(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w600,
    );
    final bodyStyle = GoogleFonts.dmSans(color: AppColors.textPrimary);

    // Uppercase tracked labels shared by status badges, stat pills, section heads.
    final labelTracked = bodyStyle.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.88, // 0.08em at 11sp
      color: AppColors.textSecondary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        secondary: AppColors.primary,
        surface: AppColors.surface,
        error: AppColors.danger,
        onPrimary: AppColors.background,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: TextTheme(
        // Display = gauge numeral, stat pill value — Syne
        displayLarge: displayStyle.copyWith(fontSize: 64, height: 1.0),
        displayMedium: displayStyle.copyWith(fontSize: 44, height: 1.0),
        displaySmall: displayStyle.copyWith(fontSize: 32, height: 1.0),
        // Headline = screen titles, card titles — Space Grotesk
        headlineLarge: headingStyle.copyWith(fontSize: 28),
        headlineMedium: headingStyle.copyWith(fontSize: 22),
        headlineSmall: headingStyle.copyWith(fontSize: 18),
        titleLarge: headingStyle.copyWith(fontSize: 20),
        titleMedium: headingStyle.copyWith(fontSize: 16),
        // Body — DM Sans
        bodyLarge: bodyStyle.copyWith(fontSize: 16),
        bodyMedium: bodyStyle.copyWith(fontSize: 14),
        bodySmall: bodyStyle.copyWith(fontSize: 12, color: AppColors.textSecondary),
        // Label = pill labels, section heads
        labelLarge: labelTracked,
        labelMedium: labelTracked.copyWith(fontSize: 10, letterSpacing: 0.8),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: headingStyle.copyWith(fontSize: 20),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28), // pill
          ),
          textStyle: bodyStyle.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: bodyStyle.copyWith(color: AppColors.textSecondary),
        hintStyle: bodyStyle.copyWith(color: AppColors.textSecondary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
      ),
    );
  }
}
