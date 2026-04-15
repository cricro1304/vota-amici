import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/question.dart';
import '../services/dev_bot_service.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/emoji_text.dart';
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
  // Default to Light + Neutro. Spicy is opt-in (and currently has no
  // seeded questions — the picker shows it but users have to actively
  // toggle it on).
  final Set<QuestionMode> _selectedModes = {
    QuestionMode.light,
    QuestionMode.neutro,
  };

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
    if (_selectedModes.isEmpty) {
      return _err(GameException('Scegli almeno una modalità di gioco!'));
    }
    setState(() => _loading = true);
    try {
      final res = await ref.read(gameServiceProvider).createRoom(
            hostName: name,
            timerSeconds: _timerEnabled ? 10 : null,
            modes: _selectedModes.toList(growable: false),
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
      // Refresh-to-rejoin: if this browser already has a playerId cached
      // for this room code, pass it so joinRoom can reuse it. Without this,
      // the user would get a brand-new player row every time they re-enter
      // the code from the home screen.
      //
      // This is ALSO what fixes the cross-browser-same-name bug: identity
      // now lives in SharedPreferences per browser, not in the name — so a
      // second browser typing the same name has no cached id and correctly
      // creates a distinct player.
      final session = ref.read(sessionServiceProvider);
      final cachedId = session.getPlayerId(code); // sync — reads from prefs
      final res = await ref.read(gameServiceProvider).joinRoom(
            roomCode: code,
            playerName: name,
            existingPlayerId: cachedId,
          );
      await session.setPlayerId(res.room.code, res.player.id);
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
                  const EmojiText('🎭', style: TextStyle(fontSize: 64)),
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
                  EmojiText(
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
                child: const EmojiText('🏠 Crea Stanza'),
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
                child: const EmojiText('🚪 Unisciti'),
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
              _ModePicker(
                selected: _selectedModes,
                onToggle: (mode) => setState(() {
                  if (_selectedModes.contains(mode)) {
                    _selectedModes.remove(mode);
                  } else {
                    _selectedModes.add(mode);
                  }
                }),
              ),
              const SizedBox(height: 10),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: _toggleRow(
                  label: '⏱️ Timer 10 secondi',
                  value: _timerEnabled,
                  onChanged: (v) => setState(() => _timerEnabled = v),
                ),
              ),
              // Dev-only: bot seeding + auto-start. Hidden in release builds
              // so end users never see the toggle.
              if (kDebugMode) ...[
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
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _create,
                child: EmojiText(_loading ? '⏳ Creando...' : '🎮 Crea Partita'),
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
            child: EmojiText(
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
                child: EmojiText(_loading ? '⏳ Entrando...' : '🚀 Entra'),
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

/// Multi-select chip row for choosing question modes when creating a room.
/// Mirrors the "Modalità di gioco" section on the landing page so the UX
/// vocabulary is consistent.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.selected, required this.onToggle});

  final Set<QuestionMode> selected;
  final ValueChanged<QuestionMode> onToggle;

  static const List<({QuestionMode mode, String emoji, String label})>
      _options = [
    (mode: QuestionMode.light, emoji: '🌸', label: 'Light'),
    (mode: QuestionMode.neutro, emoji: '🎯', label: 'Neutro'),
    (mode: QuestionMode.spicy, emoji: '🌶️', label: 'Spicy'),
  ];

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmojiText(
            '🎲 Modalità di gioco',
            style: bodyFont(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scegli quali domande includere',
            style: bodyFont(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.mutedFg,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final opt in _options)
                _ModeChip(
                  emoji: opt.emoji,
                  label: opt.label,
                  selected: selected.contains(opt.mode),
                  onTap: () => onToggle(opt.mode),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primary : AppColors.muted;
    final fg = selected ? Colors.white : AppColors.mutedFg;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: EmojiText(
            '$emoji $label',
            style: bodyFont(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
