import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color tokens lifted 1:1 from the web theme:
/// --ink:#17201c --muted:#68736c --line:#dfe5df --paper:#fff
/// --canvas:#f6f7f4 --green:#146c4a --green-soft:#e4f1e8
/// --orange:#b75f2b --orange-soft:#fff0df --red:#ad3c38 --red-soft:#fbe8e6
class AppColors {
  static const ink = Color(0xFF17201C);
  static const muted = Color(0xFF68736C);
  static const line = Color(0xFFDFE5DF);
  static const paper = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFF6F7F4);
  static const green = Color(0xFF146C4A);
  static const greenSoft = Color(0xFFE4F1E8);
  static const orange = Color(0xFFB75F2B);
  static const orangeSoft = Color(0xFFFFF0DF);
  static const red = Color(0xFFAD3C38);
  static const redSoft = Color(0xFFFBE8E6);

  // Extra stops used only for the animated "ask-ai" gradient button.
  static const violet = Color(0xFF5A4FCF);
  static const greenBright = Color(0xFF248F68);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.green,
        brightness: Brightness.light,
        primary: AppColors.green,
        surface: AppColors.paper,
        error: AppColors.red,
      ),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      dividerColor: AppColors.line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.green, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.line.withValues(alpha: 0.6)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.red),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
