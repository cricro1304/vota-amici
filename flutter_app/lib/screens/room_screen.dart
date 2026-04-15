import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/room.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/emoji_text.dart';
import '../widgets/game_layout.dart';
import 'lobby_screen.dart';
import 'voting_screen.dart';
import 'results_screen.dart';
import 'end_screen.dart';

/// Resolves the room by code, handles the "no session — rejoin" state,
/// then delegates to the phase-specific screen.
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  String? _roomId;
  String? _playerId;
  bool _resolving = true;
  String? _resolveError;
  final _rejoinCtrl = TextEditingController();
  bool _rejoining = false;

  String get _normalized => widget.code.toUpperCase();

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _rejoinCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    if (!mounted) return;
    setState(() {
      _resolving = true;
      _resolveError = null;
    });
    final session = ref.read(sessionServiceProvider);
    final existingPlayerId = session.getPlayerId(_normalized);

    try {
      final room =
          await ref.read(roomRepositoryProvider).findRoomByCode(_normalized);
      if (!mounted) return;
      if (room == null) {
        context.go('/');
        return;
      }
      setState(() {
        _roomId = room.id;
        _playerId = existingPlayerId;
        _resolving = false;
      });
    } catch (e) {
      // Network error on initial room lookup (e.g. host's wifi dropped right
      // as they landed on the room URL). Don't redirect to home — just show
      // a retryable error state so they can recover without losing the URL.
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolveError = e.toString();
      });
    }
  }

  Future<void> _rejoin() async {
    final name = _rejoinCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _rejoining = true);
    try {
      final res = await ref.read(gameServiceProvider).joinRoom(
            roomCode: _normalized,
            playerName: name,
          );
      await ref
          .read(sessionServiceProvider)
          .setPlayerId(res.room.code, res.player.id);
      if (mounted) setState(() => _playerId = res.player.id);
    } on GameException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _rejoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const GameLayout(child: Center(child: EmojiText('🎲', style: TextStyle(fontSize: 32))));
    }

    if (_resolveError != null) {
      return GameLayout(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const EmojiText('📡', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 12),
              const Text(
                'Connessione persa',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Non riesco a caricare la stanza.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _resolve,
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }

    final playerId = _playerId;
    if (playerId == null) return _buildRejoin();

    final roomAsync = ref.watch(roomProvider(_roomId!));
    final room = roomAsync.valueOrNull;
    if (room == null) {
      return const GameLayout(child: Center(child: EmojiText('🎲', style: TextStyle(fontSize: 32))));
    }

    return GameLayout(
      child: switch (room.status) {
        RoomStatus.lobby =>
          LobbyScreen(roomId: _roomId!, playerId: playerId),
        RoomStatus.inRound =>
          VotingScreen(roomId: _roomId!, playerId: playerId),
        RoomStatus.results =>
          ResultsScreen(roomId: _roomId!, playerId: playerId),
        RoomStatus.finished =>
          EndScreen(roomId: _roomId!),
      },
    );
  }

  Widget _buildRejoin() => GameLayout(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const EmojiText('🔄', style: TextStyle(fontSize: 50)),
            const SizedBox(height: 16),
            const Text(
              'Rientra nella stanza',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Codice: $_normalized',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 280,
              child: TextField(
                controller: _rejoinCtrl,
                textAlign: TextAlign.center,
                maxLength: 20,
                decoration: const InputDecoration(
                  hintText: 'Il tuo nome',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 280,
              child: ElevatedButton(
                onPressed: _rejoining ? null : _rejoin,
                child: EmojiText(_rejoining ? '⏳ Entrando...' : '🚀 Entra'),
              ),
            ),
          ],
        ),
      );
}
