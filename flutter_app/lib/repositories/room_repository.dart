import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/player.dart';
import '../models/room.dart';

/// Pure data access for rooms and players. No business logic here.
/// Streams emit incremental updates from Supabase Realtime — no client refetch.
class RoomRepository {
  RoomRepository(this._client);
  final SupabaseClient _client;

  // --- Room lookups -------------------------------------------------------

  Future<Room?> findRoomByCode(String code) async {
    final data = await _client
        .from('rooms')
        .select()
        .eq('code', code.toUpperCase())
        .maybeSingle();
    return data == null ? null : Room.fromJson(data);
  }

  /// One-shot lookup by id. Used by `GameService.nextRound` to read the
  /// host's `modes` selection without subscribing to the realtime stream.
  Future<Room?> findRoomById(String roomId) async {
    final data = await _client
        .from('rooms')
        .select()
        .eq('id', roomId)
        .maybeSingle();
    return data == null ? null : Room.fromJson(data);
  }

  /// Stream of a single room's current state. Supabase pushes incremental
  /// updates — we never refetch on change.
  Stream<Room?> watchRoom(String roomId) {
    return _client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((rows) => rows.isEmpty ? null : Room.fromJson(rows.first));
  }

  Future<Room> createRoom({
    required String code,
    required int? timerSeconds,
    required List<String> modes,
    required String packId,
  }) async {
    final data = await _client
        .from('rooms')
        .insert({
          'code': code,
          'status': 'lobby',
          'timer_seconds': timerSeconds,
          'modes': modes,
          // Persist the pack so the server/client both know which game
          // flow to run. Nullable in the schema but we always stamp it
          // on new rooms — only legacy rows end up with NULL.
          'pack_id': packId,
        })
        .select()
        .single();
    return Room.fromJson(data);
  }

  Future<void> setHost(String roomId, String playerId) async {
    await _client
        .from('rooms')
        .update({'host_player_id': playerId}).eq('id', roomId);
  }

  Future<void> updateRoomStatus(
    String roomId, {
    RoomStatus? status,
    int? currentRound,
  }) async {
    final patch = <String, dynamic>{};
    if (status != null) patch['status'] = statusToString(status);
    if (currentRound != null) patch['current_round'] = currentRound;
    if (patch.isEmpty) return;
    await _client.from('rooms').update(patch).eq('id', roomId);
  }

  // --- Players ------------------------------------------------------------

  /// Ordered stream of players in a room.
  Stream<List<Player>> watchPlayers(String roomId) {
    return _client
        .from('players')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at')
        .map((rows) => rows.map(Player.fromJson).toList());
  }

  /// Looks up a player by its primary-key id.
  ///
  /// Used on rejoin: when the browser has a cached playerId in
  /// SharedPreferences (via SessionService) we verify that player still
  /// exists before reusing it. Identity is per-browser-session, *not* per
  /// name — two different browsers typing the same name must create two
  /// distinct player rows.
  Future<Player?> findPlayerById(String playerId) async {
    final data = await _client
        .from('players')
        .select()
        .eq('id', playerId)
        .maybeSingle();
    return data == null ? null : Player.fromJson(data);
  }

  /// Match a player by (room, name). Intentionally NOT used as the primary
  /// rejoin path — identity is per-browser-session, not per name, so two
  /// different browsers typing the same name correctly become two distinct
  /// player rows. See [findPlayerByRoomAndBrowser] for the browser-fingerprint
  /// rejoin-recovery path.
  ///
  /// Still exposed because the service layer needs it to detect name
  /// collisions (to auto-suffix " (2)") when a brand-new player joins a
  /// room where someone else already picked that name.
  Future<Player?> findPlayerByName({
    required String roomId,
    required String name,
  }) async {
    final data = await _client
        .from('players')
        .select()
        .eq('room_id', roomId)
        .eq('name', name)
        .maybeSingle();
    return data == null ? null : Player.fromJson(data);
  }

  /// Secondary rejoin lookup: when the per-room `playerId:CODE` cache is
  /// missing (different browser-but-same-device edge cases, cleared
  /// storage, Vercel preview ↔ prod origin swap) we still want to
  /// reconnect the user to their existing player row. Matching on both
  /// room AND browser_id keeps this safe against impersonation — a
  /// different browser cannot claim someone else's player just by typing
  /// the same name.
  Future<Player?> findPlayerByRoomAndBrowser({
    required String roomId,
    required String browserId,
  }) async {
    final data = await _client
        .from('players')
        .select()
        .eq('room_id', roomId)
        .eq('browser_id', browserId)
        .maybeSingle();
    return data == null ? null : Player.fromJson(data);
  }

  Future<Player> createPlayer({
    required String roomId,
    required String name,
    bool isHost = false,
    String? browserId,
  }) async {
    final data = await _client
        .from('players')
        .insert({
          'room_id': roomId,
          'name': name,
          'is_host': isHost,
          // Nullable in the schema — omit rather than send null so
          // bot-seeding (no browser) keeps producing a clean row.
          if (browserId != null) 'browser_id': browserId,
        })
        .select()
        .single();
    return Player.fromJson(data);
  }
}

final _rng = Random.secure();

String generateRoomCode() {
  final buffer = StringBuffer();
  for (var i = 0; i < kRoomCodeLength; i++) {
    buffer.write(kRoomCodeChars[_rng.nextInt(kRoomCodeChars.length)]);
  }
  return buffer.toString();
}
