import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/player.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/game_layout.dart';
import '../widgets/player_avatar.dart';

class VotingScreen extends ConsumerStatefulWidget {
  const VotingScreen({
    super.key,
    required this.roomId,
    required this.playerId,
  });

  final String roomId;
  final String playerId;

  @override
  ConsumerState<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends ConsumerState<VotingScreen> {
  String? _selectedId;
  bool _submitting = false;
  String? _activeRoundId;
  int? _timeLeft;
  Timer? _timer;
  bool _timerExpired = false;
  bool _revealTriggered = false;

  void _resetForRound(String roundId, int? timerSeconds) {
    _activeRoundId = roundId;
    _selectedId = null;
    _submitting = false;
    _timerExpired = false;
    _revealTriggered = false;
    _timeLeft = timerSeconds;
    _timer?.cancel();
    if (timerSeconds != null && timerSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          if (_timeLeft == null) return;
          if (_timeLeft! <= 1) {
            _timeLeft = 0;
            _timer?.cancel();
          } else {
            _timeLeft = _timeLeft! - 1;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _vote(String votedForId, int totalPlayers) async {
    if (_submitting) return;
    final round = ref.read(currentRoundProvider(widget.roomId));
    if (round == null) return;
    setState(() {
      _selectedId = votedForId;
      _submitting = true;
    });
    try {
      await ref.read(gameServiceProvider).submitVote(
            roundId: round.id,
            voterId: widget.playerId,
            votedForId: votedForId,
          );
      await _maybeAutoReveal(totalPlayers);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is GameException ? e.message : 'Errore: $e')),
      );
      setState(() {
        _selectedId = null;
        _submitting = false;
      });
    }
  }

  Future<void> _maybeAutoReveal(int totalPlayers) async {
    if (_revealTriggered) return;
    final round = ref.read(currentRoundProvider(widget.roomId));
    if (round == null) return;
    final votes =
        ref.read(currentRoundVotesProvider(widget.roomId)).valueOrNull ??
            const [];
    // IMPORTANT: filter by round.id. When the round transitions, Riverpod's
    // StreamProvider keeps exposing the previous round's last value until the
    // new stream emits — without this filter we'd count stale votes and
    // instantly reveal the fresh round before anyone voted.
    final voterIds = votes
        .where((v) => v.roundId == round.id)
        .map((v) => v.voterId)
        .toSet();
    // Count self too — we may have optimistically selected but the vote
    // hasn't come back through the realtime stream yet.
    if (_selectedId != null) voterIds.add(widget.playerId);
    if (voterIds.length < totalPlayers) return;
    _revealTriggered = true;
    try {
      await ref.read(gameServiceProvider).revealResults(
            roundId: round.id,
            roomId: widget.roomId,
          );
    } catch (_) {
      // Idempotent — if another client already flipped status, ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(roomProvider(widget.roomId)).valueOrNull;
    final round = ref.watch(currentRoundProvider(widget.roomId));
    final players =
        ref.watch(playersProvider(widget.roomId)).valueOrNull ?? const [];
    final votesAsync = ref.watch(currentRoundVotesProvider(widget.roomId));
    final rawVotes = votesAsync.valueOrNull ?? const [];
    final question =
        ref.watch(currentQuestionTextProvider(widget.roomId)) ?? '';

    if (room == null || round == null) return const SizedBox.shrink();

    // Filter votes by round.id everywhere in build. When the round
    // transitions, Riverpod's StreamProvider keeps exposing the previous
    // round's last value until the new stream emits — for that one frame,
    // unfiltered votes belong to the *previous* round and would incorrectly
    // (a) trigger auto-reveal on the fresh round, and (b) mark the user as
    // already-voted.
    final votes = rawVotes.where((v) => v.roundId == round.id).toList();

    // Reset round-local state synchronously so the very first frame of a new
    // round renders with the full timer and a fresh ballot. Using a
    // post-frame callback here caused two bugs:
    //   1. First frame showed no timer at all.
    //   2. If another provider emitted before the callback fired, a second
    //      callback was scheduled and the timer got reset twice (flicker).
    if (_activeRoundId != round.id) {
      _resetForRound(round.id, room.timerSeconds);
    }

    // Reactive auto-reveal: whenever vote count reaches total players,
    // any client (not just the last voter) will fire the status flip.
    // This is what was missing when bots cast the final vote.
    final uniqueVoters = votes.map((v) => v.voterId).toSet();
    if (uniqueVoters.length >= players.length &&
        players.isNotEmpty &&
        !_revealTriggered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAutoReveal(players.length);
      });
    }

    if (_timeLeft == 0 && !_timerExpired) {
      _timerExpired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final alreadyVoted =
            votes.any((v) => v.voterId == widget.playerId) || _selectedId != null;
        if (!alreadyVoted && players.isNotEmpty) {
          final rnd = players[DateTime.now().microsecond % players.length];
          await _vote(rnd.id, players.length);
        } else {
          await _maybeAutoReveal(players.length);
        }
      });
    }

    final alreadyVotedInDb = votes.any((v) => v.voterId == widget.playerId);
    final alreadySubmitted = alreadyVotedInDb || _selectedId != null;
    final optimisticCount = alreadyVotedInDb
        ? votes.length
        : (_selectedId != null ? votes.length + 1 : votes.length);

    if (alreadySubmitted) {
      return _buildWaiting(optimisticCount, players.length);
    }

    return _buildBallot(
        players, room.currentRound, question, room.timerSeconds);
  }

  Widget _buildWaiting(int voted, int total) {
    return PopIn(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Floater(child: Text('✅', style: bodyFont(fontSize: 48))),
          const SizedBox(height: 16),
          Text(
            'Voto registrato!',
            style: displayFont(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'In attesa degli altri giocatori... ($voted/$total)',
            style: bodyFont(
              color: AppColors.mutedFg,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total > 0 ? voted / total : 0,
                minHeight: 10,
                backgroundColor: AppColors.muted,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBallot(List<Player> players, int roundNumber, String question,
      int? timerSeconds) {
    return PopIn(
      child: Column(
        children: [
          SoftCard(
            child: Column(
              children: [
                Text(
                  'ROUND $roundNumber',
                  style: bodyFont(
                    color: AppColors.mutedFg,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  question,
                  textAlign: TextAlign.center,
                  style: displayFont(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                if (_timeLeft != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '⏱️ ${_timeLeft}s',
                    style: displayFont(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: (_timeLeft ?? 0) <= 3
                          ? AppColors.destructive
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: timerSeconds != null && timerSeconds > 0
                            ? (_timeLeft ?? 0) / timerSeconds
                            : 0,
                        minHeight: 6,
                        backgroundColor: AppColors.muted,
                        color: (_timeLeft ?? 0) <= 3
                            ? AppColors.destructive
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.1,
              children: [
                for (var i = 0; i < players.length; i++)
                  _VoteTile(
                    name: players[i].name,
                    isSelf: players[i].id == widget.playerId,
                    index: i,
                    selected: _selectedId == players[i].id,
                    disabled: _submitting,
                    onTap: () => _vote(players[i].id, players.length),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoteTile extends StatelessWidget {
  const _VoteTile({
    required this.name,
    required this.index,
    required this.isSelf,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String name;
  final int index;
  final bool isSelf;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Shadow goes on the OUTER container; Material+InkWell clip the ripple
    // to rounded corners. Previously, putting boxShadow inside Ink while
    // wrapped in a transparent Material caused Flutter to render the shadow
    // on the unclipped bounding box — producing the square shadow halo
    // around the rounded card. This split is the canonical fix.
    return AnimatedScale(
      scale: selected ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 180),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: kCardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: disabled ? null : onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? Border.all(color: AppColors.primary, width: 4)
                    : null,
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PlayerAvatar(
                    name: name,
                    index: index,
                    size: AvatarSize.lg,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isSelf ? '$name (Tu)' : name,
                    textAlign: TextAlign.center,
                    style: bodyFont(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
