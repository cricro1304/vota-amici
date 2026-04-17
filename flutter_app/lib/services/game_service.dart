import 'dart:math';

import '../core/constants.dart';
import '../models/player.dart';
import '../models/question.dart';
import '../models/room.dart';
import '../models/round.dart';
import '../repositories/game_repository.dart';
import '../repositories/room_repository.dart';

/// All business logic sits here. Screens never touch repositories directly.
/// This mirrors the web's `gameActions.ts` but with a question cache and
/// cleaner separation of concerns.
class GameService {
  GameService({
    required this.roomRepository,
    required this.gameRepository,
  });

  final RoomRepository roomRepository;
  final GameRepository gameRepository;

  /// Cache questions once per app session — avoids round-by-round refetches.
  List<Question>? _questionCache;
  final _random = Random();

  Future<List<Question>> _questions() async {
    return _questionCache ??=
        await gameRepository.fetchQuestionsForPack(kDefaultQuestionPackId);
  }

  // --- Room lifecycle -----------------------------------------------------

  Future<({Room room, Player player})> createRoom({
    required String hostName,
    required int? timerSeconds,
    List<QuestionMode> modes = const [
      QuestionMode.light,
      QuestionMode.neutro,
      QuestionMode.spicy,
    ],
    String? browserId,
  }) async {
    // Defensive: an empty mode list would mean "no questions ever" — fall
    // back to the full set so the host doesn't accidentally brick the room.
    final selected = modes.isEmpty
        ? const [QuestionMode.light, QuestionMode.neutro, QuestionMode.spicy]
        : modes;
    final code = generateRoomCode();
    final room = await roomRepository.createRoom(
      code: code,
      timerSeconds: timerSeconds,
      modes: selected.map(questionModeToString).toList(growable: false),
    );
    // New room ⇒ no existing players ⇒ no name-collision / browser-recovery
    // to worry about; just stamp the browser id so a later rejoin from this
    // same browser can reconnect without relying solely on the per-room
    // SharedPreferences cache.
    final player = await roomRepository.createPlayer(
      roomId: room.id,
      name: hostName.trim(),
      isHost: true,
      browserId: browserId,
    );
    await roomRepository.setHost(room.id, player.id);
    return (room: room, player: player);
  }

  /// Returns the subset of cached questions matching the room's selected
  /// modes. Falls back to the full set if `modes` is empty (legacy rooms).
  List<Question> _questionsForRoom(List<Question> all, List<String> modes) {
    if (modes.isEmpty) return all;
    final allowed = modes.toSet();
    final filtered = all.where((q) {
      return allowed.contains(questionModeToString(q.mode));
    }).toList(growable: false);
    // If the host selected a mode that has no seeded questions yet (Spicy
    // before authoring), don't end up with an empty pool.
    return filtered.isEmpty ? all : filtered;
  }

  /// Joins [roomCode] as [playerName].
  ///
  /// Rejoin priority — we try these in order and stop at the first match:
  ///
  ///   1. **Cached playerId**: If [existingPlayerId] is supplied (typically
  ///      from the browser's SessionService `playerId:CODE` cache) and it
  ///      still points to a player in THIS room, reuse it. Fast path for
  ///      a same-browser page reload mid-game.
  ///
  ///   2. **Browser fingerprint**: If [browserId] is supplied and a player
  ///      in this room already carries that browser_id, reuse it. This
  ///      covers the "per-room cache got wiped but the browser-wide
  ///      fingerprint survived" case — e.g. a user closed the tab, the
  ///      per-room entry fell out of SharedPreferences somehow (cleanup,
  ///      origin swap between Vercel preview and prod), but this is still
  ///      the same browser. Matching on both room AND browser_id keeps
  ///      this safe: a different browser can't impersonate by typing the
  ///      same name.
  ///
  ///   3. **Fresh create**: Only allowed while the room is still in
  ///      `lobby`. If another player in the lobby already has this
  ///      trimmed name, we auto-suffix (" (2)", " (3)", …) rather than
  ///      showing two identical cards in the lobby.
  ///
  /// Dev bots (DevBotService) skip this path entirely — they call the
  /// repository directly — so browser-id logic won't fight bot seeding.
  Future<({Room room, Player player})> joinRoom({
    required String roomCode,
    required String playerName,
    String? existingPlayerId,
    String? browserId,
  }) async {
    final room = await roomRepository.findRoomByCode(roomCode);
    if (room == null) {
      throw GameException('Stanza non trovata');
    }

    // (1) Cached playerId — fast path.
    if (existingPlayerId != null && existingPlayerId.isNotEmpty) {
      final cached = await roomRepository.findPlayerById(existingPlayerId);
      if (cached != null && cached.roomId == room.id) {
        return (room: room, player: cached);
      }
    }

    // (2) Browser fingerprint — secondary recovery. Works even mid-game
    // (not gated on lobby) because a disconnected player needs to come
    // back as themselves, not as a new row.
    if (browserId != null && browserId.isNotEmpty) {
      final byBrowser = await roomRepository.findPlayerByRoomAndBrowser(
        roomId: room.id,
        browserId: browserId,
      );
      if (byBrowser != null) {
        return (room: room, player: byBrowser);
      }
    }

    if (room.status != RoomStatus.lobby) {
      throw GameException('La partita è già iniziata');
    }

    // (3) Fresh create — pick a non-colliding display name so the lobby
    // doesn't show two identical chips. We read the current player list
    // once rather than looping SELECTs: the list is small and a single
    // round-trip is simpler/cheaper than probing name-by-name.
    final trimmed = playerName.trim();
    final finalName = await _uniqueNameFor(roomId: room.id, desired: trimmed);

    final player = await roomRepository.createPlayer(
      roomId: room.id,
      name: finalName,
      browserId: browserId,
    );
    return (room: room, player: player);
  }

  /// Returns [desired] if no player in the room already has that exact name
  /// (case-insensitive on the trimmed form); otherwise appends the lowest
  /// unused `(N)` suffix. Small race window — two simultaneous joins with
  /// the same name could both land on "Alex (2)" — acceptable for a
  /// friends' game, and the UI will at worst show the dupe briefly until
  /// someone rejoins.
  Future<String> _uniqueNameFor({
    required String roomId,
    required String desired,
  }) async {
    // Snapshot the current list via the realtime stream's first frame —
    // cheaper than a bespoke REST call and uses the path we already know
    // works.
    final current = await roomRepository.watchPlayers(roomId).first;
    final taken = current
        .map((p) => p.name.trim().toLowerCase())
        .toSet();
    if (!taken.contains(desired.toLowerCase())) return desired;
    // Start at 2 — "Alex" + "Alex (2)" reads more naturally than "Alex (1)".
    for (var i = 2; i < 1000; i++) {
      final candidate = '$desired ($i)';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
    }
    // Unreachable for any realistic lobby; fall back to the original so
    // we at least don't crash.
    return desired;
  }

  // --- Round progression --------------------------------------------------

  Future<void> startGame(String roomId) async {
    final all = await _questions();
    if (all.isEmpty) {
      throw GameException('Nessuna domanda disponibile');
    }
    // Question pick stays client-side so we keep using `_questionCache`
    // and don't duplicate the mode filter in SQL. The server-side
    // `start_game` function does the idempotency check inside the same
    // transaction as the round insert (see
    // supabase/migrations/20260417093000_add_round_transition_rpcs.sql),
    // so if a round-1 row already exists (e.g. lobby auto-start raced a
    // manual click, or a second tab fired start) the RPC bumps the room
    // to `in_round` at the existing round_number and the question id we
    // just picked is harmlessly discarded. No Dart-side idempotency
    // probe is needed anymore — the FOR UPDATE lock on `rooms` + the
    // UNIQUE(room_id, round_number) constraint make it structurally
    // impossible to end up with duplicate Round 1 rows.
    final room = await roomRepository.findRoomById(roomId);
    final pool = _questionsForRoom(all, room?.modes ?? const []);
    final first = pool[_random.nextInt(pool.length)];

    await gameRepository.startGameRpc(
      roomId: roomId,
      firstQuestionId: first.id,
    );
  }

  Future<void> submitVote({
    required String roundId,
    required String voterId,
    required String votedForId,
  }) async {
    await gameRepository.submitVote(
      roundId: roundId,
      voterId: voterId,
      votedForId: votedForId,
    );
  }

  Future<void> revealResults({
    required String roundId,
    required String roomId,
  }) async {
    // Atomic: flips the round to `revealed` and the room to `results` in
    // a single transaction guarded by FOR UPDATE on `rooms`. Replaces the
    // previous two-step UPDATE that could interleave with a racing
    // `nextRound` call.
    await gameRepository.revealResultsRpc(
      roomId: roomId,
      roundId: roundId,
    );
  }

  Future<void> nextRound({
    required String roomId,
    required int currentRoundNumber,
    required List<Round> existingRounds,
  }) async {
    final all = await _questions();
    // Filter by mode FIRST, then by already-used question ids — this matches
    // the React `nextRound` semantics ("no more questions" means no more
    // questions *in scope*, not in the global pool).
    final room = await roomRepository.findRoomById(roomId);
    final scoped = _questionsForRoom(all, room?.modes ?? const []);
    final usedIds = existingRounds.map((r) => r.questionId).toSet();
    final available =
        scoped.where((q) => !usedIds.contains(q.id)).toList(growable: false);

    if (available.isEmpty || currentRoundNumber >= kMaxRounds) {
      await roomRepository.updateRoomStatus(roomId, status: RoomStatus.finished);
      return;
    }

    final next = available[_random.nextInt(available.length)];

    // Atomic: close the previous round + insert the next round + bump
    // `rooms.current_round` in one transaction, serialized against
    // concurrent callers via FOR UPDATE on the room row. This replaces
    // four separate round-trips (fetchRoundsForRoom, updateRoundStatus,
    // createRound, updateRoomStatus) plus the Dart-side idempotency
    // probe — the server's UNIQUE(room_id, round_number) constraint +
    // row lock makes double-tap/ghost-round races structurally
    // impossible.
    await gameRepository.advanceRoundRpc(
      roomId: roomId,
      nextQuestionId: next.id,
    );
  }

  Future<void> endGame(String roomId) async {
    await roomRepository.updateRoomStatus(roomId, status: RoomStatus.finished);
  }

  /// All questions in the default pack — cached after first call.
  /// Used by the UI's `allQuestionsByIdProvider` to resolve current question text.
  Future<List<Question>> allQuestions() => _questions();

  /// Used by the end screen. Fetches historic votes once, not reactively.
  Future<List<Question>> questionsForIds(Set<String> ids) async {
    final all = await _questions();
    return all.where((q) => ids.contains(q.id)).toList();
  }
}

class GameException implements Exception {
  GameException(this.message);
  final String message;
  @override
  String toString() => message;
}
