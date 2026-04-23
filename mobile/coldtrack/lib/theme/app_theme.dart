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
}

/// Central risk level → colour mapping.
enum RiskLevel { low, medium, high, critical, unknown }

extension RiskLevelColor on RiskLevel {
  Color get color {
    switch (this) {
      case RiskLevel.low:
        return AppColors.safe;
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
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    final headingStyle = GoogleFonts.spaceGrotesk(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final bodyStyle = GoogleFonts.dmSans(color: AppColors.textPrimary);

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
        displayLarge: headingStyle.copyWith(fontSize: 48),
        displayMedium: headingStyle.copyWith(fontSize: 36),
        headlineLarge: headingStyle.copyWith(fontSize: 28),
        headlineMedium: headingStyle.copyWith(fontSize: 22),
        headlineSmall: headingStyle.copyWith(fontSize: 18),
        titleLarge: headingStyle.copyWith(fontSize: 20),
        titleMedium: headingStyle.copyWith(fontSize: 16),
        bodyLarge: bodyStyle.copyWith(fontSize: 16),
        bodyMedium: bodyStyle.copyWith(fontSize: 14),
        bodySmall: bodyStyle.copyWith(fontSize: 12, color: AppColors.textSecondary),
        labelLarge: bodyStyle.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
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
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: bodyStyle.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
    );
  }
}
