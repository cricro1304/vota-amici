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
          else
            Column(
              children: [
                const Floater(
                    child: EmojiText('⏳', style: TextStyle(fontSize: 36))),
                const SizedBox(height: 8),
                Text(
                  isCouples
                      ? "In attesa che il tuo partner inizi la partita..."
                      : "In attesa che l'host inizi la partita...",
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
