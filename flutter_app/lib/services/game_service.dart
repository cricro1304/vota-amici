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
  }) async {
    final code = generateRoomCode();
    final room =
        await roomRepository.createRoom(code: code, timerSeconds: timerSeconds);
    final player = await roomRepository.createPlayer(
      roomId: room.id,
      name: hostName,
      isHost: true,
    );
    await roomRepository.setHost(room.id, player.id);
    return (room: room, player: player);
  }

  Future<({Room room, Player player})> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    final room = await roomRepository.findRoomByCode(roomCode);
    if (room == null) {
      throw GameException('Stanza non trovata');
    }

    final existing = await roomRepository.findPlayerByName(
      roomId: room.id,
      name: playerName,
    );
    if (existing != null) {
      return (room: room, player: existing);
    }

    if (room.status != RoomStatus.lobby) {
      throw GameException('La partita è già iniziata');
    }

    final player = await roomRepository.createPlayer(
      roomId: room.id,
      name: playerName,
    );
    return (room: room, player: player);
  }

  // --- Round progression --------------------------------------------------

  Future<void> startGame(String roomId) async {
    final questions = await _questions();
    if (questions.isEmpty) {
      throw GameException('Nessuna domanda disponibile');
    }
    // Idempotent: if a round already exists for this room (because the lobby
    // auto-start fired alongside a manual click, or a second tab raced us),
    // just make sure the room's status is in_round and bail — do NOT insert
    // a duplicate round_number=1. This is what produced the "ghost Round 1"
    // cards on the end screen.
    final existing = await gameRepository.fetchRoundsForRoom(roomId);
    if (existing.isNotEmpty) {
      await roomRepository.updateRoomStatus(
        roomId,
        status: RoomStatus.inRound,
        currentRound: existing
            .map((r) => r.roundNumber)
            .fold<int>(1, (a, b) => b > a ? b : a),
      );
      return;
    }
    final first = questions[_random.nextInt(questions.length)];
    await gameRepository.createRound(
      roomId: roomId,
      questionId: first.id,
      roundNumber: 1,
    );
    await roomRepository.updateRoomStatus(
      roomId,
      status: RoomStatus.inRound,
      currentRound: 1,
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
    await gameRepository.updateRoundStatus(roundId, RoundStatus.revealed);
    await roomRepository.updateRoomStatus(roomId, status: RoomStatus.results);
  }

  Future<void> nextRound({
    required String roomId,
    required int currentRoundNumber,
    required List<Round> existingRounds,
  }) async {
    final questions = await _questions();
    final usedIds = existingRounds.map((r) => r.questionId).toSet();
    final available =
        questions.where((q) => !usedIds.contains(q.id)).toList(growable: false);

    if (available.isEmpty || currentRoundNumber >= kMaxRounds) {
      await roomRepository.updateRoomStatus(roomId, status: RoomStatus.finished);
      return;
    }

    final nextNumber = currentRoundNumber + 1;

    // Idempotent: re-fetch rounds from the DB (not the stale list passed in)
    // and bail if round `nextNumber` already exists. Without this, a
    // double-tap on "Prossimo Round" — or two clients racing — inserts two
    // rows with the same `round_number`, showing as ghost rounds on the
    // end screen.
    final fresh = await gameRepository.fetchRoundsForRoom(roomId);
    if (fresh.any((r) => r.roundNumber == nextNumber)) {
      await roomRepository.updateRoomStatus(
        roomId,
        status: RoomStatus.inRound,
        currentRound: nextNumber,
      );
      return;
    }

    final next = available[_random.nextInt(available.length)];
    final current =
        fresh.firstWhere((r) => r.roundNumber == currentRoundNumber);
    await gameRepository.updateRoundStatus(current.id, RoundStatus.closed);

    await gameRepository.createRound(
      roomId: roomId,
      questionId: next.id,
      roundNumber: nextNumber,
    );

    await roomRepository.updateRoomStatus(
      roomId,
      status: RoomStatus.inRound,
      currentRound: nextNumber,
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
