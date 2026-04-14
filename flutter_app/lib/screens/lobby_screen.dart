import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/player_avatar.dart';

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({
    super.key,
    required this.roomId,
    required this.playerId,
  });

  final String roomId;
  final String playerId;

  Future<void> _start(BuildContext context, WidgetRef ref, int playerCount) async {
    if (playerCount < kMinPlayersToStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servono almeno 3 giocatori!')),
      );
      return;
    }
    try {
      await ref.read(gameServiceProvider).startGame(roomId);
    } on GameException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomProvider(roomId)).valueOrNull;
    final players = ref.watch(playersProvider(roomId)).valueOrNull ?? const [];
    if (room == null) return const SizedBox.shrink();

    final isHost = room.hostPlayerId == playerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'CODICE STANZA',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  room.code,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Condividi questo codice con i tuoi amici!',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Giocatori (${players.length})',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            for (var i = 0; i < players.length; i++)
              Column(
                children: [
                  PlayerAvatar(name: players[i].name, index: i),
                  const SizedBox(height: 4),
                  Text(
                    '${players[i].name}${players[i].isHost ? ' 👑' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: players[i].id == playerId
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const Spacer(),
        if (isHost)
          ElevatedButton(
            onPressed: () => _start(context, ref, players.length),
            child: const Text('🚀 Inizia Partita'),
          )
        else
          const Column(
            children: [
              Text('⏳', style: TextStyle(fontSize: 30)),
              SizedBox(height: 8),
              Text(
                "In attesa che l'host inizi la partita...",
                textAlign: TextAlign.center,
              ),
            ],
          ),
      ],
    );
  }
}
