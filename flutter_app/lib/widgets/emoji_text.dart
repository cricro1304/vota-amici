import 'package:flutter/material.dart';

/// Thin shim around [Text] kept only to avoid a callsite-wide rename across
/// the screen widgets that already import `EmojiText`.
///
/// Originally this widget intercepted every emoji codepoint in [text] and
/// replaced it with an `Image.network` pointing at a Noto Color Emoji PNG
/// served by `cdn.jsdelivr.net`. That workaround was needed when the
/// Flutter web build used the **CanvasKit renderer**, which ships its own
/// Skia-based text engine and cannot see OS-installed emoji fonts —
/// without the PNG swap, every emoji rendered as a monochrome tofu box on
/// macOS / iOS / Windows.
///
/// The web build now forces the **HTML renderer** (see
/// `flutter_app/web/index.html`'s `initializeEngine({ renderer: "html" })`).
/// Under HTML rendering Flutter draws text via the DOM, and the browser's
/// emoji-font fallback works naturally — meaning each platform shows its
/// own emoji set:
///
///   - macOS / iOS  → Apple Color Emoji
///   - Windows      → Segoe UI Emoji
///   - Android      → Noto Color Emoji
///   - Linux        → Noto / distro choice
///
/// The `_emojiFallback` list in `lib/core/theme.dart` is wired into every
/// TextStyle via `fontFamilyFallback`, so the right font is consulted on
/// each platform with no per-widget setup. Native iOS/Android builds were
/// always fine — Flutter has system access to the platform's emoji font
/// directly.
///
/// Removing the CDN-PNG path:
///   - Drops a per-emoji round-trip to `cdn.jsdelivr.net` on first paint
///     (some screens fired ~10–20 fetches before becoming interactive).
///   - Restores Apple-style emoji on macOS/iOS instead of forced Noto.
///   - Eliminates the runtime `cdn.jsdelivr.net` dependency and its
///     blocked-CDN failure mode.
///
/// The widget API is preserved (`text`, `style`, `textAlign`, `emojiSize`)
/// so the existing ~70 callsites compile without edits. `emojiSize` is
/// retained for source compat only — its value is ignored because OS
/// emoji glyphs size with the surrounding text run, not as a separately
/// sized box. To make an emoji bigger, set `fontSize` on `style`, which
/// every callsite that cared was already doing.
///
/// Usage (unchanged):
///   EmojiText('Chi è il più pigro? 😴', style: displayFont(...))
///   EmojiText('🎲', style: TextStyle(fontSize: 32))
///
/// This file can eventually be deleted by replacing every `EmojiText(` /
/// `import '../widgets/emoji_text.dart';` with `Text(` and removing the
/// import — the shim exists purely to keep the diff for the perf fix
/// surgical. Doing the rename later is ~70 mechanical edits with no
/// behavior change.
class EmojiText extends StatelessWidget {
  const EmojiText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.emojiSize,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Retained for source-compat with existing callsites; the value is
  /// ignored because OS-rendered emoji glyphs size with the surrounding
  /// text run automatically. Set `fontSize` on [style] instead.
  final double? emojiSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      textAlign: textAlign,
    );
  }
}
