import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/emoji_text.dart';

/// Mobile "Pacchetti" tab — stub for the pack browser.
///
/// Will become a full pack catalogue with previews, coming-soon states,
/// and eventually a storefront. For now, acts as a placeholder so the
/// navigation scaffold is complete.
class PacksTab extends StatelessWidget {
  const PacksTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const EmojiText('📦', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(
                'Pacchetti',
                style: displayFont(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Esplora e sfoglia i pacchetti disponibili.\nProssimamente.',
                textAlign: TextAlign.center,
                style: bodyFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
