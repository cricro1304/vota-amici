import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

/// Mobile-only scaffold: wraps tab content with a Material 3 NavigationBar.
///
/// Lives outside the game room flow — `/room/:code` routes intentionally
/// bypass this shell so voting/results/lobby are always full-screen.
class MobileShell extends StatelessWidget {
  const MobileShell({super.key, required this.child});
  final Widget child;

  static const _destinations = [
    (
      path: '/mobile',
      icon: Icons.sports_esports_outlined,
      activeIcon: Icons.sports_esports,
      label: 'Gioca',
    ),
    (
      path: '/mobile/packs',
      icon: Icons.apps_outlined,
      activeIcon: Icons.apps,
      label: 'Pacchetti',
    ),
    (
      path: '/mobile/profile',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profilo',
    ),
  ];

  int _currentIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    for (var i = 0; i < _destinations.length; i++) {
      if (path.startsWith(_destinations[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: GestureDetector(
        // Tapping outside a focused TextField dismisses the soft keyboard.
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => context.go(_destinations[i].path),
            backgroundColor: AppColors.card,
            indicatorColor: AppColors.primaryTint,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.activeIcon, color: AppColors.primary),
                  label: d.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
