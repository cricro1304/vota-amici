import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/emoji_text.dart';

/// Mobile "Profilo" tab — stub for user profile and settings.
///
/// Will host guest-vs-signed-in state, recent games history, and account
/// management (magic-link auth via Supabase). For now, acts as a
/// placeholder so the navigation scaffold is complete.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const EmojiText('👤', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(
                'Profilo',
                style: displayFont(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gestisci il tuo account e le tue partite.\nProssimamente.',
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
