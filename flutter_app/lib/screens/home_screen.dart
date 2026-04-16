import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/pack.dart';
import '../models/question.dart';
import '../services/dev_bot_service.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/emoji_text.dart';
import '../widgets/game_layout.dart';

/// Flow states for the home screen. The happy path is
/// `home → selectPack → create`; `join` is a parallel branch from `home`.
enum _Mode { home, selectPack, create, join }

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

  /// The pack the host picked on the `selectPack` step. Independent from
  /// [_selectedModes] — the pack narrows which *topic* the questions will
  /// be drawn from (Originale, Coppie, …) while the mode narrows the
  /// *tone* (light / neutro / spicy). Host can mix any combination.
  Pack? _selectedPack;

  /// Tone of questions included in the round. Default mirrors the original
  /// home-screen behaviour: Light + Neutro on, Spicy opt-in.
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

  void _info(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
      ));
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    final pack = _selectedPack;
    if (name.isEmpty) return _err(GameException('Inserisci il tuo nome!'));
    if (pack == null) {
      // Shouldn't be reachable — the UI only exposes `_create` after a pack
      // has been picked — but guard anyway so we fail loudly instead of
      // silently creating a room.
      return _err(GameException('Scegli prima un pacchetto!'));
    }
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

  void _onPackTap(Pack pack) {
    if (!pack.isPlayable) {
      final msg = pack.status == PackStatus.ageRestricted
          ? '🔞 Il pacchetto Spicy arriva presto!'
          : '🔜 Il pacchetto "${pack.title}" arriva presto!';
      _info(msg);
      return;
    }
    setState(() {
      _selectedPack = pack;
      _mode = _Mode.create;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameLayout(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            // Compact header on the pack-selection step so the list has
            // room to breathe; full hero on the other steps.
            if (_mode == _Mode.selectPack)
              _buildCompactHeader()
            else
              _buildHero(),
            const SizedBox(height: 24),
            if (_mode == _Mode.home) _buildHomeButtons(),
            if (_mode == _Mode.selectPack) _buildPackPicker(),
            if (_mode == _Mode.create) _buildCreateForm(),
            if (_mode == _Mode.join) _buildJoinForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() => PopIn(
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
      );

  Widget _buildCompactHeader() => PopIn(
        child: Column(
          children: [
            Text(
              'Scegli un pacchetto',
              style: displayFont(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 4),
            EmojiText(
              '🎲 Quale vibe vuoi stasera?',
              textAlign: TextAlign.center,
              style: bodyFont(
                color: AppColors.mutedFg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _buildHomeButtons() => PopIn(
        delay: const Duration(milliseconds: 100),
        child: Column(
          children: [
            SizedBox(
              width: 300,
              child: ElevatedButton(
                onPressed: () => setState(() => _mode = _Mode.selectPack),
                child: const EmojiText('🎮 Gioca Ora'),
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

  Widget _buildPackPicker() => PopIn(
        child: SizedBox(
          width: 360,
          child: Column(
            children: [
              for (final pack in Pack.catalog) ...[
                _PackCard(pack: pack, onTap: () => _onPackTap(pack)),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => setState(() => _mode = _Mode.home),
                child: const Text('← Indietro'),
              ),
            ],
          ),
        ),
      );

  Widget _buildCreateForm() {
    // _selectedPack is always set by the time we're on this step (see
    // `_onPackTap`), but belt & suspenders — fall back to Originale so we
    // never crash.
    final pack = _selectedPack ?? Pack.catalog.first;
    return PopIn(
      child: SizedBox(
        width: 320,
        child: Column(
          children: [
            _SelectedPackBadge(
              pack: pack,
              onChange: () => setState(() => _mode = _Mode.selectPack),
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
              onPressed: () => setState(() => _mode = _Mode.selectPack),
              child: const Text('← Cambia pacchetto'),
            ),
          ],
        ),
      ),
    );
  }

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

/// Single pack card in the selection list. Mirrors the `.pack-full` blocks
/// on `packs.html` — icon on the left, title + status tag + description on
/// the right. Unavailable packs are faded and show their "arrivo" tag.
class _PackCard extends StatelessWidget {
  const _PackCard({required this.pack, required this.onTap});

  final Pack pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = !pack.isPlayable;
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: SoftCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: pack.isPlayable
                        ? AppColors.primaryTint
                        : AppColors.muted,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: EmojiText(
                    pack.emoji,
                    style: const TextStyle(fontSize: 30),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              pack.title,
                              style: displayFont(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.foreground,
                              ),
                            ),
                          ),
                          _StatusTag(status: pack.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pack.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bodyFont(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pill showing the pack's availability — mirrors the
/// `.pack-tag.free` / `.pack-tag.soon` / `.spicy_18_tag` styles on the
/// landing page.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});
  final PackStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      PackStatus.available => (
          AppColors.accent.withValues(alpha: 0.18),
          AppColors.accent,
          '✅ Gratis',
        ),
      PackStatus.comingSoon => (
          AppColors.muted,
          AppColors.mutedFg,
          '🔜 In arrivo',
        ),
      PackStatus.ageRestricted => (
          AppColors.primary.withValues(alpha: 0.15),
          AppColors.primary,
          '🔞 18+',
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: EmojiText(
        label,
        style: bodyFont(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// Shown on top of the create form to make the chosen pack obvious, with
/// a one-tap shortcut back to the picker.
class _SelectedPackBadge extends StatelessWidget {
  const _SelectedPackBadge({required this.pack, required this.onChange});

  final Pack pack;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          EmojiText(pack.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pacchetto',
                  style: bodyFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.mutedFg,
                  ),
                ),
                Text(
                  pack.title,
                  style: displayFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: const Text('Cambia'),
          ),
        ],
      ),
    );
  }
}

/// Multi-select chip row for choosing question modes when creating a room.
/// Mirrors the "Modalità di gioco" section on the landing page so the UX
/// vocabulary is consistent. Orthogonal to [Pack] — the host picks the
/// topic (pack) *and* the tone (modes) independently.
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
