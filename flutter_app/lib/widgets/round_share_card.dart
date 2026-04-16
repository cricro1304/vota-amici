import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'emoji_text.dart';

/// Poster-style summary of a single round — the thing we screenshot and
/// send to the native share sheet.
///
/// Intrinsic logical size is 360×360 so a 3× `RepaintBoundary.toImage`
/// capture yields a crisp 1080×1080 image — ideal for Instagram Stories,
/// WhatsApp, Messages. All text + rings are static (no animation) so the
/// single captured frame looks intentional, not mid-pulse.
class RoundShareCard extends StatelessWidget {
  const RoundShareCard({
    super.key,
    required this.roundNumber,
    required this.question,
    required this.winners,
    required this.maxVotes,
    required this.totalVotes,
    required this.caption,
    this.siteLabel = 'vota-amici.it',
  });

  final int roundNumber;
  final String question;
  final List<ShareCardWinner> winners;
  final int maxVotes;
  final int totalVotes;
  final String caption;
  final String siteLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      height: 360,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient backdrop — same pink→cyan as the app header.
            Container(
              decoration: const BoxDecoration(gradient: kGameGradient),
            ),
            // Decorative translucent circles give the poster depth.
            Positioned(
              top: -40,
              right: -30,
              child: _blob(120, Colors.white.withValues(alpha: 0.18)),
            ),
            Positioned(
              bottom: -40,
              left: -30,
              child: _blob(100, Colors.white.withValues(alpha: 0.12)),
            ),
            Positioned(
              top: 60,
              left: -20,
              child: _blob(50, AppColors.yellow.withValues(alpha: 0.35)),
            ),
            // Brand strip on top.
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: EmojiText(
                '🎭 Chi è il più...?',
                textAlign: TextAlign.center,
                style: displayFont(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            // Main card with the question + winners.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 44, 24, 44),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: kCardShadow,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoundPill(roundNumber: roundNumber),
                    Flexible(
                      child: EmojiText(
                        question,
                        textAlign: TextAlign.center,
                        style: displayFont(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                    // Winner(s) row. Wrap keeps ties readable even with 3+.
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        for (final w in winners) _WinnerCell(winner: w),
                      ],
                    ),
                    EmojiText(
                      caption,
                      textAlign: TextAlign.center,
                      style: bodyFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Site watermark at the bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: EmojiText(
                '🎮 $siteLabel',
                textAlign: TextAlign.center,
                style: displayFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

/// Data-only projection of a winner — kept decoupled from the Player model
/// so the poster can be built without importing game domain types.
class ShareCardWinner {
  const ShareCardWinner({
    required this.name,
    required this.initials,
    required this.color,
  });
  final String name;
  final String initials;
  final Color color;
}

class _RoundPill extends StatelessWidget {
  const _RoundPill({required this.roundNumber});
  final int roundNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'ROUND $roundNumber',
        style: bodyFont(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _WinnerCell extends StatelessWidget {
  const _WinnerCell({required this.winner});
  final ShareCardWinner winner;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Static ring — the animated [WinnerRing] would be captured mid-
        // frame, which looks off in a screenshot.
        Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: kWinnerRingGradient,
            boxShadow: [
              BoxShadow(
                color: Color(0x40F5C518),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: winner.color,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              winner.initials,
              style: displayFont(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 80,
          child: Text(
            winner.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: displayFont(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
        ),
      ],
    );
  }
}
