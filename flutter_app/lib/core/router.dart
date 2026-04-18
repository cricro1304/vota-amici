import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../mobile/mobile_shell.dart';
import '../mobile/screens/mobile_home_tab.dart';
import '../mobile/screens/packs_tab.dart';
import '../mobile/screens/profile_tab.dart';
import '../screens/home_screen.dart';
import '../screens/room_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // Web lands on '/'; mobile lands on '/mobile' (shell with bottom nav).
    initialLocation: kIsWeb ? '/' : '/mobile',
    routes: [
      // ── Web routes ─────────────────────────────────────────────────────
      // Unchanged from main. Both platforms share '/room/:code' so the full
      // game flow (lobby → voting → results → end) works identically.
      GoRoute(
        path: '/',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/room/:code',
        builder: (_, state) => RoomScreen(code: state.pathParameters['code']!),
      ),

      // ── Mobile shell ────────────────────────────────────────────────────
      // ShellRoute wraps only the top-level tabs. Game room routes above are
      // intentionally outside the shell so gameplay is always full-screen.
      if (!kIsWeb)
        ShellRoute(
          builder: (_, __, child) => MobileShell(child: child),
          routes: [
            GoRoute(
              path: '/mobile',
              builder: (_, __) => const MobileHomeTab(),
            ),
            GoRoute(
              path: '/mobile/packs',
              builder: (_, __) => const PacksTab(),
            ),
            GoRoute(
              path: '/mobile/profile',
              builder: (_, __) => const ProfileTab(),
            ),
          ],
        ),
    ],
  );
});
