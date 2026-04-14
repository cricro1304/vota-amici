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
  }) async {
    final data = await _client
        .from('rooms')
        .insert({
          'code': code,
          'status': 'lobby',
          'timer_seconds': timerSeconds,
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

  Future<Player> createPlayer({
    required String roomId,
    required String name,
    bool isHost = false,
  }) async {
    final data = await _client
        .from('players')
        .insert({
          'room_id': roomId,
          'name': name,
          'is_host': isHost,
        })
        .select()
        .single();
    return Player.fromJson(data);
  }
}

String generateRoomCode() {
  final chars = kRoomCodeChars;
  final rnd = DateTime.now().microsecondsSinceEpoch;
  final buffer = StringBuffer();
  var seed = rnd;
  for (var i = 0; i < kRoomCodeLength; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    buffer.write(chars[seed % chars.length]);
  }
  return buffer.toString();
}
