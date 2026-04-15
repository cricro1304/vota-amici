import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the device is online. Emits on every connectivity change.
///
/// On Flutter Web this tracks `navigator.onLine`, which DevTools' Offline
/// toggle flips — so the offline banner in [ConnectionBanner] appears
/// immediately when you simulate an outage, even though Riverpod's stream
/// providers keep serving cached room data.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final conn = Connectivity();
  // Seed with the current status so the banner doesn't flash on first frame.
  final initial = await conn.checkConnectivity();
  yield _isOnline(initial);
  yield* conn.onConnectivityChanged.map(_isOnline);
});

bool _isOnline(List<ConnectivityResult> results) {
  if (results.isEmpty) return false;
  return results.any((r) => r != ConnectivityResult.none);
}
