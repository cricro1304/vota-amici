import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
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
      // Stamp the persistent browser fingerprint on the host row so a
      // later rejoin from this same browser (after clearing the per-room
      // cache or coming in via a different URL origin) can recover us
      // without creating a duplicate host player.
      final session = ref.read(sessionServiceProvider);
      // `pack.dbId` is non-null for every playable catalog entry (see
      // Pack.catalog); the `pack == null` guard above plus the
      // `!pack.isPlayable` branch in `_onPackTap` means we can't reach
      // here with a pack that has no DB row. The `!` is load-bearing —
      // if it ever fires we want to crash rather than silently create a
      // pack-less room.
      final res = await ref.read(gameServiceProvider).createRoom(
            hostName: name,
            timerSeconds: _timerEnabled ? 10 : null,
            modes: _selectedModes.toList(growable: false),
            packId: pack.dbId!,
            browserId: session.browserId(),
          );
      await session.setPlayerId(res.room.code, res.player.id);

      if (_devMode) {
        // Spawn bots + auto-start the game. Cap by the pack's own
        // `maxPlayers` when set — couples is 2-player-only, so blindly
        // seeding 3 bots makes the room reject everyone past the second
        // and breaks the agree/cross/self reveal taxonomy which assumes
        // exactly 2 voters. For unlimited packs (classic) we keep the
        // 3-bot default which gives a decent feel for the voting UI.
        final botCount = pack.maxPlayers != null
            ? (pack.maxPlayers! - 1).clamp(0, 5)
            : 3;
        if (botCount > 0) {
          await ref.read(devBotServiceProvider).seedBots(
                roomId: res.room.id,
                count: botCount,
              );
        }
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
      // Rejoin priority in the service layer:
      //   (1) cached per-room playerId (this branch — fastest)
      //   (2) browser fingerprint (covers cache-cleared / origin-swap cases)
      //   (3) fresh create with an auto-suffixed name if someone else in
      //       the lobby already picked it
      // We pass both signals here and let joinRoom pick the first that
      // matches. Distinct-name is handled server-side via (3) — two
      // browsers both typing "Alex" now produce "Alex" + "Alex (2)" rather
      // than two indistinguishable lobby chips.
      final session = ref.read(sessionServiceProvider);
      final cachedId = session.getPlayerId(code); // sync — reads from prefs
      final res = await ref.read(gameServiceProvider).joinRoom(
            roomCode: code,
            playerName: name,
            existingPlayerId: cachedId,
            browserId: session.browserId(),
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

  Widget _buildHero() {
    // When a couples pack is selected we swap the hero for a
    // romance-themed version so the whole create step reads as
    // "game for two" instead of "game with friends". We only do this
    // in `_Mode.create` — on `_Mode.home` there's no selected pack yet
    // and we don't want to prejudge which pack the user will pick.
    final isCouplesCreate = _mode == _Mode.create &&
        _selectedPack?.kind == PackKind.couples;
    if (isCouplesCreate) {
      return const _CouplesHero();
    }
    return PopIn(
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
  }

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
            // Dev-only: bot seeding + auto-start. Shown in local debug runs
            // AND on Vercel preview deploys (via --dart-define=ENABLE_DEV_MODE)
            // so we can click through a game alone, but hidden in production.
            if (kDebugMode || kEnableDevMode) ...[
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
              // Couples gets warmer copy — this button literally starts
              // a 2-person game, "Crea Partita" reads too utilitarian
              // for the "how well do you know each other" framing.
              child: EmojiText(
                _loading
                    ? '⏳ Creando...'
                    : (pack.kind == PackKind.couples
                        ? '💕 Inizia la sfida'
                        : '🎮 Crea Partita'),
              ),
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

/// Hero block shown on the create step when the Coppie pack is
/// selected. Swaps the theater-mask emoji + "amici" copy for a
/// couples-framed version: floating hearts, a 💑 centerpiece, and
/// framing that reads as "game for two" rather than "party game".
class _CouplesHero extends StatelessWidget {
  const _CouplesHero();

  @override
  Widget build(BuildContext context) {
    return PopIn(
      child: Column(
        children: [
          // Reuse the existing lobby decoration for visual continuity
          // — the same cluster of floating hearts the non-host sees
          // while waiting. Sizing/layout identical; this is a pure
          // vibe swap, not a new animation.
          const _HomeCouplesDecoration(),
          const SizedBox(height: 6),
          Text(
            'Quanto vi conoscete?',
            textAlign: TextAlign.center,
            style: displayFont(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          EmojiText(
            'Scopri cosa pensa davvero il tuo partner 💕',
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
  }
}

/// Home-screen variant of the floating-hearts cluster. Kept inline
/// (instead of re-using `_CouplesWaitingDecoration` from the lobby)
/// because the two screens have different size/spacing budgets — the
/// home hero runs wider and taller, and tying them together would
/// mean either shrinking the home hero or stretching the lobby one.
class _HomeCouplesDecoration extends StatelessWidget {
  const _HomeCouplesDecoration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Positioned(
            left: 20,
            top: 8,
            child: _HomeFloatingHeart(emoji: '💕', size: 26, phaseMs: 0),
          ),
          Positioned(
            right: 22,
            top: 2,
            child: _HomeFloatingHeart(emoji: '💗', size: 22, phaseMs: 500),
          ),
          Positioned(
            left: 6,
            bottom: 14,
            child: _HomeFloatingHeart(emoji: '💖', size: 24, phaseMs: 1100),
          ),
          Positioned(
            right: 10,
            bottom: 6,
            child: _HomeFloatingHeart(emoji: '💘', size: 20, phaseMs: 1700),
          ),
          Positioned(
            right: 90,
            top: 0,
            child: _HomeFloatingHeart(emoji: '✨', size: 16, phaseMs: 2200),
          ),
          Floater(
            child: EmojiText('💑', style: TextStyle(fontSize: 64)),
          ),
        ],
      ),
    );
  }
}

/// Local copy of the lobby's `_FloatingHeart` — same behaviour,
/// different file scope. Duplicating is cheaper than promoting the
/// widget to a shared module for two callsites that may well want to
/// diverge visually (they're already sized differently).
class _HomeFloatingHeart extends StatefulWidget {
  const _HomeFloatingHeart({
    required this.emoji,
    required this.size,
    required this.phaseMs,
  });

  final String emoji;
  final double size;
  final int phaseMs;

  @override
  State<_HomeFloatingHeart> createState() => _HomeFloatingHeartState();
}

class _HomeFloatingHeartState extends State<_HomeFloatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.phaseMs), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Opacity(
          opacity: 0.55 + 0.45 * t,
          child: Transform.translate(
            offset: Offset(0, -6 * t),
            child: Transform.scale(
              scale: 0.85 + 0.2 * t,
              child: child,
            ),
          ),
        );
      },
      child: EmojiText(
        widget.emoji,
        style: TextStyle(fontSize: widget.size),
      ),
    );
  }
}
