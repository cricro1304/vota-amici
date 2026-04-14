import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../services/dev_bot_service.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/game_layout.dart';

enum _Mode { home, create, join }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _Mode _mode = _Mode.home;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _timerEnabled = false;
  bool _devMode = false;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Show the *actual* error message so we can debug.
  void _err(Object e) {
    final msg = e is GameException ? e.message : 'Errore: $e';
    debugPrint('[home] $msg');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 6),
      ));
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return _err(GameException('Inserisci il tuo nome!'));
    setState(() => _loading = true);
    try {
      final res = await ref.read(gameServiceProvider).createRoom(
            hostName: name,
            timerSeconds: _timerEnabled ? 10 : null,
          );
      await ref
          .read(sessionServiceProvider)
          .setPlayerId(res.room.code, res.player.id);

      if (_devMode) {
        // Spawn bots + auto-start the game.
        await ref.read(devBotServiceProvider).seedBots(
              roomId: res.room.id,
              count: 3,
            );
      }

      if (mounted) context.go('/room/${res.room.code}');
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (name.isEmpty) return _err(GameException('Inserisci il tuo nome!'));
    if (code.isEmpty) return _err(GameException('Inserisci il codice!'));
    setState(() => _loading = true);
    try {
      final res = await ref
          .read(gameServiceProvider)
          .joinRoom(roomCode: code, playerName: name);
      await ref
          .read(sessionServiceProvider)
          .setPlayerId(res.room.code, res.player.id);
      if (mounted) context.go('/room/${res.room.code}');
    } catch (e) {
      _err(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameLayout(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            PopIn(
              child: Column(
                children: [
                  const Text('🎭', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 12),
                  Text(
                    'Chi è il più...?',
                    style: displayFont(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scopri cosa pensano davvero di te i tuoi amici 👀',
                    textAlign: TextAlign.center,
                    style: bodyFont(
                      color: AppColors.mutedFg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            if (_mode == _Mode.home) _buildHomeButtons(),
            if (_mode == _Mode.create) _buildCreateForm(),
            if (_mode == _Mode.join) _buildJoinForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeButtons() => PopIn(
        delay: const Duration(milliseconds: 100),
        child: Column(
          children: [
            SizedBox(
              width: 300,
              child: ElevatedButton(
                onPressed: () => setState(() => _mode = _Mode.create),
                child: const Text('🏠 Crea Stanza'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 300,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                ),
                onPressed: () => setState(() => _mode = _Mode.join),
                child: const Text('🚪 Unisciti'),
              ),
            ),
          ],
        ),
      );

  Widget _buildCreateForm() => PopIn(
        child: SizedBox(
          width: 320,
          child: Column(
            children: [
              TextField(
                controller: _nameCtrl,
                textAlign: TextAlign.center,
                maxLength: 20,
                style: displayFont(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: 'Il tuo nome',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: _toggleRow(
                  label: '⏱️ Timer 10 secondi',
                  value: _timerEnabled,
                  onChanged: (v) => setState(() => _timerEnabled = v),
                ),
              ),
              const SizedBox(height: 10),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: _toggleRow(
                  label: '🧪 Dev mode (test coi bot)',
                  value: _devMode,
                  onChanged: (v) => setState(() => _devMode = v),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _create,
                child: Text(_loading ? '⏳ Creando...' : '🎮 Crea Partita'),
              ),
              TextButton(
                onPressed: () => setState(() => _mode = _Mode.home),
                child: const Text('← Indietro'),
              ),
            ],
          ),
        ),
      );

  Widget _toggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: bodyFont(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      );

  Widget _buildJoinForm() => PopIn(
        child: SizedBox(
          width: 320,
          child: Column(
            children: [
              TextField(
                controller: _codeCtrl,
                textAlign: TextAlign.center,
                maxLength: 5,
                textCapitalization: TextCapitalization.characters,
                style: displayFont(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 10,
                ),
                decoration: const InputDecoration(
                  hintText: 'CODICE',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                textAlign: TextAlign.center,
                maxLength: 20,
                style: displayFont(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: 'Il tuo nome',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _join,
                child: Text(_loading ? '⏳ Entrando...' : '🚀 Entra'),
              ),
              TextButton(
                onPressed: () => setState(() => _mode = _Mode.home),
                child: const Text('← Indietro'),
              ),
            ],
          ),
        ),
      );
}
