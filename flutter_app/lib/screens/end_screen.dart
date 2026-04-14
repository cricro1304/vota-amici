import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/round.dart';
import '../models/vote.dart';
import '../state/providers.dart';
import '../widgets/emoji_text.dart';
import '../widgets/game_layout.dart';

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

    final summaryAsync = ref.watch(_summaryProvider(roomId));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Errore: $e',
          style: bodyFont(color: AppColors.destructive),
        ),
      ),
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
          final maxV =
              voteCounts.values.fold<int>(0, (a, b) => b > a ? b : a);
          final winners = voteCounts.entries
              .where((e) => e.value == maxV && e.value > 0)
              .map((e) => '${playerNames[e.key] ?? '?'} (${e.value})')
              .toList();
          results.add(_RoundResult(
            number: r.roundNumber,
            question: questionMap[r.questionId] ?? '',
            summary: winners.isEmpty ? 'Nessun voto' : winners.join(', '),
          ));
        }

        return PopIn(
          child: Column(
            children: [
              // Static trophy + title — matches React (no floater, no stagger).
              // EmojiText swaps 🏆 for the Twemoji PNG, so every platform shows
              // the same Apple-ish trophy instead of whatever glyph the
              // browser/OS happens to have.
              EmojiText('🏆', style: bodyFont(fontSize: 48)),
              const SizedBox(height: 8),
              Text(
                'Classifica Finale',
                style: displayFont(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final r = results[i];
                    return SoftCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // React label: "Round N)" — mixed case, trailing
                          // paren, no letterSpacing.
                          Text(
                            'Round ${r.number})',
                            style: bodyFont(
                              color: AppColors.mutedFg,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          EmojiText(
                            r.question,
                            style: displayFont(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.foreground,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            r.summary,
                            style: bodyFont(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 320,
                child: ElevatedButton(
                  onPressed: () => context.go('/'),
                  child: const EmojiText('🎮 Nuova Partita'),
                ),
              ),
            ],
          ),
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

class _EndSummary {
  _EndSummary({required this.votes, required this.questions});
  final List<Vote> votes;
  final Map<String, String> questions;
}

/// Keyed by [roomId] only — lists / sets in provider families break caching
/// because they don't have structural equality. We read the round list from
/// the already-streaming `roundsProvider` instead.
final _summaryProvider = FutureProvider.autoDispose
    .family<_EndSummary, String>((ref, roomId) async {
  final gameRepo = ref.watch(gameRepositoryProvider);
  final gameService = ref.watch(gameServiceProvider);
  final rounds =
      ref.watch(roundsProvider(roomId)).valueOrNull ?? const <Round>[];
  if (rounds.isEmpty) {
    return _EndSummary(votes: const [], questions: const {});
  }
  final votes = await gameRepo.fetchAllVotes(rounds.map((r) => r.id).toList());
  final qIds = rounds.map((r) => r.questionId).toSet();
  final questions = await gameService.questionsForIds(qIds);
  return _EndSummary(
    votes: votes,
    questions: {for (final q in questions) q.id: q.text},
  );
});
