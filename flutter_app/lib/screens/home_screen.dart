import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return _err('Inserisci il tuo nome!');
    setState(() => _loading = true);
    try {
      final res = await ref.read(gameServiceProvider).createRoom(
            hostName: name,
            timerSeconds: _timerEnabled ? 10 : null,
          );
      await ref
          .read(sessionServiceProvider)
          .setPlayerId(res.room.code, res.player.id);
      if (mounted) context.go('/room/${res.room.code}');
    } on GameException catch (e) {
      _err(e.message);
    } catch (_) {
      _err('Errore nella creazione della stanza');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (name.isEmpty) return _err('Inserisci il tuo nome!');
    if (code.isEmpty) return _err('Inserisci il codice stanza!');
    setState(() => _loading = true);
    try {
      final res = await ref
          .read(gameServiceProvider)
          .joinRoom(roomCode: code, playerName: name);
      await ref
          .read(sessionServiceProvider)
          .setPlayerId(res.room.code, res.player.id);
      if (mounted) context.go('/room/${res.room.code}');
    } on GameException catch (e) {
      _err(e.message);
    } catch (_) {
      _err("Errore nell'unirsi alla stanza");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameLayout(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎭', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 12),
          const Text(
            'Chi è il più...?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Scopri cosa pensano davvero di te i tuoi amici 👀',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_mode == _Mode.home) _buildHomeButtons(),
          if (_mode == _Mode.create) _buildCreateForm(),
          if (_mode == _Mode.join) _buildJoinForm(),
        ],
      ),
    );
  }

  Widget _buildHomeButtons() => Column(
        children: [
          SizedBox(
            width: 280,
            child: ElevatedButton(
              onPressed: () => setState(() => _mode = _Mode.create),
              child: const Text('🏠 Crea Stanza'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 280,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
              ),
              onPressed: () => setState(() => _mode = _Mode.join),
              child: const Text('🚪 Unisciti'),
            ),
          ),
        ],
      );

  Widget _buildCreateForm() => SizedBox(
        width: 320,
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              textAlign: TextAlign.center,
              maxLength: 20,
              decoration: const InputDecoration(
                hintText: 'Il tuo nome',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '⏱️ Timer 10 secondi',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Switch(
                      value: _timerEnabled,
                      onChanged: (v) => setState(() => _timerEnabled = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
      );

  Widget _buildJoinForm() => SizedBox(
        width: 320,
        child: Column(
          children: [
            TextField(
              controller: _codeCtrl,
              textAlign: TextAlign.center,
              maxLength: 5,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
              ),
              decoration: const InputDecoration(
                hintText: 'Codice stanza',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              textAlign: TextAlign.center,
              maxLength: 20,
              decoration: const InputDecoration(
                hintText: 'Il tuo nome',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
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
      );
}
