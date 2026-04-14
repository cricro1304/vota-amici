import 'package:shared_preferences/shared_preferences.dart';

/// Persistent per-room playerId mapping. Mirrors the web's
/// `localStorage.setItem('playerId:CODE', id)` pattern.
class SessionService {
  SessionService(this._prefs);
  final SharedPreferences _prefs;

  String _key(String roomCode) => 'playerId:${roomCode.toUpperCase()}';

  String? getPlayerId(String roomCode) => _prefs.getString(_key(roomCode));

  Future<void> setPlayerId(String roomCode, String playerId) async {
    await _prefs.setString(_key(roomCode), playerId);
  }

  Future<void> clearPlayerId(String roomCode) async {
    await _prefs.remove(_key(roomCode));
  }
}
