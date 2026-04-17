import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/pack.dart';
import '../models/player.dart';
import '../models/vote.dart';
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
    final pack = Pack.byDbId(room.packId);
    final isCouples = pack.kind == PackKind.couples;

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
            if (isCouples)
              // Couples have a fundamentally different reveal: with only
              // 2 players and 2 votes there's no "winner by tally"; we
              // show one of three outcomes (agree / cross / self) with
              // tailored copy per Cristiano's voice-memo taxonomy.
              _CouplesReveal(
                players: players,
                votes: votes,
              )
            else if (winners.isEmpty)
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

/// One of the three couples-round outcomes:
///   - `agree`          → both voters named the same person
///   - `crossDisagree`  → A picked B, B picked A (each thinks it's the
///                         OTHER one more X)
///   - `selfDisagree`   → A picked A, B picked B (each picked THEMSELF,
///                         i.e. mutual self-claim)
///   - `incomplete`     → fewer than 2 votes landed before the reveal
///                         fired (edge case, e.g. host revealed early
///                         or a voter disconnected)
enum _CouplesOutcome { agree, crossDisagree, selfDisagree, incomplete }

/// Reveal body for the couples pack. Computes the outcome locally from
/// `players` + `votes` — no server-side help needed — and renders one of
/// four states. Keep rendering fast and self-contained; this widget is
/// rebuilt whenever the votes stream ticks.
class _CouplesReveal extends StatelessWidget {
  const _CouplesReveal({required this.players, required this.votes});

  final List<Player> players;
  final List<Vote> votes;

  String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '??';
    return t.substring(0, t.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Map a player's index in [players] to their palette colour. Keeps
  /// A and B visually distinct from each other AND consistent with the
  /// lobby/voting screens which use the same palette.
  Color _colourFor(Player p) =>
      playerColor(players.indexWhere((x) => x.id == p.id));

  _CouplesOutcome _compute() {
    if (players.length != 2 || votes.length < 2) {
      return _CouplesOutcome.incomplete;
    }
    // Index votes by voter to make the pattern-match trivial.
    final byVoter = <String, String>{
      for (final v in votes) v.voterId: v.votedForId,
    };
    final a = players[0];
    final b = players[1];
    final aVote = byVoter[a.id];
    final bVote = byVoter[b.id];
    if (aVote == null || bVote == null) return _CouplesOutcome.incomplete;

    if (aVote == bVote) return _CouplesOutcome.agree;
    if (aVote == b.id && bVote == a.id) return _CouplesOutcome.crossDisagree;
    if (aVote == a.id && bVote == b.id) return _CouplesOutcome.selfDisagree;
    // N=2 with both voting different people and not hitting either of
    // the two "clean" disagreement patterns is logically impossible —
    // with 2 candidates and 2 voters, "different answers" is exhaustively
    // either cross or self. We fall through to `incomplete` as a safety net.
    return _CouplesOutcome.incomplete;
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _compute();
    // Wrap the per-outcome body in an ambient heart backdrop so every
    // couples reveal (agree / cross / self) gets the same themed
    // atmosphere. Hearts sit *behind* the content via Stack children
    // order; pointer events pass through to any widgets above them.
    return _RevealHeartBackdrop(
      // Tint hearts toward the mood of the outcome: strong pink for
      // agreement, orange for cross (fiery), purple-ish for self.
      mood: _moodFor(outcome),
      child: _outcomeBody(outcome),
    );
  }

  _RevealMood _moodFor(_CouplesOutcome o) {
    switch (o) {
      case _CouplesOutcome.agree:
        return _RevealMood.tender;
      case _CouplesOutcome.crossDisagree:
        return _RevealMood.spicy;
      case _CouplesOutcome.selfDisagree:
        return _RevealMood.playful;
      case _CouplesOutcome.incomplete:
        return _RevealMood.neutral;
    }
  }

  Widget _outcomeBody(_CouplesOutcome outcome) {
    switch (outcome) {
      case _CouplesOutcome.agree:
        // Both picked the same person — find them and show a single
        // large avatar with a "siete d'accordo" banner. We recompute
        // the target here instead of threading it through _compute()
        // to keep the signature simple; it's O(players.length) = 2.
        final targetId = votes.first.votedForId;
        final target = players.firstWhere(
          (p) => p.id == targetId,
          // Shouldn't happen — targetId is always one of the two — but
          // defending against a race where a player row is deleted
          // mid-reveal. Falls back to the first player.
          orElse: () => players.first,
        );
        return Column(
          children: [
            WinnerRing(
              initials: _initials(target.name),
              size: 110,
              innerColor: _colourFor(target),
            ),
            const SizedBox(height: 12),
            Text(
              target.name,
              style: displayFont(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 16),
            EmojiText(
              '💕 Siete d\'accordo!',
              textAlign: TextAlign.center,
              style: displayFont(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        );

      case _CouplesOutcome.crossDisagree:
        // "A thinks B, B thinks A". Show both avatars side by side and
        // the headline "Parlatene — pensate entrambi sia l'altro".
        return _CouplesPairBody(
          players: players,
          initials: _initials,
          colourFor: _colourFor,
          headlineEmoji: '🔥',
          headlineText: 'Parlatene!',
          subtext: 'Pensate entrambi sia l\'altro',
        );

      case _CouplesOutcome.selfDisagree:
        // "A thinks A, B thinks B". Different mood from cross: this is
        // a mutual claim, often funny/telling. Headline is gentler.
        return _CouplesPairBody(
          players: players,
          initials: _initials,
          colourFor: _colourFor,
          headlineEmoji: '👀',
          headlineText: 'Discutete!',
          subtext: 'Ognuno ha votato se stesso',
        );

      case _CouplesOutcome.incomplete:
        return Text(
          'Voti non ancora completi',
          style: displayFont(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.mutedFg,
          ),
        );
    }
  }
}

/// Mood hint for the reveal backdrop. Drives which hearts/emojis
/// float behind the result, letting the three couples outcomes share
/// the same decorative structure while still feeling distinct.
enum _RevealMood { tender, spicy, playful, neutral }

/// Ambient heart decoration behind a couples reveal body. Keeps the
/// per-outcome widgets small and focused on their content while giving
/// the whole reveal screen a consistent "this is a game for two"
/// atmosphere. Hearts are positioned via a Stack so they don't shift
/// the content's layout, and use the shared `_RevealFloatingHeart`
/// animation for staggered drift/fade.
class _RevealHeartBackdrop extends StatelessWidget {
  const _RevealHeartBackdrop({required this.child, required this.mood});
  final Widget child;
  final _RevealMood mood;

  @override
  Widget build(BuildContext context) {
    // Heart set tuned to the outcome mood. Keep lengths identical so
    // the five positioned slots below always have something to render.
    final List<String> hearts = switch (mood) {
      _RevealMood.tender => const ['💕', '💖', '💗', '💘', '✨'],
      _RevealMood.spicy => const ['🔥', '💔', '❤️‍🔥', '💢', '✨'],
      _RevealMood.playful => const ['👀', '💬', '🙈', '🤭', '✨'],
      _RevealMood.neutral => const ['⏳', '💭', '✨', '💫', '✨'],
    };

    return SizedBox(
      width: double.infinity,
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Backdrop hearts — positioned so they frame the content
          // without overlapping the central avatar(s).
          Positioned(
            left: 12,
            top: 6,
            child: _RevealFloatingHeart(emoji: hearts[0], size: 26, phaseMs: 0),
          ),
          Positioned(
            right: 18,
            top: 20,
            child:
                _RevealFloatingHeart(emoji: hearts[1], size: 22, phaseMs: 500),
          ),
          Positioned(
            left: 8,
            bottom: 40,
            child:
                _RevealFloatingHeart(emoji: hearts[2], size: 24, phaseMs: 1100),
          ),
          Positioned(
            right: 14,
            bottom: 24,
            child:
                _RevealFloatingHeart(emoji: hearts[3], size: 20, phaseMs: 1700),
          ),
          Positioned(
            left: 40,
            bottom: 0,
            child:
                _RevealFloatingHeart(emoji: hearts[4], size: 16, phaseMs: 2200),
          ),
          // Foreground body — centered.
          Center(child: child),
        ],
      ),
    );
  }
}

/// Ambient heart for `_RevealHeartBackdrop`. Same animation model as
/// the lobby's waiting hearts: staggered repeat with translate + fade
/// + scale so the cluster reads as organic. Kept private to this
/// file rather than promoted to a shared widget — the lobby and home
/// screen each have their own copy with different size budgets, and
/// consolidating would mean parameterising more than it's worth.
class _RevealFloatingHeart extends StatefulWidget {
  const _RevealFloatingHeart({
    required this.emoji,
    required this.size,
    required this.phaseMs,
  });
  final String emoji;
  final double size;
  final int phaseMs;

  @override
  State<_RevealFloatingHeart> createState() => _RevealFloatingHeartState();
}

class _RevealFloatingHeartState extends State<_RevealFloatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.phaseMs), () {
      if (mounted) _c.repeat(reverse: true);
    });
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
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Opacity(
          // A touch more subtle than the lobby hearts — these are
          // ambient background decoration, not the main event.
          opacity: 0.4 + 0.45 * t,
          child: Transform.translate(
            offset: Offset(0, -7 * t),
            child: Transform.scale(
              scale: 0.85 + 0.2 * t,
              child: child,
            ),
          ),
        );
      },
      child: EmojiText(
        widget.emoji,
        style: TextStyle(fontSize: widget.size),
      ),
    );
  }
}

/// Shared layout for the two disagreement cases — two avatars side by
/// side, then a punchy headline + short subtext. The callsites only
/// vary the copy + emoji, so extracting this keeps the outcome-to-UI
/// mapping readable in one place.
class _CouplesPairBody extends StatelessWidget {
  const _CouplesPairBody({
    required this.players,
    required this.initials,
    required this.colourFor,
    required this.headlineEmoji,
    required this.headlineText,
    required this.subtext,
  });

  final List<Player> players;
  final String Function(String) initials;
  final Color Function(Player) colourFor;
  final String headlineEmoji;
  final String headlineText;
  final String subtext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 28,
          runSpacing: 16,
          children: [
            for (final p in players)
              Column(
                children: [
                  WinnerRing(
                    initials: initials(p.name),
                    size: 90,
                    innerColor: colourFor(p),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.name,
                    style: displayFont(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        EmojiText(
          '$headlineEmoji $headlineText',
          textAlign: TextAlign.center,
          style: displayFont(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtext,
          textAlign: TextAlign.center,
          style: bodyFont(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedFg,
          ),
        ),
      ],
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
