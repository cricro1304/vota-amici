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
import '../services/share_service.dart';

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
final shareServiceProvider =
    Provider<ShareService>((_) => locator<ShareService>());

// --- Reactive streams: room, players, rounds -----------------------------
//
// All room-scoped providers below are `.autoDispose` so when no widget is
// watching them their underlying subscriptions tear down — see
// RoomRepository.watchRoom for the realtime + REST-watchdog pair we want
// to release. Without autoDispose, every roomId you ever visited keeps
// an open realtime channel and an 8-second polling timer for the rest
// of the session. Riverpod waits one frame after the last listener
// detaches before disposing, so a normal lobby → voting → results →
// lobby navigation does NOT cause flapping rebuilds.

/// Stream of the current room. Updates come via Supabase Realtime deltas
/// plus a REST watchdog that catches silent realtime stalls — see
/// `RoomRepository.watchRoom` for the merge policy.
final roomProvider =
    StreamProvider.autoDispose.family<Room?, String>((ref, roomId) {
  return ref.watch(roomRepositoryProvider).watchRoom(roomId);
});

final playersProvider =
    StreamProvider.autoDispose.family<List<Player>, String>((ref, roomId) {
  return ref.watch(roomRepositoryProvider).watchPlayers(roomId);
});

final roundsProvider =
    StreamProvider.autoDispose.family<List<Round>, String>((ref, roomId) {
  return ref.watch(gameRepositoryProvider).watchRounds(roomId);
});

/// Derived: the round matching room.current_round. Computed from existing
/// streams — no separate query.
final currentRoundProvider =
    Provider.autoDispose.family<Round?, String>((ref, roomId) {
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
    StreamProvider.autoDispose.family<List<Vote>, String>((ref, roomId) {
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
    Provider.autoDispose.family<String?, String>((ref, roomId) {
  final round = ref.watch(currentRoundProvider(roomId));
  if (round == null) return null;
  final map = ref.watch(allQuestionsByIdProvider).valueOrNull ?? const {};
  return map[round.questionId]?.text;
});

/// Full question object for the round currently in play. Used by the voting
/// screen to style the question card differently for light / neutro / spicy
/// prompts (so a 🌶️ question is visually obvious before the vote).
final currentQuestionProvider =
    Provider.autoDispose.family<Question?, String>((ref, roomId) {
  final round = ref.watch(currentRoundProvider(roomId));
  if (round == null) return null;
  final map = ref.watch(allQuestionsByIdProvider).valueOrNull ?? const {};
  return map[round.questionId];
});
