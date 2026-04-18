// Widget test for [MobileHomeScreen].
//
// MobileHomeScreen is a thin mobile shell around the shared [HomeScreen]:
// it adds a dark status-bar overlay and a tap-outside-to-dismiss-keyboard
// gesture. That sounds trivial, but it's exactly the kind of wrapper that
// can silently break rendering if the GestureDetector eats the hit test or
// the AnnotatedRegion wraps the wrong subtree — so this test acts as a
// smoke check before we take the app into Xcode.
//
// Scope (deliberately minimal):
//   1. The home-screen CTAs ("Gioca Ora" / "Unisciti") still render under
//      the mobile wrapper. If this fails, the wrapper broke the shared
//      flow for phone users.
//   2. An [AnnotatedRegion] with [SystemUiOverlayStyle.dark] is present in
//      the tree. This is what controls the iOS status-bar tint.
//   3. A [GestureDetector] with [HitTestBehavior.opaque] is present. This
//      is what lets taps on empty space dismiss the soft keyboard.
//
// We override [isOnlineProvider] rather than letting the real
// `connectivity_plus` plugin run — `MethodChannel` calls have no backing
// implementation under `flutter_test` and would throw a MissingPluginException
// when [GameLayout] subscribes to the stream during build.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vota_amici/screens/home_screen.dart';
import 'package:vota_amici/screens/mobile_home_screen.dart';
import 'package:vota_amici/state/connectivity_provider.dart';

void main() {
  /// Pumps [MobileHomeScreen] inside the minimum scaffolding it needs to
  /// render: a [MaterialApp] for directionality / theme, a [ProviderScope]
  /// with [isOnlineProvider] stubbed so `GameLayout` doesn't hit the
  /// `connectivity_plus` plugin.
  Future<void> pumpMobileHome(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Keep the offline banner hidden; the real provider would call
          // `Connectivity()` which has no platform channel backing in tests.
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: const MaterialApp(
          home: MobileHomeScreen(),
        ),
      ),
    );
    // One `pump` kicks off the PopIn animation controllers; we don't
    // pumpAndSettle because Google Fonts and network emoji images will
    // never "settle" in an offline test environment. The first frame is
    // enough to assert the widget tree is well-formed.
    await tester.pump();
  }

  group('MobileHomeScreen', () {
    testWidgets(
        'Given the mobile home shell, '
        'When it renders, '
        'Then the shared home CTAs are visible', (tester) async {
      await pumpMobileHome(tester);

      // EmojiText renders as Text.rich, so the button labels live inside
      // RichText widgets. `findRichText: true` tells the finder to search
      // TextSpan content in addition to plain Text widgets.
      expect(
        find.textContaining('Gioca Ora', findRichText: true),
        findsOneWidget,
        reason: 'Primary CTA should render under the mobile wrapper',
      );
      expect(
        find.textContaining('Unisciti', findRichText: true),
        findsOneWidget,
        reason: 'Secondary "join room" CTA should render too',
      );
    });

    testWidgets(
        'Given the mobile home shell, '
        'When it renders, '
        'Then a dark status-bar AnnotatedRegion wraps the content', (tester) async {
      await pumpMobileHome(tester);

      // There can be more than one AnnotatedRegion<SystemUiOverlayStyle>
      // in the tree (MaterialApp injects its own based on theme), so we
      // specifically look for one descendant of MobileHomeScreen whose
      // value is SystemUiOverlayStyle.dark.
      final annotated = find.descendant(
        of: find.byType(MobileHomeScreen),
        matching: find.byWidgetPredicate(
          (w) =>
              w is AnnotatedRegion<SystemUiOverlayStyle> &&
              w.value == SystemUiOverlayStyle.dark,
          description:
              'AnnotatedRegion<SystemUiOverlayStyle> with dark status-bar style',
        ),
      );
      expect(
        annotated,
        findsOneWidget,
        reason:
            'Mobile shell should force dark status-bar icons so the time / '
            'battery stay legible against the light scaffold background.',
      );
    });

    testWidgets(
        'Given the mobile home shell, '
        'When it renders, '
        'Then an opaque GestureDetector wraps the content to catch taps', (tester) async {
      await pumpMobileHome(tester);

      // Multiple GestureDetectors can appear in the tree — InkWell under
      // each ElevatedButton wires one up with HitTestBehavior.opaque and
      // an onTap too — so we specifically look for the detector whose
      // direct child is a HomeScreen. That's the one our wrapper installs
      // around the shared flow to catch taps on empty space.
      final detector = find.descendant(
        of: find.byType(MobileHomeScreen),
        matching: find.byWidgetPredicate(
          (w) =>
              w is GestureDetector &&
              w.behavior == HitTestBehavior.opaque &&
              w.onTap != null &&
              w.child is HomeScreen,
          description:
              'GestureDetector with HitTestBehavior.opaque wrapping HomeScreen',
        ),
      );
      expect(
        detector,
        findsOneWidget,
        reason:
            'Without the opaque detector, tapping outside a focused TextField '
            'wouldn\'t dismiss the soft keyboard — the primary CTA would stay '
            'covered and the flow would feel broken on iOS.',
      );
    });
  });
}
