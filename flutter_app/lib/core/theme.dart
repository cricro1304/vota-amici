import 'package:flutter/material.dart';

/// App theme — mirrors the web Tailwind palette (primary, card, muted, etc).
/// Colors are approximate translations of the web's HSL tokens.
ThemeData buildAppTheme() {
  const primary = Color(0xFFFF4D7E); // playful pink
  const background = Color(0xFFFFF8F1);
  const card = Colors.white;
  const foreground = Color(0xFF1F1B2E);
  const muted = Color(0xFF8A8698);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: Color(0xFF7A5CFF),
      surface: card,
      onSurface: foreground,
      error: Color(0xFFE53E3E),
    ),
    scaffoldBackgroundColor: background,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w800, color: foreground),
      displayMedium: TextStyle(fontWeight: FontWeight.w800, color: foreground),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: foreground),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: foreground),
      bodyLarge: TextStyle(color: foreground),
      bodyMedium: TextStyle(color: foreground),
      bodySmall: TextStyle(color: muted),
    ),
  );

  return base.copyWith(
    cardTheme: const CardThemeData(
      elevation: 0,
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
    ),
  );
}

/// Palette for player avatars (mirrors web PLAYER_COLORS).
const List<Color> kPlayerColors = [
  Color(0xFFE63E5C),
  Color(0xFF3E8FE6),
  Color(0xFF2FB48A),
  Color(0xFFFFC107),
  Color(0xFF9B59B6),
  Color(0xFFF39C12),
  Color(0xFF22A6B3),
  Color(0xFFC2185B),
];

Color playerColor(int index) => kPlayerColors[index % kPlayerColors.length];
