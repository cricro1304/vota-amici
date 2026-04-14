import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/service_locator.dart';
import '../models/player.dart';
import '../models/question.dart';
import '../models/room.dart';
import '../models/round.dart';
import '../models/vote.dart';
import '../repositories/game_repository.dart';
import '../repositories/room_repository.dart';
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

/// Questions are fetched once per app session and cached in GameService.
/// This provider just re-exposes that cache for the UI.
final questionsByIdProvider =
    FutureProvider.family<Map<String, Question>, Set<String>>((ref, ids) async {
  if (ids.isEmpty) return const {};
  final service = ref.watch(gameServiceProvider);
  final qs = await service.questionsForIds(ids);
  return {for (final q in qs) q.id: q};
});

final currentQuestionTextProvider =
    Provider.family<String?, String>((ref, roomId) {
  final round = ref.watch(currentRoundProvider(roomId));
  if (round == null) return null;
  final map =
      ref.watch(questionsByIdProvider({round.questionId})).valueOrNull ?? {};
  return map[round.questionId]?.text;
});
