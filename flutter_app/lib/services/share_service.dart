import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

/// Builds the shareable room URL + triggers the native share sheet.
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
      // On web we always have a usable origin.
      final origin = Uri.base.origin;
      return origin;
    }
    // Last-resort fallback for native builds that forgot to set APP_URL.
    return 'https://vota-amici.vercel.app';
  }

  /// Public helper so tests / UI can preview the link.
  Uri roomUrl(String code) =>
      Uri.parse('$_baseUrl/room/${code.toUpperCase()}');

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

  /// Copies the URL to the clipboard. Used as a fallback button alongside the
  /// share sheet so desktop / keyboard users have a discoverable option.
  Future<void> copyLink(String code) async {
    await Clipboard.setData(ClipboardData(text: roomUrl(code).toString()));
  }
}
