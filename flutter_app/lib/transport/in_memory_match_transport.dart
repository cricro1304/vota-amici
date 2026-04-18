// Test-only pair loopback transport. Zero I/O — two endpoints share a
// pair of StreamControllers so frames one side sends appear on the
// other side's `incoming()`.
//
// This is what the transport contract test runs against. It's also
// the default we'll use for Dart-only unit tests of
// LocalRoomRepository/LocalGameRepository in Phase 4 — no plugin
// registration, no platform channels, no timing flakiness.

import 'dart:async';

import 'match_transport.dart';

/// Creates a connected (host, guest) pair backed by in-memory streams.
///
/// Typical use:
///
/// ```dart
/// final (host, guest) = InMemoryMatchTransport.pair();
/// host.incoming().listen((frame) => /* host handler */);
/// await guest.send(JoinRequestFrame(peerId: 'g1', playerName: 'Ale', browserId: 'b'));
/// ```
///
/// The helper seeds [peers] on both ends so `peers().first` returns
/// immediately — real plugins need a connect handshake, but for test
/// purposes we start already connected.
class InMemoryMatchTransport implements MatchTransport {
  InMemoryMatchTransport._({
    required this.role,
    required String selfPeerId,
    required StreamController<TransportFrame> inbound,
    required void Function(TransportFrame, String?) outboundSender,
    required StreamController<Set<String>> peers,
  })  : _selfPeerId = selfPeerId,
        _inbound = inbound,
        _outboundSender = outboundSender,
        _peers = peers;

  @override
  final LocalRole role;

  final String _selfPeerId;
  final StreamController<TransportFrame> _inbound;
  final void Function(TransportFrame frame, String? to) _outboundSender;
  final StreamController<Set<String>> _peers;
  bool _closed = false;

  /// Stable peer id of this endpoint. Host is always `'host'`; guests
  /// are whatever the caller passed in (typically a browserId).
  String get peerId => _selfPeerId;

  @override
  Stream<TransportFrame> incoming() => _inbound.stream;

  @override
  Stream<Set<String>> peers() => _peers.stream;

  @override
  Future<void> send(TransportFrame frame, {String? to}) async {
    if (_closed) {
      throw StateError('InMemoryMatchTransport: send after close');
    }
    _outboundSender(frame, to);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _inbound.close();
    await _peers.close();
  }

  /// Creates a host + guest pair already "connected". The guest's peer
  /// id defaults to `'guest'`; pass [guestPeerId] to simulate a
  /// specific guest (e.g. their browserId).
  ///
  /// For a multi-guest scenario use [hostWithGuests] below.
  static (InMemoryMatchTransport host, InMemoryMatchTransport guest) pair({
    String guestPeerId = 'guest',
  }) {
    final pair = hostWithGuests(guestPeerIds: [guestPeerId]);
    return (pair.host, pair.guests.single);
  }

  /// Creates a host endpoint connected to N guest endpoints.
  ///
  /// On the host, `incoming()` multiplexes all guests' frames. On each
  /// guest, `incoming()` is scoped to only the host's frames.
  ///
  /// Sending from the host with `to: null` broadcasts to all guests.
  /// Sending from the host with `to: '<peerId>'` targets a single
  /// guest. Sending from a guest ignores `to` and always lands on the
  /// host.
  static ({
    InMemoryMatchTransport host,
    List<InMemoryMatchTransport> guests,
  }) hostWithGuests({required List<String> guestPeerIds}) {
    // One inbound queue per endpoint.
    final hostInbound = StreamController<TransportFrame>.broadcast();
    final guestInbounds = {
      for (final id in guestPeerIds)
        id: StreamController<TransportFrame>.broadcast(),
    };

    // Peer visibility. Host sees all guests; each guest sees just the host.
    final hostPeers = StreamController<Set<String>>.broadcast();
    final guestPeerControllers = {
      for (final id in guestPeerIds) id: StreamController<Set<String>>.broadcast(),
    };
    // Seed initial peer sets on the next microtask so late subscribers
    // still get *some* signal — matches how a late `peers()` listener
    // would see the currently-connected set on a real transport.
    scheduleMicrotask(() {
      if (!hostPeers.isClosed) hostPeers.add(guestPeerIds.toSet());
      for (final entry in guestPeerControllers.entries) {
        if (!entry.value.isClosed) entry.value.add({'host'});
      }
    });

    final host = InMemoryMatchTransport._(
      role: LocalRole.host,
      selfPeerId: 'host',
      inbound: hostInbound,
      peers: hostPeers,
      outboundSender: (frame, to) {
        if (to == null) {
          // Broadcast to every guest.
          for (final c in guestInbounds.values) {
            if (!c.isClosed) c.add(frame);
          }
        } else {
          final target = guestInbounds[to];
          if (target != null && !target.isClosed) target.add(frame);
          // Unknown guest id is silently ignored — matches how a real
          // plugin would drop a send-to-disconnected-peer.
        }
      },
    );

    final guests = <InMemoryMatchTransport>[];
    for (final id in guestPeerIds) {
      guests.add(InMemoryMatchTransport._(
        role: LocalRole.guest,
        selfPeerId: id,
        inbound: guestInbounds[id]!,
        peers: guestPeerControllers[id]!,
        outboundSender: (frame, _) {
          // Guests always route to the host, ignoring `to`.
          if (!hostInbound.isClosed) hostInbound.add(frame);
        },
      ));
    }
    return (host: host, guests: guests);
  }
}
