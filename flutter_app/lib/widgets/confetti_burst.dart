import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// One-shot confetti overlay that plays when the widget first mounts and
/// then disposes itself. Lightweight (no new dependency) — we paint ~60
/// paper-like rectangles with a [CustomPainter] driven by a single
/// [AnimationController].
///
/// Sized to its parent via [Positioned.fill], so the simplest usage is:
///   Stack(children: [..., ConfettiBurst(seed: roomId)]).
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.duration = const Duration(milliseconds: 3200),
    this.particleCount = 70,
    this.seed,
  });

  final Duration duration;
  final int particleCount;

  /// Seed for the RNG so the burst is deterministic per room — same end
  /// screen shown twice (e.g., user navigates back) gets the same layout
  /// instead of a jarring re-roll.
  final Object? seed;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = Random(widget.seed?.hashCode ?? 42);
    _particles = List.generate(widget.particleCount, (_) => _Particle(rng));
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          // Fade out in the last 25% so the confetti doesn't disappear
          // abruptly when the controller finishes.
          final fade = _c.value < 0.75
              ? 1.0
              : ((1.0 - _c.value) / 0.25).clamp(0.0, 1.0);
          return CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              t: _c.value,
              opacity: fade,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle(Random rng)
      : xStart = rng.nextDouble(),
        xDrift = (rng.nextDouble() - 0.5) * 0.25,
        delay = rng.nextDouble() * 0.35,
        duration = 0.55 + rng.nextDouble() * 0.35,
        rotationStart = rng.nextDouble() * 2 * pi,
        rotationSpeed = (rng.nextDouble() - 0.5) * 10,
        size = 6 + rng.nextDouble() * 8,
        color = _palette[rng.nextInt(_palette.length)],
        wobble = rng.nextDouble() * 2 * pi;

  final double xStart; // 0..1 fractional across width
  final double xDrift; // additional horizontal shift over life (fractional)
  final double delay; // 0..1 fraction of total duration
  final double duration; // 0..1 fraction — lifetime of this particle
  final double rotationStart;
  final double rotationSpeed;
  final double size;
  final Color color;
  final double wobble;

  static const _palette = <Color>[
    AppColors.primary,
    AppColors.secondary,
    AppColors.accent,
    AppColors.yellow,
    AppColors.purple,
    AppColors.orange,
  ];
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.particles,
    required this.t,
    required this.opacity,
  });

  final List<_Particle> particles;
  final double t;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Normalise "local time" into 0..1 across this particle's lifespan.
      final localT = ((t - p.delay) / p.duration).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      // Vertical position falls with mild easing to mimic gravity.
      final y = Curves.easeIn.transform(localT) * (size.height + 40) - 20;
      // Horizontal drift + a small sine wobble so the papers look like
      // they're fluttering rather than dropping straight.
      final x = (p.xStart + p.xDrift * localT) * size.width +
          sin(t * 2 * pi + p.wobble) * 6;

      final rotation = p.rotationStart + p.rotationSpeed * localT;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.45,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.t != t || old.opacity != opacity;
}
