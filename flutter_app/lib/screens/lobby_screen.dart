import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/pack.dart';
import '../services/game_service.dart';
import '../state/providers.dart';
import '../widgets/emoji_text.dart';
import '../widgets/game_layout.dart';
import '../widgets/landing_widgets.dart';

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

/// Invite controls rendered under the room code in the lobby.
///
/// "Condividi" opens the native share sheet (covers link share + AirDrop on
/// iOS, the OS picker on Android, Web Share API on mobile browsers).
/// "Copia link" is a keyboard-friendly fallback for desktop users that don't
/// get a share sheet.
class _ShareRow extends ConsumerWidget {
  const _ShareRow({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share = ref.watch(shareServiceProvider);

    Future<void> onShare() async {
      try {
        // Anchor the iPad share popover to the button.
        final box = context.findRenderObject() as RenderBox?;
        final origin = box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size;
        await share.shareRoom(code: code, sharePositionOrigin: origin);
      } catch (_) {
        // If the share sheet isn't available (rare), fall back to clipboard.
        await share.copyLink(code);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copiato negli appunti')),
        );
      }
    }

    Future<void> onCopy() async {
      await share.copyLink(code);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copiato negli appunti')),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: onShare,
            child: const EmojiText('📤 Condividi link'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
            ),
            onPressed: onCopy,
            child: const EmojiText('🔗 Copia'),
          ),
        ),
      ],
    );
  }
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _starting = false;

  Future<void> _start(int playerCount, Pack pack) async {
    if (_starting) return; // Prevent double-fire from manual click + auto-start.
    if (playerCount < pack.minPlayers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pack.kind == PackKind.couples
              // Pack-specific message — for couples we know exactly who
              // is missing, and "almeno 2 giocatori" reads like an error.
              ? 'Aspetta il tuo partner per iniziare 💑'
              : 'Servono almeno ${pack.minPlayers} giocatori!'),
        ),
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
    final roomAsync = ref.watch(roomProvider(widget.roomId));
    final playersAsync = ref.watch(playersProvider(widget.roomId));
    final room = roomAsync.valueOrNull;
    final players = playersAsync.valueOrNull ?? const [];

    // Don't render a blank screen while the realtime stream is reconnecting
    // (e.g. the host's wifi blipped while waiting for players). Show a
    // visible "reconnecting" placeholder instead of SizedBox.shrink so the
    // user never sees a white page.
    if (room == null) {
      final hasError = roomAsync.hasError || playersAsync.hasError;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Floater(
              child: EmojiText(
                hasError ? '📡' : '⏳',
                style: const TextStyle(fontSize: 40),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              hasError
                  ? 'Connessione persa, riprovo…'
                  : 'Caricamento stanza…',
              textAlign: TextAlign.center,
              style: bodyFont(
                color: AppColors.mutedFg,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  // Force both streams to rebuild.
                  ref.invalidate(roomProvider(widget.roomId));
                  ref.invalidate(playersProvider(widget.roomId));
                },
                child: const Text('Riprova'),
              ),
            ],
          ],
        ),
      );
    }

    final isHost = room.hostPlayerId == widget.playerId;
    final hasBots = players.any((p) => p.name.startsWith('Bot '));
    final pack = Pack.byDbId(room.packId);
    final isCouples = pack.kind == PackKind.couples;

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
              child: EmojiText(
                '🧪 Dev mode attivo: i bot giocheranno da soli',
                textAlign: TextAlign.center,
                style: bodyFont(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.foreground,
                ),
              ),
            ),
          RoomCodeCard(code: room.code, label: 'CODICE STANZA'),
          const SizedBox(height: 10),
          Text(
            isCouples
                // Couples are typically sitting next to each other but
                // may want to play on two phones — mention the pack name
                // so the copy doesn't read as "invite your friends".
                ? 'Condividi questo codice con il tuo partner 💑'
                : 'Condividi questo codice con i tuoi amici!',
            textAlign: TextAlign.center,
            style: bodyFont(
              fontSize: 13,
              color: AppColors.mutedFg,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _ShareRow(code: room.code),
          const SizedBox(height: 28),
          Text(
            // For couples we show "(1/2)" / "(2/2)" so the lobby makes
            // the capacity constraint self-evident; for classic we keep
            // the open-ended count.
            isCouples
                ? 'Giocatori (${players.length}/${pack.maxPlayers ?? pack.minPlayers})'
                : 'Giocatori (${players.length})',
            textAlign: TextAlign.center,
            style: displayFont(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 14),
          // Vertical player list like the lobby mockup in landing-page.html.
          // Staggered PopIn so rows fade in one after the other (mirrors the
          // `tutPlayerJoin` keyframes).
          for (var i = 0; i < players.length; i++) ...[
            PopIn(
              delay: Duration(milliseconds: 80 * i),
              child: PlayerRow(
                name: players[i].name,
                index: i,
                isHost: players[i].isHost,
                isSelf: players[i].id == widget.playerId,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 24),
          if (isHost)
            ElevatedButton(
              onPressed: () => _start(players.length, pack),
              child: const EmojiText('🚀 Inizia Partita'),
            )
          else if (isCouples)
            // Couples waiting gets its own romance-themed decoration:
            // floating hearts around a central 💑 so the non-host half
            // of the couple doesn't stare at a plain hourglass while
            // the other is tapping Inizia Partita.
            Column(
              children: [
                const _CouplesWaitingDecoration(),
                const SizedBox(height: 10),
                Text(
                  'Il tuo partner sta per iniziare...',
                  textAlign: TextAlign.center,
                  style: bodyFont(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                EmojiText(
                  '✨ Preparatevi a scoprire quanto vi conoscete ✨',
                  textAlign: TextAlign.center,
                  style: bodyFont(
                    color: AppColors.mutedFg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                const Floater(
                    child: EmojiText('⏳', style: TextStyle(fontSize: 36))),
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

/// Decorative waiting state for the couples pack: a central 💑 that
/// floats gently, surrounded by four smaller hearts that each drift,
/// fade, and pulse on their own phase so the cluster never reads as
/// "in sync". Keeps the non-host partner entertained while waiting for
/// the host to hit Inizia Partita.
class _CouplesWaitingDecoration extends StatelessWidget {
  const _CouplesWaitingDecoration();

  @override
  Widget build(BuildContext context) {
    // Hearts picked for visual variety: different shapes/colours but
    // all "love" family so the vibe stays clearly romantic. Phase
    // offsets are staggered so they don't all rise together.
    return SizedBox(
      width: 220,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Positioned(
            left: 18,
            top: 8,
            child: _FloatingHeart(emoji: '💕', size: 22, phaseMs: 0),
          ),
          Positioned(
            right: 24,
            top: 4,
            child: _FloatingHeart(emoji: '💗', size: 18, phaseMs: 500),
          ),
          Positioned(
            left: 6,
            bottom: 18,
            child: _FloatingHeart(emoji: '💖', size: 20, phaseMs: 1100),
          ),
          Positioned(
            right: 14,
            bottom: 10,
            child: _FloatingHeart(emoji: '💘', size: 16, phaseMs: 1700),
          ),
          Positioned(
            left: 80,
            top: 0,
            child: _FloatingHeart(emoji: '✨', size: 14, phaseMs: 2200),
          ),
          // Big centerpiece — uses the shared Floater so the cadence
          // matches other "waiting" moments in the app.
          Floater(
            child: EmojiText('💑', style: TextStyle(fontSize: 58)),
          ),
        ],
      ),
    );
  }
}

/// Individual floating heart — a tiny looping controller with a phase
/// offset so each heart in [_CouplesWaitingDecoration] is out of sync.
/// Drives translation, opacity, AND scale so the motion reads as
/// organic rather than purely vertical.
class _FloatingHeart extends StatefulWidget {
  const _FloatingHeart({
    required this.emoji,
    required this.size,
    required this.phaseMs,
  });

  final String emoji;
  final double size;

  /// Delay before starting the loop. Lets us stagger sibling hearts so
  /// they don't all peak at the same instant — see
  /// [_CouplesWaitingDecoration].
  final int phaseMs;

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    // Delayed start rather than `_c.value = phase/duration` because
    // we want the *whole* loop to be offset, not just the first pass.
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
          // Fade from 55% → 100% over the loop so hearts seem to
          // "breathe" in and out of view.
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
