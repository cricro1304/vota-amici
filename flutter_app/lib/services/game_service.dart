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

    final next = available[_random.nextInt(available.length)];
    final nextNumber = currentRoundNumber + 1;

    final current = existingRounds
        .firstWhere((r) => r.roundNumber == currentRoundNumber);
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
