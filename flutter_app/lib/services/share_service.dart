import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

/// Builds shareable URLs + triggers the native share sheet.
///
/// The share sheet is the same API that powers AirDrop on iOS, the OS share
/// target on Android, and the Web Share API on mobile browsers — so one call
/// covers "share link" and "AirDrop" simultaneously.
class ShareService {
  const ShareService();

  /// Base URL of the deployed web app. Falls back to the current origin on
  /// Flutter Web, and to a sensible default on mobile builds without env.
  String get _baseUrl {
    final fromEnv = dotenv.env['APP_URL']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv.endsWith('/')
          ? fromEnv.substring(0, fromEnv.length - 1)
          : fromEnv;
    }
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return origin;
    }
    return 'https://vota-amici.vercel.app';
  }

  /// Public helper so tests / UI can preview the link.
  Uri roomUrl(String code) =>
      Uri.parse('$_baseUrl/room/${code.toUpperCase()}');

  Uri siteUrl() => Uri.parse(_baseUrl);

  /// Opens the native share sheet with the invite link.
  ///
  /// We share ONLY the bare URL (no prose, no code prefix) so that iOS
  /// AirDrop recognises it as a link and offers "Open in Safari" straight
  /// away on the receiving device. When the share payload is a multi-line
  /// text with extra words around the URL, AirDrop treats it as a .txt
  /// drop and saves it to Notes instead — which is what we want to avoid.
  ///
  /// Callers should pass the widget's `RenderBox` origin on iPad (via
  /// [sharePositionOrigin]) so the popover has an anchor.
  Future<void> shareRoom({
    required String code,
    Rect? sharePositionOrigin,
  }) async {
    final url = roomUrl(code).toString();
    await Share.share(
      url,
      subject: 'Partita "Chi è il più...?"',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Copies the invite URL to the clipboard. Used as a fallback button
  /// alongside the share sheet so desktop / keyboard users have a
  /// discoverable option.
  Future<void> copyLink(String code) async {
    await Clipboard.setData(ClipboardData(text: roomUrl(code).toString()));
  }

  /// Captures a widget subtree (wrapped in a [RepaintBoundary] with [key])
  /// as a PNG, then hands it to the native share sheet alongside a caption.
  ///
  /// Works on mobile (iOS/Android) + on web where Web Share Level 2 with
  /// files is supported (iOS Safari 15+, Android Chrome). Browsers that
  /// don't support file sharing fall through to the `text + url` payload
  /// via share_plus.
  ///
  /// [caption] is the message users see in the share sheet pre-populated —
  /// e.g. the fun result line. We always append [siteUrl] so the recipient
  /// has a one-tap way to come try the game.
  Future<void> sharePng({
    required GlobalKey boundaryKey,
    required String caption,
    String filename = 'vota-amici.png',
    Rect? sharePositionOrigin,
    double pixelRatio = 3.0,
  }) async {
    final bytes = await capturePng(boundaryKey, pixelRatio: pixelRatio);
    if (bytes == null) {
      // Capture failed — still give the user something useful by sharing
      // the caption + link instead of silently no-oping.
      await Share.share(
        '$caption\n${siteUrl()}',
        sharePositionOrigin: sharePositionOrigin,
      );
      return;
    }

    // share_plus 10.x API — the 11.x `SharePlus.instance.share(ShareParams)`
    // API does NOT exist in this version, so stick with `Share.shareXFiles`.
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          name: filename,
          mimeType: 'image/png',
        ),
      ],
      text: '$caption\n${siteUrl()}',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Rasterises the subtree attached to [boundaryKey] into PNG bytes.
  /// Returns `null` if the boundary isn't in the tree yet or the encode
  /// fails — callers should handle that gracefully (see [sharePng]).
  static Future<Uint8List?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    try {
      final ctx = boundaryKey.currentContext;
      if (ctx == null) return null;
      final obj = ctx.findRenderObject();
      if (obj is! RenderRepaintBoundary) return null;
      // On some platforms the boundary may need "needs paint" to flush.
      // Trying the capture and falling back to a delayed retry is the
      // safest thing we can do without depending on private APIs.
      ui.Image image;
      try {
        image = await obj.toImage(pixelRatio: pixelRatio);
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        image = await obj.toImage(pixelRatio: pixelRatio);
      }
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
