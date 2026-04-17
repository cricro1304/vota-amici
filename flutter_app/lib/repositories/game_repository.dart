import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/question.dart';
import '../models/round.dart';
import '../models/vote.dart';

/// Rounds, votes, questions. Streams are narrowly scoped to the current
/// room/round to avoid firing events for unrelated games.
class GameRepository {
  GameRepository(this._client);
  final SupabaseClient _client;

  // --- Rounds -------------------------------------------------------------

  /// All rounds for a room, ordered. Used for end-of-game summary AND to
  /// derive the "current" round client-side without a separate query.
  Stream<List<Round>> watchRounds(String roomId) {
    return _client
        .from('rounds')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('round_number')
        .map((rows) => rows.map(Round.fromJson).toList());
  }

  /// One-shot fetch of every round in a room. Kept for tests and ad-hoc
  /// tooling; round transitions no longer call this — the `start_game`
  /// and `advance_round` Postgres functions do the idempotency check
  /// server-side inside the same transaction as the write.
  Future<List<Round>> fetchRoundsForRoom(String roomId) async {
    final rows = await _client
        .from('rounds')
        .select()
        .eq('room_id', roomId)
        .order('round_number');
    return (rows as List)
        .map((r) => Round.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // --- Round transitions (RPCs) -------------------------------------------
  //
  // These three wrap Postgres functions defined in
  // `supabase/migrations/20260417093000_add_round_transition_rpcs.sql`.
  // Each one runs as a single transaction guarded by `SELECT … FOR UPDATE`
  // on `rooms`, so concurrent callers serialize and we never end up with
  // duplicate `round_number` rows or half-applied transitions. All three
  // return void; clients pick up the new state via the existing
  // `watchRooms`/`watchRounds` realtime streams.

  /// Lobby → in_round, round 1. Idempotent.
  Future<void> startGameRpc({
    required String roomId,
    required String firstQuestionId,
  }) async {
    await _client.rpc('start_game', params: {
      'p_room_id': roomId,
      'p_first_question_id': firstQuestionId,
    });
  }

  /// Close the current round, insert round `current_round + 1`, bump the
  /// room. Idempotent on the next round_number.
  Future<void> advanceRoundRpc({
    required String roomId,
    required String nextQuestionId,
  }) async {
    await _client.rpc('advance_round', params: {
      'p_room_id': roomId,
      'p_next_question_id': nextQuestionId,
    });
  }

  /// Flip the current round to revealed and the room to results.
  /// Idempotent.
  Future<void> revealResultsRpc({
    required String roomId,
    required String roundId,
  }) async {
    await _client.rpc('reveal_results', params: {
      'p_room_id': roomId,
      'p_round_id': roundId,
    });
  }

  // --- Votes --------------------------------------------------------------

  /// Votes scoped to a single round. This is the key over-fetch fix vs. web:
  /// we subscribe only to the current round, and Supabase sends us row
  /// deltas — we don't refetch `allVotes` every time someone votes.
  Stream<List<Vote>> watchVotesForRound(String roundId) {
    return _client
        .from('votes')
        .stream(primaryKey: ['id'])
        .eq('round_id', roundId)
        .map((rows) => rows.map(Vote.fromJson).toList());
  }

  /// Historic votes for all rounds of a room — fetched once on demand for
  /// the end screen, NOT streamed.
  Future<List<Vote>> fetchAllVotes(List<String> roundIds) async {
    if (roundIds.isEmpty) return const [];
    final rows = await _client.from('votes').select().inFilter('round_id', roundIds);
    return (rows as List).map((r) => Vote.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> submitVote({
    required String roundId,
    required String voterId,
    required String votedForId,
  }) async {
    await _client.from('votes').insert({
      'round_id': roundId,
      'voter_id': voterId,
      'voted_for_id': votedForId,
    });
  }

  // --- Questions ----------------------------------------------------------

  /// Fetched once per app session and cached in the service layer.
  Future<List<Question>> fetchQuestionsForPack(String packId) async {
    final rows =
        await _client.from('questions').select().eq('pack_id', packId);
    return (rows as List)
        .map((r) => Question.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// All questions across every pack. Fetched once per app session and
  /// cached in the service layer — the total pool is small (a few dozen
  /// rows per pack × a handful of packs), so one fetch and a client-side
  /// filter by (pack_id, mode) is cheaper than a query per round.
  Future<List<Question>> fetchAllQuestions() async {
    final rows = await _client.from('questions').select();
    return (rows as List)
        .map((r) => Question.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
