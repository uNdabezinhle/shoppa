/// Design tokens ported from the Shoppa interactive prototype
/// (shoppa-prototype.jsx) so the Flutter build matches the validated UX.
import 'package:flutter/material.dart';

class ShoppaColors {
  ShoppaColors._();

  static const obsidian = Color(0xFF0B0E14);
  static const panel = Color(0xFF12161F);
  static const panel2 = Color(0xFF1A1F2B);
  static const line = Color(0xFF252B38);
  static const amber = Color(0xFFF5A623);
  static const amberBright = Color(0xFFFFB627);
  static const gold = Color(0xFFE8B339);
  static const green = Color(0xFF3DD68C);
  static const rose = Color(0xFFF4476B);
  static const blue = Color(0xFF5B9BFF);
  static const violet = Color(0xFF9B7BFF);
  static const ink = Color(0xFFF4F1EA);
  static const mist = Color(0xFF8A92A6);
  static const faint = Color(0xFF5A6275);
}

class ShoppaTheme {
  ShoppaTheme._();

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ShoppaColors.obsidian,
      colorScheme: const ColorScheme.dark(
        primary: ShoppaColors.amber,
        secondary: ShoppaColors.violet,
        surface: ShoppaColors.panel,
        error: ShoppaColors.rose,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          color: ShoppaColors.ink,
        ),
        bodyMedium: TextStyle(color: ShoppaColors.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ShoppaColors.panel2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ShoppaColors.line),
        ),
        labelStyle: const TextStyle(color: ShoppaColors.mist),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ShoppaColors.amber,
          foregroundColor: ShoppaColors.obsidian,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
