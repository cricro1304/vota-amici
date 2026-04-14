import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/round.dart';
import '../models/vote.dart';
import '../state/providers.dart';

/// Shows the final scoreboard. Unlike the web version, we fetch historic
/// votes ONCE here (via FutureProvider) rather than reactively streaming
/// them across the whole game.
class EndScreen extends ConsumerWidget {
  const EndScreen({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players =
        ref.watch(playersProvider(roomId)).valueOrNull ?? const [];
    final rounds = ref.watch(roundsProvider(roomId)).valueOrNull ?? const [];

    final summaryAsync = ref.watch(_summaryProvider((
      roomId: roomId,
      roundIds: rounds.map((r) => r.id).toList(),
    )));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore: $e')),
      data: (summary) {
        final playerNames = {for (final p in players) p.id: p.name};
        final questionMap = summary.questions;

        final results = <_RoundResult>[];
        final sortedRounds = [...rounds]
          ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
        for (final r in sortedRounds) {
          final voteCounts = <String, int>{};
          for (final v in summary.votes.where((v) => v.roundId == r.id)) {
            voteCounts[v.votedForId] = (voteCounts[v.votedForId] ?? 0) + 1;
          }
          final maxV = voteCounts.values.fold<int>(0, (a, b) => b > a ? b : a);
          final winners = voteCounts.entries
              .where((e) => e.value == maxV && e.value > 0)
              .map((e) => '${playerNames[e.key] ?? '?'} (${e.value})')
              .toList();
          results.add(_RoundResult(
            number: r.roundNumber,
            question: questionMap[r.questionId] ?? '',
            summary:
                winners.isEmpty ? 'Nessun voto' : winners.join(', '),
          ));
        }

        return Column(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 50)),
            const SizedBox(height: 6),
            const Text(
              'Classifica Finale',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = results[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Round ${r.number})',
                              style: const TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(r.question,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            r.summary,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 280,
              child: ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('🎮 Nuova Partita'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoundResult {
  _RoundResult({
    required this.number,
    required this.question,
    required this.summary,
  });
  final int number;
  final String question;
  final String summary;
}

typedef _SummaryKey = ({String roomId, List<String> roundIds});

class _EndSummary {
  _EndSummary({required this.votes, required this.questions});
  final List<Vote> votes;
  final Map<String, String> questions;
}

final _summaryProvider =
    FutureProvider.autoDispose.family<_EndSummary, _SummaryKey>((ref, key) async {
  final gameRepo = ref.watch(gameRepositoryProvider);
  final gameService = ref.watch(gameServiceProvider);
  if (key.roundIds.isEmpty) {
    return _EndSummary(votes: const [], questions: const {});
  }
  final votes = await gameRepo.fetchAllVotes(key.roundIds);
  // Need to resolve question texts for the rounds we have.
  final rounds = ref.read(roundsProvider(key.roomId)).valueOrNull ?? const <Round>[];
  final qIds = rounds.map((r) => r.questionId).toSet();
  final questions = await gameService.questionsForIds(qIds);
  return _EndSummary(
    votes: votes,
    questions: {for (final q in questions) q.id: q.text},
  );
});
