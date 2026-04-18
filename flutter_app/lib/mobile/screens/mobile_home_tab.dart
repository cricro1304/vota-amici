import 'package:flutter/material.dart';

import '../../screens/home_screen.dart';

/// Mobile "Gioca" tab — reuses the shared [HomeScreen] unchanged.
///
/// Keyboard dismissal and status-bar styling are handled by [MobileShell],
/// so this wrapper stays intentionally thin. Any mobile-specific chrome
/// (hero greeting, recent-games strip, etc.) can be added here without
/// touching the web-facing [HomeScreen].
class MobileHomeTab extends StatelessWidget {
  const MobileHomeTab({super.key});

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
