import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const green = Color(0xFF2ECC71);
  static const greenDim = Color(0xFF1a7a44);
  static const greenGlow = Color(0x262ECC71);
  static const gold = Color(0xFFF0A500);
  static const bg = Color(0xFF060d09);
  static const surface = Color(0xFF0d1a11);
  static const glass = Color(0x0AFFFFFF);
  static const glass2 = Color(0x12FFFFFF);
  static const border = Color(0x2E2ECC71);
  static const border2 = Color(0x14FFFFFF);
  static const textPrimary = Color(0xFFE8F0EA);
  static const textSecondary = Color(0xFF8AAB90);
  static const textMuted = Color(0xFF4D6B52);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    primaryColor: green,
    colorScheme: const ColorScheme.dark(
      primary: green,
      secondary: greenDim,
      surface: surface,
      onPrimary: Colors.black,
      onSurface: textPrimary,
    ),
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: textSecondary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: greenGlow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: green, fontSize: 11, fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: textSecondary, fontSize: 11);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: green, size: 22);
        }
        return const IconThemeData(color: textSecondary, size: 22);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glass,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: green),
      ),
      labelStyle: const TextStyle(color: textSecondary),
      hintStyle: const TextStyle(color: textMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: glass,
      selectedColor: greenGlow,
      labelStyle: const TextStyle(color: textPrimary, fontSize: 12),
      side: const BorderSide(color: border2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: const DividerThemeData(color: border2, thickness: 1),
  );
}
