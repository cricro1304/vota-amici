// Tests for the pure watchdog policy on RoomRepository.
//
// `reapplyPackId` and `roomStateDiffers` are extracted as static methods
// so we can verify them without standing up a real SupabaseClient — see
// the `Stream<Room?> watchRoom(...)` doc comment for how they're used in
// the live merging logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:vota_amici/models/room.dart';
import 'package:vota_amici/repositories/room_repository.dart';

void main() {
  Room makeRoom({
    String id = 'r1',
    String code = 'ABCDE',
    String? hostPlayerId = 'host-1',
    RoomStatus status = RoomStatus.lobby,
    int currentRound = 0,
    int? timerSeconds,
    List<String> modes = const ['light', 'neutro', 'spicy'],
    String? packId = 'pack-classic',
    DateTime? createdAt,
  }) =>
      Room(
        id: id,
        code: code,
        hostPlayerId: hostPlayerId,
        status: status,
        currentRound: currentRound,
        timerSeconds: timerSeconds,
        modes: modes,
        packId: packId,
        createdAt: createdAt ?? DateTime(2026, 5, 1),
      );

  group('RoomRepository.reapplyPackId', () {
    test(
        'Given the row already has a packId, '
        'When reapplyPackId is called with any cached value, '
        'Then it returns the row unchanged (cache must never overwrite '
        'a value the row itself carries)', () {
      final row = makeRoom(packId: 'pack-couples');
      final result = RoomRepository.reapplyPackId(row, 'pack-classic');
      expect(identical(result, row), isTrue);
      expect(result.packId, 'pack-couples');
    });

    test(
        'Given the row has packId == null and we have a cached value, '
        'When reapplyPackId is called, '
        'Then a new Room with the cached packId is returned and every '
        'other field is preserved verbatim', () {
      final row = makeRoom(
        id: 'r-payload',
        code: 'ABCDE',
        hostPlayerId: 'host-7',
        status: RoomStatus.inRound,
        currentRound: 3,
        timerSeconds: 10,
        modes: const ['neutro'],
        packId: null,
      );
      final result = RoomRepository.reapplyPackId(row, 'pack-cached');
      expect(result.packId, 'pack-cached');
      expect(result.id, 'r-payload');
      expect(result.code, 'ABCDE');
      expect(result.hostPlayerId, 'host-7');
      expect(result.status, RoomStatus.inRound);
      expect(result.currentRound, 3);
      expect(result.timerSeconds, 10);
      expect(result.modes, const ['neutro']);
      expect(identical(result, row), isFalse);
    });

    test(
        'Given the row has packId == null and the cache is also null, '
        'When reapplyPackId is called, '
        'Then the row is returned unchanged (no value to apply)', () {
      final row = makeRoom(packId: null);
      final result = RoomRepository.reapplyPackId(row, null);
      expect(identical(result, row), isTrue);
      expect(result.packId, isNull);
    });
  });

  group('RoomRepository.roomStateDiffers', () {
    test(
        'Given two identical rows by reference, '
        'When compared, Then returns false (cheap fast path)', () {
      final r = makeRoom();
      expect(RoomRepository.roomStateDiffers(r, r), isFalse);
    });

    test(
        'Given prev is null and next is non-null (or vice-versa), '
        'When compared, Then returns true', () {
      final r = makeRoom();
      expect(RoomRepository.roomStateDiffers(null, r), isTrue);
      expect(RoomRepository.roomStateDiffers(r, null), isTrue);
    });

    test(
        'Given two equal-by-value rows, When compared, '
        'Then returns false — a watchdog poll seeing the same row the '
        'realtime stream already pushed must not re-emit', () {
      final a = makeRoom();
      final b = makeRoom();
      expect(RoomRepository.roomStateDiffers(a, b), isFalse);
    });

    test(
        'Given only `code`, `modes`, or `createdAt` differ, '
        'When compared, Then returns false — these never change for a '
        'room and re-emitting on them would just churn the UI', () {
      final base = makeRoom();
      expect(
        RoomRepository.roomStateDiffers(
          base,
          makeRoom(code: 'ZZZZZ'),
        ),
        isFalse,
      );
      expect(
        RoomRepository.roomStateDiffers(
          base,
          makeRoom(modes: const ['light']),
        ),
        isFalse,
      );
      expect(
        RoomRepository.roomStateDiffers(
          base,
          makeRoom(createdAt: DateTime(2030)),
        ),
        isFalse,
      );
    });

    test(
        'Given `status` flips lobby → in_round (THE bug we fix), '
        'When compared, Then returns true', () {
      final lobby = makeRoom(status: RoomStatus.lobby);
      final inRound =
          makeRoom(status: RoomStatus.inRound, currentRound: 1);
      expect(RoomRepository.roomStateDiffers(lobby, inRound), isTrue);
    });

    test(
        'Given only `currentRound` differs, '
        'When compared, Then returns true (round advance)', () {
      final r1 = makeRoom(status: RoomStatus.inRound, currentRound: 1);
      final r2 = makeRoom(status: RoomStatus.inRound, currentRound: 2);
      expect(RoomRepository.roomStateDiffers(r1, r2), isTrue);
    });

    test(
        'Given only `timerSeconds` differs, '
        'When compared, Then returns true', () {
      final off = makeRoom(timerSeconds: null);
      final on = makeRoom(timerSeconds: 10);
      expect(RoomRepository.roomStateDiffers(off, on), isTrue);
    });

    test(
        'Given only `hostPlayerId` differs, '
        'When compared, Then returns true (host transferred)', () {
      final a = makeRoom(hostPlayerId: 'host-A');
      final b = makeRoom(hostPlayerId: 'host-B');
      expect(RoomRepository.roomStateDiffers(a, b), isTrue);
    });

    test(
        'Given `packId` legacy NULL → real id, '
        'When compared, Then returns true so the watchdog pushes the '
        'fresher value (covers the realtime-payload-dropped-pack_id case '
        'when the joiner had no primer to seed the cache)', () {
      final legacy = makeRoom(packId: null);
      final real = makeRoom(packId: 'pack-couples');
      expect(RoomRepository.roomStateDiffers(legacy, real), isTrue);
    });

    test(
        'Given `id` differs (sanity check — should never happen for the '
        'same watchRoom subscription), When compared, Then returns true', () {
      final a = makeRoom(id: 'r1');
      final b = makeRoom(id: 'r2');
      expect(RoomRepository.roomStateDiffers(a, b), isTrue);
    });
  });
}
