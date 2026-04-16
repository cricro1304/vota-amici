import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/player.dart';
import '../models/round.dart';
import '../models/vote.dart';
import '../state/providers.dart';
import '../widgets/confetti_burst.dart';
import '../widgets/emoji_text.dart';
import '../widgets/game_layout.dart';
import '../widgets/round_share_card.dart';

/// Final scoreboard shown after the host ends the game.
///
/// Unlike the voting screen, this fetches historic votes ONCE (via a
/// FutureProvider) rather than subscribing to a live stream — the game is
/// over, nothing else is going to change.
class EndScreen extends ConsumerStatefulWidget {
  const EndScreen({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<EndScreen> createState() => _EndScreenState();
}

class _EndScreenState extends ConsumerState<EndScreen> {
  // Tracks which round-card is currently rendering a share. Keyed by round
  // id so two simultaneous taps can't collide — although the UI prevents
  // that, this is cheap insurance.
  final Set<String> _sharingRoundIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final players =
        ref.watch(playersProvider(widget.roomId)).valueOrNull ?? const [];
    final rounds =
        ref.watch(roundsProvider(widget.roomId)).valueOrNull ?? const [];
    final summaryAsync = ref.watch(_summaryProvider(widget.roomId));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Errore: $e',
          style: bodyFont(color: AppColors.destructive),
        ),
      ),
      data: (summary) {
        final stats = _computeStats(
          players: players,
          rounds: rounds,
          votes: summary.votes,
          questions: summary.questions,
        );

        return Stack(
          children: [
            _ScoreboardBody(
              stats: stats,
              sharingRoundIds: _sharingRoundIds,
              onShareRound: _onShareRound,
              onPlayAgain: () => context.go('/'),
            ),
            // Deterministic per-room so revisiting doesn't re-roll.
            Positioned.fill(
              child: ConfettiBurst(seed: widget.roomId),
            ),
          ],
        );
      },
    );
  }

  /// Renders a [RoundShareCard] off-screen in an [OverlayEntry], waits for
  /// its emoji images to finish loading, captures it to PNG and hands the
  /// bytes to the native share sheet.
  Future<void> _onShareRound(
    _RoundStats round, {
    Rect? sharePositionOrigin,
  }) async {
    if (_sharingRoundIds.contains(round.roundId)) return;
    setState(() => _sharingRoundIds.add(round.roundId));

    final overlayState = Overlay.of(context, rootOverlay: true);
    final boundaryKey = GlobalKey();

    final card = RoundShareCard(
      roundNumber: round.number,
      question: round.question,
      winners: round.winners
          .map((w) => ShareCardWinner(
                name: w.name,
                initials: _initials(w.name),
                color: w.color,
              ))
          .toList(growable: false),
      maxVotes: round.maxVotes,
      totalVotes: round.totalVotes,
      caption: round.caption,
    );

    // Wrap in Material so text has a default direction / baseline and
    // position way off-screen so users never see the capture build.
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: -10000,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(key: boundaryKey, child: card),
        ),
      ),
    );
    overlayState.insert(entry);

    try {
      // Give Twemoji images time to fetch + paint. A single post-frame
      // callback is not enough when images come from the network.
      await _waitForPaint();
      await Future<void>.delayed(const Duration(milliseconds: 550));

      final caption = _shareCaption(round);
      await ref.read(shareServiceProvider).sharePng(
            boundaryKey: boundaryKey,
            caption: caption,
            filename: 'vota-amici-round-${round.number}.png',
            sharePositionOrigin: sharePositionOrigin,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Condivisione fallita: $e')),
      );
    } finally {
      entry.remove();
      if (mounted) {
        setState(() => _sharingRoundIds.remove(round.roundId));
      }
    }
  }

  Future<void> _waitForPaint() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        completer.complete();
      });
    });
    return completer.future;
  }

  String _shareCaption(_RoundStats r) {
    final names = r.winners.map((w) => w.name).join(', ');
    final stripped = _stripQuestion(r.question);
    if (names.isEmpty) {
      return '🎭 Round ${r.number}: $stripped? ...nessuno!';
    }
    return '🎭 $stripped: $names! 🏆\nScopri cosa pensano di te gli amici:';
  }
}

// ---------------------------------------------------------------------------
// Presentation — kept as stateless widgets so the stateful shell above stays
// focused on share orchestration.
// ---------------------------------------------------------------------------

class _ScoreboardBody extends StatelessWidget {
  const _ScoreboardBody({
    required this.stats,
    required this.sharingRoundIds,
    required this.onShareRound,
    required this.onPlayAgain,
  });

  final _ScoreboardStats stats;
  final Set<String> sharingRoundIds;
  final Future<void> Function(_RoundStats, {Rect? sharePositionOrigin})
      onShareRound;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final hasRounds = stats.rounds.isNotEmpty;
    return PopIn(
      child: Column(
        children: [
          const _Hero(),
          const SizedBox(height: 16),
          if (stats.champion != null) _ChampionCard(champion: stats.champion!),
          if (stats.podium.length >= 2) ...[
            const SizedBox(height: 12),
            _Podium(podium: stats.podium),
          ],
          const SizedBox(height: 20),
          if (hasRounds) ...[
            const _SectionLabel(
              icon: '🎞️',
              text: 'Round per round',
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: hasRounds
                ? ListView.separated(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: stats.rounds.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final r = stats.rounds[i];
                      return _RoundCard(
                        round: r,
                        sharing: sharingRoundIds.contains(r.roundId),
                        onShare: (origin) =>
                            onShareRound(r, sharePositionOrigin: origin),
                      );
                    },
                  )
                : Center(
                    child: Text(
                      'Nessun round registrato.',
                      style: bodyFont(color: AppColors.mutedFg),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 320,
            child: ElevatedButton(
              onPressed: onPlayAgain,
              child: const EmojiText('🎮 Nuova Partita'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Floater(
          child: EmojiText('🏆', style: bodyFont(fontSize: 56)),
        ),
        const SizedBox(height: 6),
        Text(
          'Classifica Finale',
          style: displayFont(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: 4),
        EmojiText(
          'Ecco cosa pensano i tuoi amici 👀',
          textAlign: TextAlign.center,
          style: bodyFont(
            color: AppColors.mutedFg,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.text});
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: EmojiText(
        '$icon  $text',
        style: displayFont(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.mutedFg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ChampionCard extends StatelessWidget {
  const _ChampionCard({required this.champion});
  final _PlayerStats champion;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(champion.name);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.yellow.withValues(alpha: 0.95),
            AppColors.orange.withValues(alpha: 0.95),
          ],
        ),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: champion.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: displayFont(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EmojiText(
                  '👑 MVP della serata',
                  style: bodyFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.9),
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  champion.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: displayFont(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                EmojiText(
                  '🏆 ${champion.wins} ${champion.wins == 1 ? 'round vinto' : 'round vinti'} · '
                  '🗳️ ${champion.totalVotes} ${champion.totalVotes == 1 ? 'voto' : 'voti'}',
                  style: bodyFont(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.podium});
  final List<_PlayerStats> podium;

  @override
  Widget build(BuildContext context) {
    // Renders up to 3 slots, 2nd / 1st / 3rd, with bar heights tied to
    // wins so the lead is visually obvious.
    final maxWins = podium.fold<int>(0, (a, b) => b.wins > a ? b.wins : a);
    final first = podium.isNotEmpty ? podium[0] : null;
    final second = podium.length > 1 ? podium[1] : null;
    final third = podium.length > 2 ? podium[2] : null;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _PodiumSlot(
              player: second,
              rank: 2,
              medal: '🥈',
              maxWins: maxWins,
              barColor: AppColors.secondary,
            ),
          ),
          Expanded(
            child: _PodiumSlot(
              player: first,
              rank: 1,
              medal: '🥇',
              maxWins: maxWins,
              barColor: AppColors.yellow,
              elevated: true,
            ),
          ),
          Expanded(
            child: _PodiumSlot(
              player: third,
              rank: 3,
              medal: '🥉',
              maxWins: maxWins,
              barColor: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({
    required this.player,
    required this.rank,
    required this.medal,
    required this.maxWins,
    required this.barColor,
    this.elevated = false,
  });

  final _PlayerStats? player;
  final int rank;
  final String medal;
  final int maxWins;
  final Color barColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final p = player;
    // Bar height proportional to wins — 1st place caps at 80px, floors at
    // 30px so even a "0 wins" slot reads as a podium step and not a line.
    final ratio = (maxWins == 0 || p == null) ? 0.0 : (p.wins / maxWins);
    final barHeight = 30 + (ratio * 50);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (p != null) ...[
          EmojiText(medal, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Container(
            width: elevated ? 52 : 44,
            height: elevated ? 52 : 44,
            decoration: BoxDecoration(
              color: p.color,
              shape: BoxShape.circle,
              boxShadow: elevated
                  ? [
                      BoxShadow(
                        color: AppColors.yellow.withValues(alpha: 0.5),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(p.name),
              style: displayFont(
                fontSize: elevated ? 16 : 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: displayFont(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
          Text(
            '${p.wins} ${p.wins == 1 ? 'win' : 'wins'}',
            style: bodyFont(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.mutedFg,
            ),
          ),
          const SizedBox(height: 4),
        ] else ...[
          const SizedBox(height: 76),
          Text(
            '—',
            style: displayFont(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.mutedFg,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: p == null ? AppColors.muted : barColor.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$rank',
            style: displayFont(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: p == null ? AppColors.mutedFg : Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundCard extends StatefulWidget {
  const _RoundCard({
    required this.round,
    required this.sharing,
    required this.onShare,
  });
  final _RoundStats round;
  final bool sharing;
  final Future<void> Function(Rect? sharePositionOrigin) onShare;

  @override
  State<_RoundCard> createState() => _RoundCardState();
}

class _RoundCardState extends State<_RoundCard> {
  final GlobalKey _shareAnchorKey = GlobalKey();

  Rect? _anchorRect() {
    final ctx = _shareAnchorKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final pos = box.localToGlobal(Offset.zero);
    return pos & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.round;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RankPill(number: r.number),
              const Spacer(),
              IconButton(
                key: _shareAnchorKey,
                tooltip: 'Condividi questo risultato',
                onPressed: widget.sharing
                    ? null
                    : () => widget.onShare(_anchorRect()),
                icon: widget.sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.ios_share_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: EmojiText(
              r.question,
              style: displayFont(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.foreground,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (r.winners.isEmpty)
            EmojiText(
              '🤷 Nessun voto',
              style: bodyFont(
                fontWeight: FontWeight.w700,
                color: AppColors.mutedFg,
              ),
            )
          else
            _WinnerStrip(round: r),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: EmojiText(
              r.caption,
              style: bodyFont(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WinnerStrip extends StatelessWidget {
  const _WinnerStrip({required this.round});
  final _RoundStats round;

  @override
  Widget build(BuildContext context) {
    // Single-winner → avatar + name + vote bar.
    // Multi-winner (tie) → horizontal wrap of mini avatars + shared count.
    if (round.winners.length == 1) {
      final w = round.winners.first;
      final pct = round.totalVotes == 0
          ? 0.0
          : round.maxVotes / round.totalVotes;
      return Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: w.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: w.color.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(w.name),
              style: displayFont(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.name,
                  style: displayFont(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                _VoteBar(ratio: pct, color: w.color),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${round.maxVotes}/${round.totalVotes}',
              style: bodyFont(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.mutedFg,
              ),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final w in round.winners)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: w.color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(w.name),
                  style: displayFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                w.name,
                style: displayFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            '${round.maxVotes} voti ciascuno',
            style: bodyFont(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.mutedFg,
            ),
          ),
        ),
      ],
    );
  }
}

class _VoteBar extends StatelessWidget {
  const _VoteBar({required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          Container(
            height: 8,
            color: AppColors.muted,
          ),
          FractionallySizedBox(
            widthFactor: ratio.clamp(0.02, 1.0),
            child: Container(height: 8, color: color),
          ),
        ],
      ),
    );
  }
}

class _RankPill extends StatelessWidget {
  const _RankPill({required this.number});
  final int number;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'ROUND $number',
        style: bodyFont(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats derivation
// ---------------------------------------------------------------------------

class _ScoreboardStats {
  const _ScoreboardStats({
    required this.rounds,
    required this.podium,
    required this.champion,
  });
  final List<_RoundStats> rounds;
  final List<_PlayerStats> podium;
  final _PlayerStats? champion;
}

class _RoundStats {
  _RoundStats({
    required this.roundId,
    required this.number,
    required this.question,
    required this.winners,
    required this.maxVotes,
    required this.totalVotes,
    required this.caption,
  });
  final String roundId;
  final int number;
  final String question;
  final List<_PlayerStats> winners;
  final int maxVotes;
  final int totalVotes;
  final String caption;
}

class _PlayerStats {
  const _PlayerStats({
    required this.id,
    required this.name,
    required this.color,
    required this.wins,
    required this.totalVotes,
  });
  final String id;
  final String name;
  final Color color;
  final int wins;
  final int totalVotes;
}

_ScoreboardStats _computeStats({
  required List<Player> players,
  required List<Round> rounds,
  required List<Vote> votes,
  required Map<String, String> questions,
}) {
  // Player bookkeeping — wins (rounds won outright or tied) + total votes.
  final winCounts = <String, int>{for (final p in players) p.id: 0};
  final voteCounts = <String, int>{for (final p in players) p.id: 0};

  final sortedRounds = [...rounds]
    ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));

  final playerIndex = {
    for (var i = 0; i < players.length; i++) players[i].id: i,
  };
  final playerById = {for (final p in players) p.id: p};

  final roundStats = <_RoundStats>[];
  for (final r in sortedRounds) {
    final thisRoundVotes = <String, int>{};
    var total = 0;
    for (final v in votes.where((v) => v.roundId == r.id)) {
      thisRoundVotes[v.votedForId] = (thisRoundVotes[v.votedForId] ?? 0) + 1;
      voteCounts[v.votedForId] = (voteCounts[v.votedForId] ?? 0) + 1;
      total++;
    }
    final maxV =
        thisRoundVotes.values.fold<int>(0, (a, b) => b > a ? b : a);
    final winnerIds = thisRoundVotes.entries
        .where((e) => e.value == maxV && e.value > 0)
        .map((e) => e.key)
        .toList();

    for (final id in winnerIds) {
      winCounts[id] = (winCounts[id] ?? 0) + 1;
    }

    final winnerStats = <_PlayerStats>[];
    for (final id in winnerIds) {
      final p = playerById[id];
      if (p == null) continue;
      winnerStats.add(_PlayerStats(
        id: p.id,
        name: p.name,
        color: playerColor(playerIndex[p.id] ?? 0),
        // wins/totalVotes are filled in per-player below; per-round we only
        // care about the name + color.
        wins: 0,
        totalVotes: 0,
      ));
    }

    roundStats.add(_RoundStats(
      roundId: r.id,
      number: r.roundNumber,
      question: questions[r.questionId] ?? '',
      winners: winnerStats,
      maxVotes: maxV,
      totalVotes: total,
      caption: _captionFor(
        maxVotes: maxV,
        totalVotes: total,
        winnerCount: winnerIds.length,
      ),
    ));
  }

  // Build player stats sorted by wins DESC, then total votes DESC.
  final stats = players.map((p) {
    return _PlayerStats(
      id: p.id,
      name: p.name,
      color: playerColor(playerIndex[p.id] ?? 0),
      wins: winCounts[p.id] ?? 0,
      totalVotes: voteCounts[p.id] ?? 0,
    );
  }).toList()
    ..sort((a, b) {
      final c = b.wins.compareTo(a.wins);
      if (c != 0) return c;
      return b.totalVotes.compareTo(a.totalVotes);
    });

  final podium = stats.take(3).toList();
  // "Champion" only makes sense when someone is clearly ahead — a three-
  // way dead heat would be misleading to call MVP.
  _PlayerStats? champion;
  if (podium.isNotEmpty &&
      podium.first.wins > 0 &&
      (podium.length < 2 || podium.first.wins > podium[1].wins)) {
    champion = podium.first;
  }

  return _ScoreboardStats(
    rounds: roundStats,
    podium: podium,
    champion: champion,
  );
}

String _captionFor({
  required int maxVotes,
  required int totalVotes,
  required int winnerCount,
}) {
  if (totalVotes == 0 || winnerCount == 0) return '🤷 Nessun voto in questo round';
  if (winnerCount >= 3) return '🤔 Pareggio a $winnerCount — nessuno si decide!';
  if (winnerCount == 2) return '🔥 Testa a testa — $maxVotes voti ciascuno';
  if (maxVotes == totalVotes && totalVotes >= 3) {
    return '💯 Unanimità! Tutti d\'accordo';
  }
  final ratio = maxVotes / totalVotes;
  if (ratio >= 0.66) return '💥 Vittoria schiacciante — $maxVotes su $totalVotes';
  if (maxVotes == 1) return '👀 Un solo voto decisivo';
  return '🏆 Vittoria con $maxVotes su $totalVotes voti';
}

String _initials(String name) {
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

// ---------------------------------------------------------------------------
// Historic-vote fetch — keyed by roomId only so Riverpod reuses the future.
// ---------------------------------------------------------------------------

class _EndSummary {
  _EndSummary({required this.votes, required this.questions});
  final List<Vote> votes;
  final Map<String, String> questions;
}

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
