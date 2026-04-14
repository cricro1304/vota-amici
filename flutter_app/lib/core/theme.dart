import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Exact translations of the landing's CSS tokens
/// (see `public/assets/css/shared.css` — these MUST stay in sync 1:1).
class AppColors {
  static const background = Color(0xFFFFF8ED); // --bg
  static const foreground = Color(0xFF2B2640); // --text
  static const card = Color(0xFFFFFFFF); // --bg-card
  // --pink
  static const primary = Color(0xFFE6366E);
  static const primaryLight = Color(0xFFF06292); // mid-stop in nav/header gradient
  static const primaryTint = Color(0xFFF9D1DC); // --pink-light
  // --cyan
  static const secondary = Color(0xFF3BA3D0);
  static const secondaryLight = Color(0xFFC4E8F7); // --cyan-light
  // --teal
  static const accent = Color(0xFF2DB88A);
  static const yellow = Color(0xFFF5C518); // --yellow
  static const purple = Color(0xFF9B59B6); // --purple
  static const orange = Color(0xFFF0883E); // --orange
  static const muted = Color(0xFFEEE8DD); // bg-adjacent chip bg
  static const mutedFg = Color(0xFF8A8494); // --text-muted
  static const destructive = Color(0xFFEF4444);
  static const winner = Color(0xFFF5C518); // --yellow (used for winner rings)
  // --pink-glow: rgba(230, 54, 110, 0.25) → 0x40 alpha
  static const pinkGlow = Color(0x40E6366E);
  // --shadow first layer: rgba(230, 54, 110, 0.15) → 0x26 alpha
  static const cardShadowTint = Color(0x26E6366E);
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

/// Player-avatar palette — mirrors the landing's `--pink / --cyan / --teal /
/// --yellow / --purple / --orange` tokens so a "Marco" avatar looks identical
/// on the marketing page and inside the app.
const List<Color> kPlayerColors = [
  AppColors.primary, // --pink
  AppColors.secondary, // --cyan
  AppColors.accent, // --teal
  AppColors.yellow, // --yellow
  AppColors.purple, // --purple
  AppColors.orange, // --orange
  Color(0xFF26A5C2), // extra cyan (8+ player fallback)
  Color(0xFFCC3374), // extra magenta
];

Color playerColor(int index) => kPlayerColors[index % kPlayerColors.length];

/// The nav / header gradient from the landing:
/// `linear-gradient(135deg, var(--pink) 0%, #f06292 50%, var(--cyan) 100%)`.
const LinearGradient kGameGradient = LinearGradient(
  // 135deg in CSS = diagonal top-left → bottom-right.
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    AppColors.primary, // --pink
    AppColors.primaryLight, // #f06292
    AppColors.secondary, // --cyan
  ],
  stops: [0.0, 0.5, 1.0],
);

/// Winner ring gradient (landing `.result-winner-ring`):
/// `linear-gradient(135deg, var(--yellow), var(--orange))`.
const LinearGradient kWinnerRingGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.yellow, AppColors.orange],
);

/// Footer gradient: `linear-gradient(135deg, #f9d1dc 0%, #e8c4d4 100%)`.
const LinearGradient kFooterGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF9D1DC), Color(0xFFE8C4D4)],
);

/// Shared `--shadow` token from the landing:
/// `0 4px 20px -4px rgba(230,54,110,0.15), 0 2px 8px -2px rgba(0,0,0,0.08)`.
const List<BoxShadow> kCardShadow = [
  BoxShadow(
    color: AppColors.cardShadowTint, // pink @ 0.15
    blurRadius: 20,
    offset: Offset(0, 4),
    spreadRadius: -4,
  ),
  BoxShadow(
    color: Color(0x14000000), // black @ 0.08
    blurRadius: 8,
    offset: Offset(0, 2),
    spreadRadius: -2,
  ),
];

/// Winner halo mirroring the `winnerPulse` box-shadow on the landing:
/// `box-shadow: 0 0 30px rgba(245, 197, 24, 0.4)`.
const List<BoxShadow> kWinnerGlow = [
  BoxShadow(
    color: Color(0x66F5C518), // yellow @ 0.4
    blurRadius: 30,
  ),
  BoxShadow(
    color: Color(0x33F5C518),
    blurRadius: 60,
  ),
];

/// Pink CTA glow: `box-shadow: 0 3px 12px rgba(230,54,110,0.25)`.
const List<BoxShadow> kPinkGlow = [
  BoxShadow(
    color: AppColors.pinkGlow,
    blurRadius: 12,
    offset: Offset(0, 3),
  ),
];
