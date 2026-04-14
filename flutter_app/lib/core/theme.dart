import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Exact translations of the web app's CSS HSL tokens.
class AppColors {
  static const background = Color(0xFFFFFBE8); // hsl(45, 100%, 96%)
  static const foreground = Color(0xFF20203D); // hsl(240, 20%, 15%)
  static const card = Colors.white;
  static const primary = Color(0xFFE63E5C); // hsl(350, 80%, 55%)
  static const primaryLight = Color(0xFFF57991); // hsl(350, 90%, 65%)
  static const secondary = Color(0xFF3D8CE6); // hsl(210, 70%, 55%)
  static const accent = Color(0xFF2EB87A); // hsl(160, 60%, 45%)
  static const muted = Color(0xFFEAE5DC); // hsl(40, 30%, 90%)
  static const mutedFg = Color(0xFF696675); // hsl(240, 10%, 45%)
  static const destructive = Color(0xFFEF4444); // hsl(0, 84%, 60%)
  static const winner = Color(0xFFFFC400); // hsl(45, 100%, 50%)
  static const cardShadowTint = Color(0x26E63E5C); // primary @ ~15%
}

/// System color-emoji fonts. Flutter Web otherwise falls back to a
/// monochrome glyph or a tofu box, because Fredoka/Nunito (loaded via
/// google_fonts) don't include emoji coverage. Listing these as fallback
/// means the emoji codepoint gets rendered by whichever of these the
/// browser/OS actually has — Apple devices have Apple Color Emoji,
/// Windows has Segoe UI Emoji, Linux/Chrome has Noto Color Emoji.
const _emojiFallback = <String>[
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Segoe UI Symbol',
  'Noto Color Emoji',
  'Twemoji Mozilla',
  'EmojiOne Color',
];

TextStyle _display(TextStyle base) => GoogleFonts.fredoka(
      textStyle: base.copyWith(fontFamilyFallback: _emojiFallback),
    );
TextStyle _body(TextStyle base) => GoogleFonts.nunito(
      textStyle: base.copyWith(fontFamilyFallback: _emojiFallback),
    );

/// Public helpers — use these instead of calling `GoogleFonts.fredoka/nunito`
/// directly in widgets, so every Text in the app picks up the emoji font
/// fallback chain and renders 🎭 🏆 ✅ as color glyphs instead of tofu.
TextStyle displayFont({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
}) =>
    GoogleFonts.fredoka(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    ).copyWith(fontFamilyFallback: _emojiFallback);

TextStyle bodyFont({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
}) =>
    GoogleFonts.nunito(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    ).copyWith(fontFamilyFallback: _emojiFallback);

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      tertiary: AppColors.accent,
      surface: AppColors.card,
      onSurface: AppColors.foreground,
      error: AppColors.destructive,
    ),
    scaffoldBackgroundColor: AppColors.background,
    textTheme: TextTheme(
      displayLarge: _display(const TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
      )),
      displayMedium: _display(const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
      )),
      headlineMedium: _display(const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
      )),
      titleLarge: _display(const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
      )),
      bodyLarge: _body(const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.foreground)),
      bodyMedium: _body(const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.foreground)),
      bodySmall: _body(const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.mutedFg)),
      labelLarge: _display(const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      )),
    ),
  );

  return base.copyWith(
    cardTheme: const CardThemeData(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      margin: EdgeInsets.zero,
      shadowColor: AppColors.cardShadowTint,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        elevation: 0,
        shadowColor: AppColors.cardShadowTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        textStyle: GoogleFonts.fredoka(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ).copyWith(fontFamilyFallback: _emojiFallback),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.pressed)
              ? Colors.white.withValues(alpha: 0.1)
              : null,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      hintStyle: _body(const TextStyle(color: AppColors.mutedFg)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.muted),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.muted),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.foreground,
      contentTextStyle: _body(
          const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  );
}

/// Palette for player avatars (same as web).
const List<Color> kPlayerColors = [
  Color(0xFFE63E5C), // primary pink
  Color(0xFF3D8CE6), // blue
  Color(0xFF2EB87A), // green
  Color(0xFFFFC400), // yellow
  Color(0xFFA64DD9), // purple
  Color(0xFFF57A1F), // orange
  Color(0xFF26A5C2), // cyan
  Color(0xFFCC3374), // magenta
];

Color playerColor(int index) => kPlayerColors[index % kPlayerColors.length];

/// The "game-gradient" from the web — used in the header.
const LinearGradient kGameGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    AppColors.primary,
    AppColors.primaryLight,
    AppColors.secondary,
  ],
  stops: [0.0, 0.5, 1.0],
);

/// Soft shadow matching `card-shadow` utility.
const List<BoxShadow> kCardShadow = [
  BoxShadow(
    color: AppColors.cardShadowTint,
    blurRadius: 20,
    offset: Offset(0, 4),
    spreadRadius: -4,
  ),
  BoxShadow(
    color: Color(0x14000000),
    blurRadius: 8,
    offset: Offset(0, 2),
    spreadRadius: -2,
  ),
];

/// Winner glow — warm amber halo.
const List<BoxShadow> kWinnerGlow = [
  BoxShadow(
    color: Color(0x80FFC400),
    blurRadius: 30,
  ),
  BoxShadow(
    color: Color(0x33FFC400),
    blurRadius: 60,
  ),
];
