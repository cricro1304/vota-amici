import 'package:flutter/material.dart';

/// Apple-style-ish emoji rendering that is *consistent across every device*.
///
/// The marketing landing (`landing-page.html`) just uses system emoji, which
/// on the author's Mac renders as Apple Color Emoji. Flutter Web with the
/// CanvasKit renderer doesn't fall back to the OS emoji font, so on the same
/// Mac the flutter app showed monochrome/tofu glyphs. To get parity we ship
/// Twemoji (open-source, SVG-based, Apple-inspired) via jsdelivr's CDN and
/// swap every emoji codepoint in a Text for a small Image.network.
///
/// Usage:
///   EmojiText('Chi è il più pigro? 😴', style: displayFont(...))
///
/// Or inline in a RichText:
///   Text.rich(TextSpan(children: buildEmojiSpans('🎉 Chi è il più...?', ...)))
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

  /// Rendered height of each emoji. Defaults to `style.fontSize * 1.15` so
  /// an emoji in a 20-px run ends up ~23 px tall — matching how system
  /// emoji tend to overhang their text box.
  final double? emojiSize;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final size = emojiSize ?? (baseStyle.fontSize ?? 14) * 1.15;
    return Text.rich(
      TextSpan(
        children: buildEmojiSpans(text, baseStyle, emojiSize: size),
      ),
      textAlign: textAlign,
    );
  }
}

/// Public helper — splits [text] into text spans and WidgetSpans for each
/// emoji run. The emoji image uses Twemoji's 72x72 PNG for crispness on
/// hi-DPI screens.
List<InlineSpan> buildEmojiSpans(
  String text,
  TextStyle baseStyle, {
  required double emojiSize,
}) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  final runes = text.runes.toList();
  var i = 0;

  void flushText() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: baseStyle));
    buffer.clear();
  }

  while (i < runes.length) {
    final r = runes[i];
    if (_isEmojiStart(r)) {
      // Collect a full emoji run: base + variation selectors + ZWJ sequences.
      final group = <int>[r];
      var j = i + 1;
      while (j < runes.length) {
        final n = runes[j];
        if (n == _zwj && j + 1 < runes.length && _isEmojiBase(runes[j + 1])) {
          group.add(n);
          group.add(runes[j + 1]);
          j += 2;
          continue;
        }
        if (n == _vs16 || n == _vs15 || _isSkinTone(n) || _isKeycap(n)) {
          group.add(n);
          j += 1;
          continue;
        }
        // Regional indicator pair (flags): two RI codepoints in a row.
        if (_isRegionalIndicator(r) &&
            _isRegionalIndicator(n) &&
            group.length == 1) {
          group.add(n);
          j += 1;
          continue;
        }
        break;
      }

      flushText();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _TwemojiImage(
            codepoints: group,
            size: emojiSize,
            fallback: String.fromCharCodes(group),
            fallbackStyle: baseStyle,
          ),
        ),
      );
      i = j;
    } else {
      buffer.writeCharCode(r);
      i += 1;
    }
  }
  flushText();
  return spans;
}

// --- emoji codepoint classification -----------------------------------------

const int _zwj = 0x200D;
const int _vs15 = 0xFE0E; // text-style variation selector
const int _vs16 = 0xFE0F; // emoji-style variation selector

bool _isSkinTone(int r) => r >= 0x1F3FB && r <= 0x1F3FF;
bool _isKeycap(int r) => r == 0x20E3;
bool _isRegionalIndicator(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;

bool _isEmojiBase(int r) =>
    (r >= 0x1F300 && r <= 0x1FAFF) ||
    (r >= 0x2600 && r <= 0x27BF) ||
    (r >= 0x2300 && r <= 0x23FF) ||
    (r >= 0x2B00 && r <= 0x2BFF) ||
    (r >= 0x2190 && r <= 0x21FF) ||
    (r >= 0x25A0 && r <= 0x25FF) ||
    _isRegionalIndicator(r) ||
    _isSkinTone(r) ||
    r == 0x203C || r == 0x2049 ||
    r == 0x2122 || r == 0x2139 ||
    r == 0x3030 || r == 0x303D ||
    r == 0x3297 || r == 0x3299 ||
    // Keycap digits need to be treated as emoji only when followed by the
    // combining enclosing keycap — the caller handles that via _isKeycap.
    (r >= 0x0030 && r <= 0x0039) ||
    r == 0x0023 || r == 0x002A;

/// A slightly stricter test than [_isEmojiBase]: only codepoints that are
/// safe to *start* an emoji run (i.e. we don't want to grab every literal
/// digit '5' or '#' unless it's followed by a keycap marker).
bool _isEmojiStart(int r) {
  if (_isEmojiBase(r) && (r < 0x0030 || r > 0x0039) && r != 0x0023 && r != 0x002A) {
    return true;
  }
  // Keycap sequences always look like: digit/# + VS16 + 0x20E3.
  // We detect them with a 3-char lookahead in the main loop instead, to
  // keep this function O(1).
  return false;
}

// --- Twemoji CDN image ------------------------------------------------------

class _TwemojiImage extends StatelessWidget {
  const _TwemojiImage({
    required this.codepoints,
    required this.size,
    required this.fallback,
    required this.fallbackStyle,
  });

  final List<int> codepoints;
  final double size;
  final String fallback;
  final TextStyle fallbackStyle;

  /// Twemoji's filename convention: each codepoint in lowercase hex, joined
  /// by dashes, variation selector `FE0F` omitted (unless the sequence is
  /// JUST `something + FE0F`, in which case it's kept — but jdecked/twemoji's
  /// assets follow the strip-FE0F rule uniformly, so we always strip).
  String get _slug {
    final parts = <String>[];
    for (final cp in codepoints) {
      if (cp == _vs16) continue;
      parts.add(cp.toRadixString(16));
    }
    return parts.join('-');
  }

  @override
  Widget build(BuildContext context) {
    // iamcal/emoji-data — the Apple PNG sprite set Slack/Discord/etc. have
    // used for years. Same slug convention as Twemoji (lowercase hex, dashed,
    // FE0F stripped), just a different path. Legally grey: Apple owns the
    // artwork. Fine for local testing; revisit before shipping publicly.
    final url =
        'https://cdn.jsdelivr.net/gh/iamcal/emoji-data@master/img-apple-64/$_slug.png';
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            Text(fallback, style: fallbackStyle.copyWith(fontSize: size)),
      ),
    );
  }
}
