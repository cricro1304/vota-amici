import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/connectivity_provider.dart';
import 'emoji_text.dart';

/// Gradient header + centered content column with max-width, mirroring
/// the web `GameLayout`. Also shows a connectivity banner at the top when
/// the device goes offline. so the host never sees a silently-dead lobby.
class GameLayout extends ConsumerWidget {
  const GameLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(gradient: kGameGradient),
              child: EmojiText(
                '🎉 Chi è il più...?',
                textAlign: TextAlign.center,
                style: displayFont(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            if (!online) const _OfflineBanner(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 24),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim red bar shown at the top of every screen while the device is
/// offline. Piggybacks on connectivity_plus so it reacts to the real OS-
/// level state, not the Supabase stream (which may keep serving cached
/// values for up to ~30s after the socket dies).
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: AppColors.destructive,
      child: const EmojiText(
        '📡 Connessione persa, tentativo di riconnessione…',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Soft-shadow rounded card used across screens.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: kCardShadow,
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Scale + fade-in animation mirroring web's `animate-pop-in`.
class PopIn extends StatefulWidget {
  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });
  final Widget child;
  final Duration delay;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.elasticOut),
      ),
      child: FadeTransition(
        opacity: _c,
        child: widget.child,
      ),
    );
  }
}

/// Gentle up-down float used for loading/waiting states.
class Floater extends StatefulWidget {
  const Floater({super.key, required this.child});
  final Widget child;
  @override
  State<Floater> createState() => _FloaterState();
}

class _FloaterState extends State<Floater>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat(reverse: true);

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
        return Transform.translate(
          offset: Offset(0, -8 * t),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
