import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
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

  void _resetForRound(String roundId, int? timerSeconds) {
    _activeRoundId = roundId;
    _selectedId = null;
    _submitting = false;
    _timerExpired = false;
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
    } on GameException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      setState(() {
        _selectedId = null;
        _submitting = false;
      });
    }
  }

  Future<void> _maybeAutoReveal(int totalPlayers) async {
    final round = ref.read(currentRoundProvider(widget.roomId));
    final votes =
        ref.read(currentRoundVotesProvider(widget.roomId)).valueOrNull ?? [];
    if (round == null) return;
    final voterIds = votes.map((v) => v.voterId).toSet();
    // Include the vote we just submitted (stream may not have caught up).
    voterIds.add(widget.playerId);
    if (voterIds.length >= totalPlayers) {
      await ref.read(gameServiceProvider).revealResults(
            roundId: round.id,
            roomId: widget.roomId,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(roomProvider(widget.roomId)).valueOrNull;
    final round = ref.watch(currentRoundProvider(widget.roomId));
    final players = ref.watch(playersProvider(widget.roomId)).valueOrNull ?? const [];
    final votesAsync = ref.watch(currentRoundVotesProvider(widget.roomId));
    final votes = votesAsync.valueOrNull ?? const [];
    final question = ref.watch(currentQuestionTextProvider(widget.roomId));

    if (room == null || round == null) return const SizedBox.shrink();

    // Reset local state when the round changes.
    if (_activeRoundId != round.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _resetForRound(round.id, room.timerSeconds));
      });
    }

    // Timer expiration — submit a random vote if still pending.
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
    final alreadySubmitted =
        alreadyVotedInDb || _selectedId != null;
    final optimisticCount = alreadyVotedInDb
        ? votes.length
        : (_selectedId != null ? votes.length + 1 : votes.length);

    if (alreadySubmitted) {
      return _buildWaiting(optimisticCount, players.length);
    }

    return _buildBallot(players, room.currentRound, question ?? '', room.timerSeconds);
  }

  Widget _buildWaiting(int voted, int total) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('✅', style: TextStyle(fontSize: 50)),
        const SizedBox(height: 16),
        const Text(
          'Voto registrato!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text('In attesa degli altri giocatori... ($voted/$total)'),
        const SizedBox(height: 16),
        SizedBox(
          width: 280,
          child: LinearProgressIndicator(
            value: total > 0 ? voted / total : 0,
            minHeight: 10,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }

  Widget _buildBallot(
      List<Player> players, int roundNumber, String question, int? timerSeconds) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Text(
                  'ROUND $roundNumber',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  question,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
                if (_timeLeft != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '⏱️ ${_timeLeft}s',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: (_timeLeft ?? 0) <= 3
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: timerSeconds != null && timerSeconds > 0
                          ? (_timeLeft ?? 0) / timerSeconds
                          : 0,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
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
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 4)
              : null,
          boxShadow: const [
            BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PlayerAvatar(
              name: name,
              index: index,
              size: AvatarSize.lg,
              selected: selected,
            ),
            const SizedBox(height: 8),
            Text(
              isSelf ? '$name (Tu)' : name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
