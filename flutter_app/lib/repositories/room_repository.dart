import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// Stream of a single room's current state. Combines three sources:
  ///
  ///   1. **REST primer** (one-shot): an explicit fetch BEFORE realtime
  ///      connects. Authoritative full row — fixes the early-subscription
  ///      window where the realtime payload could omit `pack_id` (see
  ///      pack_id carry-over below) and bricks the couples theme on the
  ///      joiner.
  ///
  ///   2. **Realtime deltas** (continuous): Supabase pushes incremental
  ///      updates — we never refetch on change in the happy path.
  ///
  ///   3. **REST watchdog** (every [_watchdogPeriod]): polls the room
  ///      row and emits *only* when something meaningful changed
  ///      (`status`, `current_round`, `timer_seconds`). This catches the
  ///      "everyone progressed but one user stayed in the lobby" failure
  ///      mode where the realtime channel silently stalls — no error,
  ///      no emission, and the affected client sees `lobby` forever
  ///      while the host has flipped to `in_round`. Equality-gated so
  ///      it adds zero churn during normal operation; this is invisible
  ///      to the user and to the rest of the app.
  ///
  /// Pack-id carry-over: realtime replication events can occasionally
  /// deliver a row whose payload doesn't include `pack_id` (most
  /// reproducible right after the column was added, before Realtime's
  /// schema cache refreshes; also seen intermittently on a joiner's
  /// first subscription). When that happens, `Pack.byDbId(null)` falls
  /// back to classic and the joiner sees the plain theme while the host
  /// correctly renders couples. We cache the first non-null `pack_id`
  /// we ever see and re-stamp it on any later payload that lost it.
  /// The pack of a room never changes over its lifetime, so downgrading
  /// non-null → null is always wrong.
  static const Duration _watchdogPeriod = Duration(seconds: 8);

  /// Pure: reapplies a previously-seen pack_id to a row whose payload
  /// dropped it. Realtime occasionally delivers a row with `pack_id`
  /// missing — most reproducibly right after the column was added,
  /// before Realtime's schema cache refreshes, but also seen on a
  /// joiner's first subscription. `Pack.byDbId(null)` falls back to
  /// classic in that case, which would flicker the joiner's couples
  /// theme back to plain mid-game. The pack of a room never changes
  /// over its lifetime, so re-stamping the cached value is always safe.
  ///
  /// Returns the original [row] when [cachedPackId] is null, when [row]
  /// already has a non-null `packId`, or when both are null. Public for
  /// unit testing — see `room_repository_watchdog_test.dart`.
  @visibleForTesting
  static Room reapplyPackId(Room row, String? cachedPackId) {
    if (row.packId != null) return row;
    if (cachedPackId == null) return row;
    return Room(
      id: row.id,
      code: row.code,
      hostPlayerId: row.hostPlayerId,
      status: row.status,
      currentRound: row.currentRound,
      timerSeconds: row.timerSeconds,
      modes: row.modes,
      packId: cachedPackId,
      createdAt: row.createdAt,
    );
  }

  /// Pure: returns true when [next] has a state-affecting difference
  /// vs. [prev], i.e. the watchdog SHOULD push it onto the stream.
  ///
  /// Deliberately ignores fields that screens don't read (createdAt,
  /// modes list identity, code) so a watchdog poll during normal
  /// operation stays a silent no-op — the realtime stream emits the
  /// same authoritative row every time the host writes, and we don't
  /// want both sources to fire a UI rebuild for the same logical
  /// state.
  ///
  /// Public for unit testing — see `room_repository_watchdog_test.dart`.
  @visibleForTesting
  static bool roomStateDiffers(Room? prev, Room? next) {
    if (identical(prev, next)) return false;
    if (prev == null || next == null) return true;
    if (prev.id != next.id) return true;
    if (prev.status != next.status) return true;
    if (prev.currentRound != next.currentRound) return true;
    if (prev.timerSeconds != next.timerSeconds) return true;
    if (prev.hostPlayerId != next.hostPlayerId) return true;
    // pack_id changes are pinned by `reapplyPackId` and shouldn't be
    // a separate trigger — but if both sides genuinely disagree
    // (legacy NULL → real id), we want the fresher value.
    if ((prev.packId ?? '') != (next.packId ?? '')) return true;
    return false;
  }

  Stream<Room?> watchRoom(String roomId) {
    String? cachedPackId;
    Room? lastEmitted;
    StreamSubscription<List<Map<String, dynamic>>>? rtSub;
    Timer? watchdog;
    // Set in `onCancel`. Read after every `await` in `start()` so a
    // screen exit that happens while the REST primer is in flight
    // doesn't leak a Timer.periodic that keeps polling forever.
    var cancelled = false;
    late final StreamController<Room?> controller;

    void emit(Room? room) {
      if (controller.isClosed) return;
      final Room? out;
      if (room == null) {
        out = null;
      } else {
        out = reapplyPackId(room, cachedPackId);
        if (out.packId != null) cachedPackId = out.packId;
      }
      lastEmitted = out;
      controller.add(out);
    }

    Future<void> start() async {
      // 1. REST primer. A single round-trip, cheap, and gives us the
      //    authoritative row before realtime even connects.
      try {
        final initial = await findRoomById(roomId);
        if (cancelled) return;
        if (initial != null) emit(initial);
      } catch (_) {
        // Non-fatal — the realtime stream / watchdog below will supply
        // the row.
      }
      if (cancelled) return;

      // 2. Realtime deltas. The pack_id carry-over (`emit` →
      //    `reapplyPackId`) protects against late UPDATEs that happen
      //    to omit pack_id flickering the joiner back to classic.
      rtSub = _client
          .from('rooms')
          .stream(primaryKey: ['id'])
          .eq('id', roomId)
          .listen(
            (rows) {
              // `cancelled` covers the window between onCancel running
              // and `rtSub.cancel()` taking effect — events delivered
              // there must not be added to a controller we're tearing
              // down. `isClosed` covers the post-close window after
              // onCancel finishes.
              if (cancelled || controller.isClosed) return;
              if (rows.isEmpty) {
                emit(null);
                return;
              }
              emit(Room.fromJson(rows.first));
            },
            // Errors on the realtime channel must not poison the merged
            // stream — the watchdog below is exactly the recovery path
            // for "channel broken, but the room is still progressing
            // server-side". Swallow so the StreamController keeps
            // accepting watchdog emissions.
            onError: (_) {},
          );
      if (cancelled) {
        await rtSub?.cancel();
        rtSub = null;
        return;
      }

      // 3. Watchdog. Re-fetch the room periodically and emit ONLY when
      //    a state-affecting field changed. This is the fix for "the
      //    game started for everyone but a user": when the realtime
      //    delta is silently dropped on one client, the host's flip
      //    from `lobby` → `in_round` lands here on the next tick and
      //    pushes the affected screen forward without any user action.
      watchdog = Timer.periodic(_watchdogPeriod, (_) async {
        if (cancelled || controller.isClosed) return;
        try {
          final fresh = await findRoomById(roomId);
          if (cancelled || controller.isClosed) return;
          if (fresh == null) {
            if (lastEmitted != null) emit(null);
            return;
          }
          if (roomStateDiffers(lastEmitted, fresh)) {
            emit(fresh);
          }
        } catch (_) {
          // Transient network blip — try again next tick.
        }
      });
      if (cancelled) {
        watchdog?.cancel();
        watchdog = null;
      }
    }

    controller = StreamController<Room?>(
      onListen: start,
      onCancel: () async {
        cancelled = true;
        watchdog?.cancel();
        watchdog = null;
        // Snapshot then null to avoid double-cancel if onCancel is
        // somehow re-entered (defensive — Dart doesn't normally do
        // that, but cheap insurance).
        final sub = rtSub;
        rtSub = null;
        await sub?.cancel();
        // Close the controller so any in-flight `emit()` short-circuits
        // via `isClosed`. Without close(), a single-subscription
        // controller silently buffers post-cancel events forever — they
        // hold references to Room objects and pin the closure in
        // memory until the entire RoomRepository is GC'd, which never
        // happens (it's a singleton in GetIt).
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );

    return controller.stream;
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
  ///
  /// Why `order + limit(1)` instead of `maybeSingle()`: the live DB has
  /// a partial UNIQUE index on (room_id, browser_id), but if a future
  /// schema change removed it (or a glitch produced two rows
  /// historically) `maybeSingle()` THROWS on more than one row, which
  /// would brick rejoin recovery for that browser forever — the user
  /// would be stuck creating yet another "(N)" suffixed row on every
  /// retry. Picking the oldest row deterministically reconnects them
  /// to their *original* player so votes/host status stay intact.
  Future<Player?> findPlayerByRoomAndBrowser({
    required String roomId,
    required String browserId,
  }) async {
    final rows = await _client
        .from('players')
        .select()
        .eq('room_id', roomId)
        .eq('browser_id', browserId)
        .order('created_at')
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return Player.fromJson(list.first as Map<String, dynamic>);
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
