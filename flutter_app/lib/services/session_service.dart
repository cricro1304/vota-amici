import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent per-room playerId mapping. Mirrors the web's
/// `localStorage.setItem('playerId:CODE', id)` pattern.
///
/// Also owns a per-browser persistent id used as a *secondary* rejoin
/// signal. When the per-room playerId cache is missing (different
/// browser/incognito, cleared storage, Vercel preview ↔ prod domain swap,
/// etc.) the browser id lets GameService.joinRoom still recover the
/// existing player instead of silently creating a duplicate row.
class SessionService {
  SessionService(this._prefs);
  final SharedPreferences _prefs;

  /// Key used to cache a per-room playerId.
  String _key(String roomCode) => 'playerId:${roomCode.toUpperCase()}';

  /// Key for the browser-wide persistent fingerprint. NOT scoped to a room
  /// on purpose — it should survive across rooms, and it's what we match
  /// against a player row's `browser_id` column on rejoin.
  static const _browserIdKey = 'browserId';

  String? getPlayerId(String roomCode) => _prefs.getString(_key(roomCode));

  Future<void> setPlayerId(String roomCode, String playerId) async {
    await _prefs.setString(_key(roomCode), playerId);
  }

  Future<void> clearPlayerId(String roomCode) async {
    await _prefs.remove(_key(roomCode));
  }

  /// Returns this browser's stable id, creating one on first call.
  ///
  /// The id is purely a local fingerprint — not a security token. Its sole
  /// purpose is to disambiguate a rejoin from a fresh join when the
  /// per-room `playerId:CODE` cache is missing. If the user clears ALL
  /// localStorage (or switches browsers) they'll get a new id and the
  /// rejoin-by-name path will correctly treat them as a new player.
  String browserId() {
    final existing = _prefs.getString(_browserIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = _generateBrowserId();
    // Fire-and-forget: we want the id available synchronously, and the
    // prefs write completes on the next microtask. Worst case on a crash
    // before the write lands, we generate a new id next boot — which just
    // looks like a fresh browser, which is the correct fallback anyway.
    _prefs.setString(_browserIdKey, fresh);
    return fresh;
  }

  /// 128 bits of entropy, hex-encoded. Collisions across browsers are
  /// astronomically unlikely, which is enough for "is this the same
  /// browser that created the player row?".
  static String _generateBrowserId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
