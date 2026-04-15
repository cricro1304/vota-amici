import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/player.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/emoji_text.dart';
import '../widgets/game_layout.dart';
import '../widgets/landing_widgets.dart';

enum _Phase { intro, suspense, reveal }

class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({
    super.key,
    required this.roomId,
    required this.playerId,
  });

  final String roomId;
  final String playerId;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  _Phase _phase = _Phase.intro;
  String? _roundId;
  Timer? _introTimer;
  Timer? _suspenseTimer;
  bool _advancing = false;
  bool _ending = false;

  void _beginReveal(String roundId) {
    _roundId = roundId;
    _phase = _Phase.intro;
    _introTimer?.cancel();
    _suspenseTimer?.cancel();
    _introTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _phase = _Phase.suspense);
      _suspenseTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _phase = _Phase.reveal);
      });
    });
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _suspenseTimer?.cancel();
    super.dispose();
  }

  String _initialsOf(String name) {
    final t = name.trim();
    if (t.isEmpty) return '??';
    return t.substring(0, t.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _stripQuestion(String q) {
    var s = q;
    if (s.startsWith('Chi è il più ')) {
      s = 'Il più ${s.substring('Chi è il più '.length)}';
    } else if (s.startsWith('Chi è la più ')) {
      s = 'La più ${s.substring('Chi è la più '.length)}';
    }
    if (s.endsWith('?')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(roomProvider(widget.roomId)).valueOrNull;
    final round = ref.watch(currentRoundProvider(widget.roomId));
    final players =
        ref.watch(playersProvider(widget.roomId)).valueOrNull ?? const [];
    final votes =
        ref.watch(currentRoundVotesProvider(widget.roomId)).valueOrNull ??
            const [];
    final questionText =
        ref.watch(currentQuestionTextProvider(widget.roomId)) ?? '';

    // Don't render a blank screen during stream reconnects — show a waiting
    // placeholder so the user never sees a white page.
    if (room == null || round == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Floater(
                child: EmojiText('⏳', style: TextStyle(fontSize: 40))),
            const SizedBox(height: 12),
            Text(
              'Attendere…',
              textAlign: TextAlign.center,
              style: bodyFont(
                color: AppColors.mutedFg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    final isHost = room.hostPlayerId == widget.playerId;

    if (_roundId != round.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _beginReveal(round.id));
      });
    }

    final counts = <String, int>{};
    for (final p in players) {
      counts[p.id] = 0;
    }
    for (final v in votes) {
      counts[v.votedForId] = (counts[v.votedForId] ?? 0) + 1;
    }
    final maxVotes = counts.values.fold<int>(0, (a, b) => b > a ? b : a);
    final winners = maxVotes > 0
        ? players.where((p) => counts[p.id] == maxVotes).toList()
        : const <Player>[];

    return PopIn(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'ROUND ${room.currentRound}',
            style: bodyFont(
              color: AppColors.mutedFg,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 24),
          // React renders the question plainly (no card wrapper) during
          // intro and suspense. We match that.
          if (_phase == _Phase.intro || _phase == _Phase.suspense)
            EmojiText(
              '${_stripQuestion(questionText)} è...',
              textAlign: TextAlign.center,
              style: displayFont(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
            ),
          if (_phase == _Phase.suspense) ...[
            const SizedBox(height: 24),
            const _BouncingDots(),
          ],
          if (_phase == _Phase.reveal) ...[
            EmojiText(
              '${_stripQuestion(questionText)} è...',
              textAlign: TextAlign.center,
              style: displayFont(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.mutedFg,
              ),
            ),
            const SizedBox(height: 24),
            if (winners.isEmpty)
              Text(
                'Nessun voto!',
                style: displayFont(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              )
            else
              Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 24,
                    runSpacing: 16,
                    children: [
                      for (final w in winners)
                        Column(
                          children: [
                            // Landing's .result-winner-ring — gradient halo
                            // with a pink inner circle showing the initials.
                            // We feed it the player's palette colour rather
                            // than hard-coding pink so the 2nd / 3rd winners
                            // (on a tie) still look distinct.
                            WinnerRing(
                              initials: _initialsOf(w.name),
                              size: 110,
                              innerColor: playerColor(
                                  players.indexWhere((p) => p.id == w.id)),
                            ),
                            const SizedBox(height: 8),
                            // React uses text-3xl (30px) for the winner name.
                            Text(
                              w.name,
                              style: displayFont(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: AppColors.foreground,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // React has no pill background — just muted-foreground
                  // body text at text-lg (18px).
                  EmojiText(
                    winners.length > 1
                        ? '🏆 $maxVotes voti a testa!'
                        : '🏆 con $maxVotes vot${maxVotes == 1 ? 'o' : 'i'}!',
                    textAlign: TextAlign.center,
                    style: bodyFont(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mutedFg,
                    ),
                  ),
                ],
              ),
          ],
          const Spacer(),
          if (isHost && _phase == _Phase.reveal) ...[
            SizedBox(
              width: 280,
              child: ElevatedButton(
                onPressed: _advancing
                    ? null
                    : () async {
                        setState(() => _advancing = true);
                        final rounds =
                            ref.read(roundsProvider(widget.roomId)).valueOrNull ??
                                [];
                        try {
                          await ref.read(gameServiceProvider).nextRound(
                                roomId: widget.roomId,
                                currentRoundNumber: room.currentRound,
                                existingRounds: rounds,
                              );
                        } on GameException catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(e.message)));
                          }
                          if (mounted) setState(() => _advancing = false);
                        }
                        // On success the round stream will transition the
                        // screen away, so we don't need to reset _advancing.
                      },
                child: EmojiText(_advancing ? '…' : '➡️ Prossimo Round'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 280,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                ),
                onPressed: _ending
                    ? null
                    : () async {
                        setState(() => _ending = true);
                        try {
                          await ref
                              .read(gameServiceProvider)
                              .endGame(widget.roomId);
                        } catch (e) {
                          debugPrint('[results] endGame failed: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Errore: $e'),
                                duration: const Duration(seconds: 6),
                              ),
                            );
                          }
                          if (mounted) setState(() => _ending = false);
                        }
                      },
                child: EmojiText(_ending ? '…' : '🏁 Fine Partita'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BouncingDots extends StatefulWidget {
  const _BouncingDots();
  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        double offset(int i) {
          final t = (_c.value + i * 0.15) % 1.0;
          return (t < 0.5 ? t : 1 - t) * 16;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              Transform.translate(
                offset: Offset(0, -offset(i)),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}
