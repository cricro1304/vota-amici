import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/service_locator.dart';
import '../models/player.dart';
import '../models/question.dart';
import '../models/room.dart';
import '../models/round.dart';
import '../models/vote.dart';
import '../repositories/game_repository.dart';
import '../repositories/room_repository.dart';
import '../services/dev_bot_service.dart';
import '../services/game_service.dart';
import '../services/session_service.dart';

// --- Service providers (thin wrappers over GetIt) -------------------------

final roomRepositoryProvider =
    Provider<RoomRepository>((_) => locator<RoomRepository>());
final gameRepositoryProvider =
    Provider<GameRepository>((_) => locator<GameRepository>());
final gameServiceProvider =
    Provider<GameService>((_) => locator<GameService>());
final sessionServiceProvider =
    Provider<SessionService>((_) => locator<SessionService>());
final devBotServiceProvider =
    Provider<DevBotService>((_) => locator<DevBotService>());

// --- Reactive streams: room, players, rounds -----------------------------

/// Stream of the current room. Updates come via Supabase Realtime deltas —
/// NO refetch on change (this is the big efficiency win over the web app).
final roomProvider =
    StreamProvider.family<Room?, String>((ref, roomId) {
  return ref.watch(roomRepositoryProvider).watchRoom(roomId);
});

final playersProvider =
    StreamProvider.family<List<Player>, String>((ref, roomId) {
  return ref.watch(roomRepositoryProvider).watchPlayers(roomId);
});

final roundsProvider =
    StreamProvider.family<List<Round>, String>((ref, roomId) {
  return ref.watch(gameRepositoryProvider).watchRounds(roomId);
});

/// Derived: the round matching room.current_round. Computed from existing
/// streams — no separate query.
final currentRoundProvider =
    Provider.family<Round?, String>((ref, roomId) {
  final room = ref.watch(roomProvider(roomId)).valueOrNull;
  final rounds = ref.watch(roundsProvider(roomId)).valueOrNull ?? const [];
  if (room == null || room.currentRound == 0) return null;
  for (final r in rounds) {
    if (r.roundNumber == room.currentRound) return r;
  }
  return null;
});

/// Votes for the CURRENT round only. Scoped stream means we don't get
/// notified about votes in other rooms or previous rounds.
final currentRoundVotesProvider =
    StreamProvider.family<List<Vote>, String>((ref, roomId) {
  final round = ref.watch(currentRoundProvider(roomId));
  if (round == null) return const Stream.empty();
  return ref.watch(gameRepositoryProvider).watchVotesForRound(round.id);
});

// --- Question cache -------------------------------------------------------

/// Fetches ALL questions in the default pack ONCE per app session.
/// Keyed by nothing — so Riverpod reuses the same future forever.
///
/// We intentionally avoid `.family` with a `Set<String>` here: Dart Set
/// literals don't have structural equality, so `{id}` would produce a fresh
/// provider instance on every rebuild and the UI would see a perpetual
/// loading state — which caused the "question text doesn't show" bug.
final allQuestionsByIdProvider =
    FutureProvider<Map<String, Question>>((ref) async {
  final service = ref.watch(gameServiceProvider);
  final qs = await service.allQuestions();
  return {for (final q in qs) q.id: q};
});

final currentQuestionTextProvider =
    Provider.family<String?, String>((ref, roomId) {
  final round = ref.watch(currentRoundProvider(roomId));
  if (round == null) return null;
  final map = ref.watch(allQuestionsByIdProvider).valueOrNull ?? const {};
  return map[round.questionId]?.text;
});
