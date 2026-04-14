import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Winner ring + inner avatar mirroring `.result-winner-ring /
/// .result-winner-inner` from `public/assets/css/landing.css`.
///
/// Outer: gradient yellow→orange, pulsing halo (winnerPulse keyframes).
/// Inner: solid pink circle with the winner's initials.
class WinnerRing extends StatefulWidget {
  const WinnerRing({
    super.key,
    required this.initials,
    this.size = 96,
    this.innerColor = AppColors.primary,
  });

  final String initials;
  final double size;
  final Color innerColor;

  @override
  State<WinnerRing> createState() => _WinnerRingState();
}

class _WinnerRingState extends State<WinnerRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Landing pulse goes from blur-radius 20 → 40 (and opacity 0.3 → 0.5).
    // We approximate that with an AnimatedBuilder that tweens two BoxShadows.
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        final blur = 20 + 20 * t;
        final alpha = (0.3 + 0.2 * t);
        final alphaByte = (alpha * 255).round();
        final halo = Color.fromARGB(alphaByte, 0xF5, 0xC5, 0x18);

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: kWinnerRingGradient,
            boxShadow: [BoxShadow(color: halo, blurRadius: blur)],
          ),
          alignment: Alignment.center,
          child: Container(
            width: widget.size * 0.85,
            height: widget.size * 0.85,
            decoration: BoxDecoration(
              color: widget.innerColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              widget.initials,
              style: TextStyle(
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: widget.size * 0.30,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tiny pink pill — mirrors `.q-badge / .tut-vote-badge`:
///   background: var(--pink-light); color: var(--pink);
class QuestionBadge extends StatelessWidget {
  const QuestionBadge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryTint, // --pink-light
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Fredoka',
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: AppColors.primary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Dashed-pink room-code card (landing `.tut-room-code`):
/// `border: 2px dashed var(--pink); letter-spacing: 6px; color: var(--pink)`.
class RoomCodeCard extends StatelessWidget {
  const RoomCodeCard({super.key, required this.code, required this.label});
  final String code;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w800,
            fontSize: 11,
            color: AppColors.mutedFg,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        CustomPaint(
          painter: _DashedBorderPainter(
            color: AppColors.primary,
            strokeWidth: 2,
            dashWidth: 6,
            dashGap: 4,
            radius: 16,
          ),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            alignment: Alignment.center,
            child: Text(
              code,
              style: const TextStyle(
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w700,
                fontSize: 40,
                letterSpacing: 10,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashGap,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashWidth != dashWidth ||
      old.dashGap != dashGap ||
      old.radius != radius;
}

/// A horizontal player row used in the lobby — matches `.tut-player-row`:
/// rounded white card, colored avatar circle, name, optional "Host" badge.
class PlayerRow extends StatelessWidget {
  const PlayerRow({
    super.key,
    required this.name,
    required this.index,
    this.isHost = false,
    this.isSelf = false,
  });

  final String name;
  final int index;
  final bool isHost;
  final bool isSelf;

  String get _initials {
    final t = name.trim();
    if (t.isEmpty) return '??';
    return t.substring(0, t.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatarColor = playerColor(index);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000), // rgba(0,0,0,0.04)
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: avatarColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: const TextStyle(
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isSelf ? '$name (Tu)' : name,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isSelf ? AppColors.primary : AppColors.foreground,
              ),
            ),
          ),
          if (isHost)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent, // --teal, matches landing
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Host',
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
