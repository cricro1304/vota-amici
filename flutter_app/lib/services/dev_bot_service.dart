import 'dart:async';
import 'dart:math';

import '../models/player.dart';
import '../models/room.dart';
import '../models/round.dart';
import '../models/vote.dart';
import '../repositories/game_repository.dart';
import '../repositories/room_repository.dart';
import 'game_service.dart';

/// Dev-only: seeds bot players into a room and auto-plays their moves.
///
/// Why this exists: testing a voting game needs 3+ humans normally.
/// In dev mode we spawn bots as real rows in `players`, then a watcher
/// listens to the same Supabase streams the UI uses and submits random
/// votes after a small delay. The host (you) still plays normally.
///
/// Everything goes through the real tables — no mocks — so you're
/// exercising the actual realtime flow.
class DevBotService {
  DevBotService({
    required this.roomRepository,
    required this.gameRepository,
    required this.gameService,
  });

  final RoomRepository roomRepository;
  final GameRepository gameRepository;
  final GameService gameService;

  final _rng = Random();
  static const _botNames = [
    'Bot Alice',
    'Bot Bruno',
    'Bot Chiara',
    'Bot Dario',
    'Bot Elena',
  ];

  /// Currently-running watchers, keyed by roomId. Lets us cancel if the
  /// user navigates away.
  final Map<String, _BotSession> _sessions = {};

  /// Create N bot players in the room. They become regular `players` rows.
  Future<List<Player>> seedBots({
    required String roomId,
    required int count,
  }) async {
    assert(count >= 1 && count <= _botNames.length);
    final bots = <Player>[];
    for (var i = 0; i < count; i++) {
      final p = await roomRepository.createPlayer(
        roomId: roomId,
        name: _botNames[i],
      );
      bots.add(p);
    }

    // Start watching this room for round transitions so bots auto-vote.
    startWatching(roomId: roomId, botIds: bots.map((b) => b.id).toSet());
    return bots;
  }

  /// Subscribe to room + round + votes streams for this room and have
  /// the bots act autonomously.
  void startWatching({
    required String roomId,
    required Set<String> botIds,
  }) {
    _sessions[roomId]?.dispose();

    final session = _BotSession(
      roomId: roomId,
      botIds: botIds,
      roomRepository: roomRepository,
      gameRepository: gameRepository,
      rng: _rng,
    );
    _sessions[roomId] = session;
    session.start();
  }

  void stop(String roomId) {
    _sessions.remove(roomId)?.dispose();
  }

  void dispose() {
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
  }
}

class _BotSession {
  _BotSession({
    required this.roomId,
    required this.botIds,
    required this.roomRepository,
    required this.gameRepository,
    required this.rng,
  });

  final String roomId;
  final Set<String> botIds;
  final RoomRepository roomRepository;
  final GameRepository gameRepository;
  final Random rng;

  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<Round>>? _roundsSub;
  StreamSubscription<List<Vote>>? _votesSub;
  StreamSubscription<List<Player>>? _playersSub;

  List<Player> _players = const [];
  Round? _currentRound;
  Set<String> _votedBotsThisRound = {};

  void start() {
    _playersSub =
        roomRepository.watchPlayers(roomId).listen((ps) => _players = ps);

    _roundsSub = gameRepository.watchRounds(roomId).listen((rounds) async {
      // Whenever rounds change, re-derive current round from room state.
      final room = await roomRepository.findRoomByCode(''); // not used here
      // We'll instead rely on the room stream below.
    });

    _roomSub = roomRepository.watchRoom(roomId).listen((room) async {
      if (room == null) return;
      if (room.status == RoomStatus.inRound) {
        // Find the round matching current_round number.
        final all = await _currentRounds();
        Round? match;
        for (final r in all) {
          if (r.roundNumber == room.currentRound) {
            match = r;
            break;
          }
        }
        if (match != null && match.id != _currentRound?.id) {
          _currentRound = match;
          _votedBotsThisRound = {};
          _rewatchVotes(match.id);
          _scheduleBotVotes();
        }
      } else if (room.status == RoomStatus.finished) {
        dispose();
      }
    });
  }

  Future<List<Round>> _currentRounds() async {
    // One-shot read to avoid racing with the stream.
    final completer = Completer<List<Round>>();
    final sub = gameRepository.watchRounds(roomId).listen((r) {
      if (!completer.isCompleted) completer.complete(r);
    });
    final rounds = await completer.future;
    await sub.cancel();
    return rounds;
  }

  void _rewatchVotes(String roundId) {
    _votesSub?.cancel();
    _votesSub = gameRepository.watchVotesForRound(roundId).listen((votes) {
      for (final v in votes) {
        if (botIds.contains(v.voterId)) {
          _votedBotsThisRound.add(v.voterId);
        }
      }
    });
  }

  /// Each bot waits a short random delay, then picks a random player
  /// (including other bots and the host) and votes.
  void _scheduleBotVotes() {
    final round = _currentRound;
    if (round == null) return;

    for (final botId in botIds) {
      final delay = Duration(milliseconds: 800 + rng.nextInt(2200));
      Future.delayed(delay, () async {
        if (_currentRound?.id != round.id) return;
        if (_votedBotsThisRound.contains(botId)) return;
        final candidates =
            _players.where((p) => p.id != botId).toList(growable: false);
        if (candidates.isEmpty) return;
        final target = candidates[rng.nextInt(candidates.length)];
        try {
          await gameRepository.submitVote(
            roundId: round.id,
            voterId: botId,
            votedForId: target.id,
          );
        } catch (_) {
          // Swallow duplicate-vote errors silently — the unique constraint
          // protects us against double-submission.
        }
      });
    }
  }

  void dispose() {
    _roomSub?.cancel();
    _roundsSub?.cancel();
    _votesSub?.cancel();
    _playersSub?.cancel();
  }
}
