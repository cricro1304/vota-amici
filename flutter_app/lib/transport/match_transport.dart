// Match transport — the seam that lets us plug in offline (LAN / Bluetooth)
// multiplayer later without rewriting GameService, screens, or the Supabase
// path.
//
// This file is intentionally isolated: it has NO imports from repositories,
// services, or screens. A transport just shuttles frames between a host
// device and N guest devices on the same local network. `LocalRoomRepository`
// and `LocalGameRepository` (to be added in Phase 4 per mobile-app-design.md)
// will sit on top of this and translate repository calls into frames.
//
// The Supabase path does NOT use this — online play goes through
// SupabaseRoomRepository / SupabaseGameRepository as it does today.

import 'dart:async';

/// Role of the current device in a local (offline) session.
///
/// The host is the single authoritative source of truth: it holds the
/// in-memory room + rounds + votes and runs the same round-progression
/// logic `GameService` already implements online. Guests mirror the
/// host's state read-only and send writes (votes, join requests) back
/// via [MatchTransport.send].
enum LocalRole { host, guest }

/// Bidirectional frame-based transport between a host device and N guests.
///
/// Implementations we expect:
///   - `InMemoryMatchTransport` — test-only pair loopback, no I/O.
///   - `NearbyConnectionsMatchTransport` — real LAN/BT via the
///     `nearby_connections` plugin (Android) + MultipeerConnectivity
///     (iOS). Lands in Phase 4.
///   - Potentially a `WebSocketMatchTransport` — if we ever want a
///     LAN-only fallback over mDNS + WS without depending on the
///     mobile-native plugins.
///
/// The interface is narrow on purpose: it should be cheap to add a new
/// transport, and behavioral tests should be identical across all of them
/// (see `test/transport/in_memory_match_transport_test.dart`).
abstract class MatchTransport {
  /// Role of this endpoint for the lifetime of the transport. Not
  /// re-assignable — swap the transport if the role changes.
  LocalRole get role;

  /// Frames received from the other end.
  ///
  /// On the host, this is every guest's frames, multiplexed and tagged
  /// with the guest's `peerId` on the frame envelope.
  ///
  /// On guests, this is only the host's frames.
  ///
  /// The stream is a broadcast stream — multiple listeners are allowed
  /// and late subscribers do NOT receive historic frames. Callers that
  /// care about the latest state (e.g. "what room am I in right now?")
  /// should maintain their own cache.
  Stream<TransportFrame> incoming();

  /// Send a frame to the other end.
  ///
  /// On the host, [to] targets a specific connected guest by peer id;
  /// `null` broadcasts to all connected guests. On guests, [to] is
  /// ignored — frames always go to the host.
  Future<void> send(TransportFrame frame, {String? to});

  /// Currently connected peers, as a reactive set.
  ///
  /// On the host, this is the set of guests currently reachable. On
  /// guests, this is a singleton `{'host'}` while connected, empty
  /// during reconnect.
  ///
  /// Like [incoming], this is a broadcast stream; it emits the current
  /// set on subscription.
  Stream<Set<String>> peers();

  /// Shut down the transport. After this, [incoming] and [peers] complete
  /// and [send] throws.
  Future<void> close();
}

// ---------------------------------------------------------------------------
// Frame types
// ---------------------------------------------------------------------------
//
// Frame kinds map 1:1 onto repository operations so the
// LocalRoomRepository/LocalGameRepository translation layer is a thin
// switch rather than a protocol interpreter. Sealed so that the
// exhaustiveness checker flags any missing case when we add a new frame.

sealed class TransportFrame {
  const TransportFrame({required this.peerId});

  /// Envelope: which peer sent this frame. For host->guest broadcasts,
  /// this is `'host'`. For guest->host frames, this is the guest's
  /// stable peer id (typically their browser id from SessionService —
  /// we reuse the existing fingerprint rather than minting a new one).
  final String peerId;
}

/// Guest -> host: "I want to join this room as `name`." The host
/// decides whether to accept (name collisions, room-full, wrong code)
/// and replies with either an updated [StateDeltaFrame] or an
/// [ErrorFrame].
class JoinRequestFrame extends TransportFrame {
  const JoinRequestFrame({
    required super.peerId,
    required this.playerName,
    required this.browserId,
  });

  final String playerName;
  final String browserId;
}

/// Host -> guest(s): a snapshot of the current room + players + rounds +
/// votes. Sent on every state change. Guests overwrite their local
/// cache with the snapshot — no delta math — which keeps the transport
/// idempotent under reordering/retransmission at the cost of a bit
/// more bandwidth per change. Acceptable for turn-based play.
///
/// We pass maps, not model instances, so the transport layer doesn't
/// import the models package. The repository adapter converts.
class StateDeltaFrame extends TransportFrame {
  const StateDeltaFrame({
    required super.peerId,
    required this.roomJson,
    required this.playersJson,
    required this.roundsJson,
    required this.votesJson,
  });

  final Map<String, dynamic> roomJson;
  final List<Map<String, dynamic>> playersJson;
  final List<Map<String, dynamic>> roundsJson;
  final List<Map<String, dynamic>> votesJson;
}

/// Guest -> host: cast a vote in the current round.
class VoteFrame extends TransportFrame {
  const VoteFrame({
    required super.peerId,
    required this.roundId,
    required this.voterId,
    required this.votedForId,
  });

  final String roundId;
  final String voterId;
  final String votedForId;
}

/// Guest -> host (usually from the host tapping "next" on their own
/// device): advance to the next round. The host's repository picks
/// the next question and runs the state machine.
class AdvanceRoundFrame extends TransportFrame {
  const AdvanceRoundFrame({required super.peerId});
}

/// Guest -> host: reveal the current round's votes.
class RevealFrame extends TransportFrame {
  const RevealFrame({required super.peerId});
}

/// Host -> guest: request rejected (room full, game already started,
/// wrong code, unknown vote target, etc.).
class ErrorFrame extends TransportFrame {
  const ErrorFrame({
    required super.peerId,
    required this.message,
    this.code,
  });

  final String message;
  final String? code;
}
