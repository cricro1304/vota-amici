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

  Future<Round> createRound({
    required String roomId,
    required String questionId,
    required int roundNumber,
  }) async {
    final data = await _client
        .from('rounds')
        .insert({
          'room_id': roomId,
          'question_id': questionId,
          'round_number': roundNumber,
          'status': 'voting',
        })
        .select()
        .single();
    return Round.fromJson(data);
  }

  Future<void> updateRoundStatus(String roundId, RoundStatus status) async {
    await _client
        .from('rounds')
        .update({'status': roundStatusToString(status)}).eq('id', roundId);
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
}
