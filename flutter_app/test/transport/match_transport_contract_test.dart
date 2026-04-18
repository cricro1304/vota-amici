// Contract test for MatchTransport implementations.
//
// Any class that implements `MatchTransport` must pass these tests. Today
// we only have `InMemoryMatchTransport`; when the real LAN/Bluetooth
// transport lands in Phase 4 (see `mobile-app-design.md`), point the
// `makePair` factory at it and this suite will exercise the same
// behaviors against the real plugin — that's the safety net that lets us
// swap transports without silently regressing offline play.
//
// Test style: Given-When-Then, per the flutter-tester skill. Each test
// builds a fresh (host, guest) pair in `setUp` so state never leaks.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vota_amici/transport/in_memory_match_transport.dart';
import 'package:vota_amici/transport/match_transport.dart';

void main() {
  // Swap this out for the real transport under test when Phase 4 lands.
  // Kept as a nullary function so setUp can call it fresh each test.
  (MatchTransport host, MatchTransport guest) makePair({String guestId = 'guest-A'}) {
    return InMemoryMatchTransport.pair(guestPeerId: guestId);
  }

  late MatchTransport host;
  late MatchTransport guest;

  setUp(() {
    final p = makePair();
    host = p.$1;
    guest = p.$2;
  });

  tearDown(() async {
    await host.close();
    await guest.close();
  });

  group('peer visibility', () {
    test(
        'Given a fresh host-guest pair, '
        'When either side subscribes to peers(), '
        'Then the host sees the guest and the guest sees the host', () async {
      expect(await host.peers().first, equals({'guest-A'}));
      expect(await guest.peers().first, equals({'host'}));
    });

    test(
        'Given the host has two connected guests, '
        'When the host subscribes to peers(), '
        'Then both guest ids are present', () async {
      final p = InMemoryMatchTransport.hostWithGuests(
        guestPeerIds: ['g-1', 'g-2'],
      );
      addTearDown(() async {
        await p.host.close();
        for (final g in p.guests) {
          await g.close();
        }
      });

      expect(await p.host.peers().first, equals({'g-1', 'g-2'}));
    });
  });

  group('role', () {
    test('Given the transport pair, Then host.role is host and guest.role is guest', () {
      expect(host.role, LocalRole.host);
      expect(guest.role, LocalRole.guest);
    });
  });

  group('guest -> host frame delivery', () {
    test(
        'Given a guest sends a JoinRequestFrame, '
        'When the host listens on incoming(), '
        'Then the frame is received exactly once with the guest peer id', () async {
      // Subscribe BEFORE sending so the broadcast stream doesn't drop the frame.
      final received = host.incoming().take(1).toList();

      await guest.send(const JoinRequestFrame(
        peerId: 'guest-A',
        playerName: 'Ale',
        browserId: 'browser-xyz',
      ));

      final frames = await received;
      expect(frames, hasLength(1));
      final frame = frames.single;
      expect(frame, isA<JoinRequestFrame>());
      expect(frame.peerId, 'guest-A');
      expect((frame as JoinRequestFrame).playerName, 'Ale');
      expect(frame.browserId, 'browser-xyz');
    });

    test(
        'Given a guest sends a VoteFrame, '
        'When the host receives it, '
        'Then the round/voter/target round-trip unchanged', () async {
      final received = host.incoming().take(1).toList();

      await guest.send(const VoteFrame(
        peerId: 'guest-A',
        roundId: 'round-1',
        voterId: 'p1',
        votedForId: 'p2',
      ));

      final frame = (await received).single as VoteFrame;
      expect(frame.roundId, 'round-1');
      expect(frame.voterId, 'p1');
      expect(frame.votedForId, 'p2');
    });

    test(
        'Given a guest sends a frame with a bogus `to` target, '
        'When the host receives it, '
        'Then the frame still arrives (guests ignore `to`)', () async {
      // Guests always talk to the host; `to` is irrelevant on guest->host.
      final received = host.incoming().take(1).toList();

      await guest.send(
        const AdvanceRoundFrame(peerId: 'guest-A'),
        to: 'someone-else',
      );

      final frames = await received;
      expect(frames.single, isA<AdvanceRoundFrame>());
    });
  });

  group('host -> guest broadcast', () {
    test(
        'Given the host broadcasts a StateDeltaFrame with `to: null`, '
        'When all guests listen, '
        'Then every guest receives the same frame', () async {
      final p = InMemoryMatchTransport.hostWithGuests(
        guestPeerIds: ['g-1', 'g-2', 'g-3'],
      );
      addTearDown(() async {
        await p.host.close();
        for (final g in p.guests) {
          await g.close();
        }
      });
      final received = Future.wait(
        p.guests.map((g) => g.incoming().take(1).first),
      );

      await p.host.send(const StateDeltaFrame(
        peerId: 'host',
        roomJson: {'id': 'r1', 'status': 'lobby'},
        playersJson: [],
        roundsJson: [],
        votesJson: [],
      ));

      final frames = await received;
      expect(frames, hasLength(3));
      for (final f in frames) {
        expect(f, isA<StateDeltaFrame>());
        expect((f as StateDeltaFrame).roomJson['id'], 'r1');
      }
    });

    test(
        'Given the host targets a single guest with `to: <peerId>`, '
        'When other guests listen, '
        'Then only the target receives the frame', () async {
      final p = InMemoryMatchTransport.hostWithGuests(
        guestPeerIds: ['g-1', 'g-2'],
      );
      addTearDown(() async {
        await p.host.close();
        for (final g in p.guests) {
          await g.close();
        }
      });

      // Collect frames for both guests over a short window. g-2 should
      // see nothing; g-1 should see the ErrorFrame.
      final g1Frames = <TransportFrame>[];
      final g2Frames = <TransportFrame>[];
      final sub1 = p.guests[0].incoming().listen(g1Frames.add);
      final sub2 = p.guests[1].incoming().listen(g2Frames.add);
      addTearDown(() async {
        await sub1.cancel();
        await sub2.cancel();
      });

      await p.host.send(
        const ErrorFrame(peerId: 'host', message: 'room full', code: 'ROOM_FULL'),
        to: 'g-1',
      );
      // Let the microtask queue drain so broadcast listeners see the frame.
      await Future<void>.delayed(Duration.zero);

      expect(g1Frames, hasLength(1));
      expect((g1Frames.single as ErrorFrame).code, 'ROOM_FULL');
      expect(g2Frames, isEmpty);
    });

    test(
        'Given the host targets an unknown peer id, '
        'When the host sends, '
        'Then the send completes normally and no guest receives it', () async {
      final p = InMemoryMatchTransport.hostWithGuests(
        guestPeerIds: ['g-1'],
      );
      addTearDown(() async {
        await p.host.close();
        await p.guests.single.close();
      });
      final received = <TransportFrame>[];
      final sub = p.guests.single.incoming().listen(received.add);
      addTearDown(sub.cancel);

      await p.host.send(
        const ErrorFrame(peerId: 'host', message: 'nope'),
        to: 'nonexistent-peer',
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });
  });

  group('close semantics', () {
    test(
        'Given close() has been called, '
        'When we try to send, '
        'Then we get a StateError', () async {
      await guest.close();
      expect(
        () => guest.send(const AdvanceRoundFrame(peerId: 'guest-A')),
        throwsStateError,
      );
    });

    test(
        'Given close() has been called, '
        'When we subscribe to incoming(), '
        'Then the stream has already completed and emits nothing', () async {
      await guest.close();
      final frames = await guest.incoming().toList();
      expect(frames, isEmpty);
    });

    test('Given close() is called twice, Then the second call is a no-op', () async {
      await guest.close();
      await guest.close(); // must not throw
    });
  });

  group('incoming is a broadcast stream (multi-listener safe)', () {
    test(
        'Given two listeners attach to the host, '
        'When a guest sends a frame, '
        'Then both listeners receive it', () async {
      final a = <TransportFrame>[];
      final b = <TransportFrame>[];
      final subA = host.incoming().listen(a.add);
      final subB = host.incoming().listen(b.add);
      addTearDown(() async {
        await subA.cancel();
        await subB.cancel();
      });

      await guest.send(const AdvanceRoundFrame(peerId: 'guest-A'));
      await Future<void>.delayed(Duration.zero);

      expect(a, hasLength(1));
      expect(b, hasLength(1));
    });
  });
}
