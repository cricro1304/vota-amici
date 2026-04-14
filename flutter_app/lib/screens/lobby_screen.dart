import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/game_layout.dart';
import '../widgets/player_avatar.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({
    super.key,
    required this.roomId,
    required this.playerId,
  });

  final String roomId;
  final String playerId;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _starting = false;

  Future<void> _start(int playerCount) async {
    if (_starting) return; // Prevent double-fire from manual click + auto-start.
    if (playerCount < kMinPlayersToStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servono almeno 3 giocatori!')),
      );
      return;
    }
    _starting = true;
    try {
      await ref.read(gameServiceProvider).startGame(widget.roomId);
    } catch (e) {
      _starting = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is GameException ? e.message : 'Errore: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(roomProvider(widget.roomId)).valueOrNull;
    final players =
        ref.watch(playersProvider(widget.roomId)).valueOrNull ?? const [];
    if (room == null) return const SizedBox.shrink();

    final isHost = room.hostPlayerId == widget.playerId;
    final hasBots = players.any((p) => p.name.startsWith('Bot '));

return PopIn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasBots)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.winner.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '🧪 Dev mode attivo — i bot giocheranno da soli',
                textAlign: TextAlign.center,
                style: bodyFont(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.foreground,
                ),
              ),
            ),
          SoftCard(
            child: Column(
              children: [
                Text(
                  'CODICE STANZA',
                  style: bodyFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: AppColors.mutedFg,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  room.code,
                  style: displayFont(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 14,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Condividi questo codice con i tuoi amici!',
                  style: bodyFont(
                    fontSize: 12,
                    color: AppColors.mutedFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Giocatori (${players.length})',
            textAlign: TextAlign.center,
            style: displayFont(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 20,
            runSpacing: 16,
            children: [
              for (var i = 0; i < players.length; i++)
                PopIn(
                  delay: Duration(milliseconds: 50 * i),
                  child: Column(
                    children: [
                      PlayerAvatar(name: players[i].name, index: i),
                      const SizedBox(height: 6),
                      Text(
                        '${players[i].name}${players[i].isHost ? ' 👑' : ''}',
                        style: bodyFont(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: players[i].id == widget.playerId
                              ? AppColors.primary
                              : AppColors.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 40),
          if (isHost)
            ElevatedButton(
              onPressed: () => _start(players.length),
              child: const Text('🚀 Inizia Partita'),
            )
          else
            Column(
              children: [
                const Floater(child: Text('⏳', style: TextStyle(fontSize: 36))),
                const SizedBox(height: 8),
                Text(
                  "In attesa che l'host inizi la partita...",
                  textAlign: TextAlign.center,
                  style: bodyFont(
                    color: AppColors.mutedFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
