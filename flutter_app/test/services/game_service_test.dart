// Tests for GameService.joinRoom — the rejoin recovery + name-suffix logic.
//
// If you add new methods on RoomRepository/GameRepository you MUST regenerate
// the mocks after editing the @GenerateMocks list:
//
//     dart run build_runner build --delete-conflicting-outputs
//
// The `game_service_test.mocks.dart` file is generated — never edit by hand.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:vota_amici/models/player.dart';
import 'package:vota_amici/models/room.dart';
import 'package:vota_amici/repositories/game_repository.dart';
import 'package:vota_amici/repositories/room_repository.dart';
import 'package:vota_amici/services/game_service.dart';

import 'game_service_test.mocks.dart';

@GenerateMocks([RoomRepository, GameRepository])
void main() {
  late MockRoomRepository roomRepo;
  late MockGameRepository gameRepo;
  late GameService service;

  /// Default: the room starts empty unless a test overrides it. The
  /// `_uniqueNameFor` helper inside GameService reads `watchPlayers().first`
  /// to compute the suffix — stubbing it once here keeps each test terse.
  void stubPlayers(List<Player> players) {
    when(roomRepo.watchPlayers(any))
        .thenAnswer((_) => Stream.value(players));
  }

  setUp(() {
    roomRepo = MockRoomRepository();
    gameRepo = MockGameRepository();
    service = GameService(roomRepository: roomRepo, gameRepository: gameRepo);
    stubPlayers(const []);
  });

  Room makeRoom({
    String id = 'r1',
    String code = 'ABCDE',
    RoomStatus status = RoomStatus.lobby,
  }) =>
      Room(
        id: id,
        code: code,
        hostPlayerId: 'hostId',
        status: status,
        currentRound: 0,
        timerSeconds: null,
        createdAt: DateTime.now(),
      );

  Player makePlayer({
    required String id,
    String roomId = 'r1',
    String name = 'Ale',
    bool isHost = false,
    String? browserId,
  }) =>
      Player(
        id: id,
        roomId: roomId,
        name: name,
        isHost: isHost,
        createdAt: DateTime.now(),
        browserId: browserId,
      );

  group('joinRoom', () {
    test(
        'Given room not found, When joinRoom called, Then throws GameException',
        () async {
      when(roomRepo.findRoomByCode(any)).thenAnswer((_) async => null);

      expect(
        () => service.joinRoom(roomCode: 'XYZ12', playerName: 'Ale'),
        throwsA(isA<GameException>()),
      );
    });

    test(
        'Given cached existingPlayerId still in room, When joinRoom called, '
        'Then reuses that player without creating a new one '
        '(same-browser refresh-to-rejoin path, works even mid-game)',
        () async {
      final room = makeRoom(status: RoomStatus.inRound);
      final cached = makePlayer(id: 'p1', isHost: true);
      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      when(roomRepo.findPlayerById('p1')).thenAnswer((_) async => cached);

      final result = await service.joinRoom(
        roomCode: 'ABCDE',
        playerName: 'Ale',
        existingPlayerId: 'p1',
      );

      expect(result.player.id, 'p1');
      verifyNever(roomRepo.createPlayer(
        roomId: anyNamed('roomId'),
        name: anyNamed('name'),
        browserId: anyNamed('browserId'),
      ));
    });

    test(
        'Given two browsers join with the same name and no cached id nor '
        'matching browserId, When joinRoom called for the second one, '
        'Then the second player is created with a "(2)" suffix '
        '(same-name auto-disambiguation, replaces old "collision" bug)',
        () async {
      final room = makeRoom();
      final firstPlayer = makePlayer(id: 'p1', browserId: 'browser-A');
      stubPlayers([firstPlayer]); // the lobby already has one "Ale"

      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      // Different browser, so browser-recovery lookup misses.
      when(roomRepo.findPlayerByRoomAndBrowser(
        roomId: 'r1',
        browserId: 'browser-B',
      )).thenAnswer((_) async => null);
      when(roomRepo.createPlayer(
        roomId: 'r1',
        name: 'Ale (2)',
        browserId: 'browser-B',
      )).thenAnswer((_) async =>
          makePlayer(id: 'p2', name: 'Ale (2)', browserId: 'browser-B'));

      final result = await service.joinRoom(
        roomCode: 'ABCDE',
        playerName: 'Ale',
        browserId: 'browser-B',
      );

      expect(result.player.id, 'p2');
      expect(result.player.name, 'Ale (2)');
      verify(roomRepo.createPlayer(
        roomId: 'r1',
        name: 'Ale (2)',
        browserId: 'browser-B',
      )).called(1);
    });

    test(
        'Given three browsers join with the same name in sequence, '
        'When joinRoom called for the third, Then the suffix skips to "(3)"',
        () async {
      final room = makeRoom();
      stubPlayers([
        makePlayer(id: 'p1', name: 'Ale'),
        makePlayer(id: 'p2', name: 'Ale (2)'),
      ]);
      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      when(roomRepo.findPlayerByRoomAndBrowser(
        roomId: 'r1',
        browserId: 'browser-C',
      )).thenAnswer((_) async => null);
      when(roomRepo.createPlayer(
        roomId: 'r1',
        name: 'Ale (3)',
        browserId: 'browser-C',
      )).thenAnswer((_) async =>
          makePlayer(id: 'p3', name: 'Ale (3)', browserId: 'browser-C'));

      final result = await service.joinRoom(
        roomCode: 'ABCDE',
        playerName: 'Ale',
        browserId: 'browser-C',
      );

      expect(result.player.name, 'Ale (3)');
    });

    test(
        'Given cached id is missing but a player with our browserId already '
        'exists in the room, When joinRoom called, Then that player is '
        'reused (regression: rejoin-after-reload created a duplicate when '
        'the per-room cache was cleared)',
        () async {
      final room = makeRoom(status: RoomStatus.inRound);
      final existing = makePlayer(id: 'p1', browserId: 'browser-A');
      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      when(roomRepo.findPlayerByRoomAndBrowser(
        roomId: 'r1',
        browserId: 'browser-A',
      )).thenAnswer((_) async => existing);

      final result = await service.joinRoom(
        roomCode: 'ABCDE',
        playerName: 'Ale',
        browserId: 'browser-A',
      );

      expect(result.player.id, 'p1');
      verifyNever(roomRepo.createPlayer(
        roomId: anyNamed('roomId'),
        name: anyNamed('name'),
        browserId: anyNamed('browserId'),
      ));
    });

    test(
        'Given cached existingPlayerId points to a player in a DIFFERENT room '
        'AND no browserId match, When joinRoom called, Then ignores the stale '
        'id and creates new',
        () async {
      final room = makeRoom();
      final staleFromOtherRoom =
          makePlayer(id: 'p9', roomId: 'r9'); // <- different room
      final fresh = makePlayer(id: 'pNew', browserId: 'browser-X');
      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      when(roomRepo.findPlayerById('p9'))
          .thenAnswer((_) async => staleFromOtherRoom);
      when(roomRepo.findPlayerByRoomAndBrowser(
        roomId: 'r1',
        browserId: 'browser-X',
      )).thenAnswer((_) async => null);
      when(roomRepo.createPlayer(
        roomId: 'r1',
        name: 'Ale',
        browserId: 'browser-X',
      )).thenAnswer((_) async => fresh);

      final result = await service.joinRoom(
        roomCode: 'ABCDE',
        playerName: 'Ale',
        existingPlayerId: 'p9',
        browserId: 'browser-X',
      );

      expect(result.player.id, 'pNew');
      verify(roomRepo.createPlayer(
        roomId: 'r1',
        name: 'Ale',
        browserId: 'browser-X',
      )).called(1);
    });

    test(
        'Given room is no longer in lobby and neither cached nor browser '
        'recovery matches, When joinRoom called, Then throws so the user '
        'sees a clear "partita già iniziata" error instead of silently '
        'creating a mid-game ghost',
        () async {
      final room = makeRoom(status: RoomStatus.inRound);
      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      when(roomRepo.findPlayerByRoomAndBrowser(
        roomId: 'r1',
        browserId: 'browser-new',
      )).thenAnswer((_) async => null);

      expect(
        () => service.joinRoom(
          roomCode: 'ABCDE',
          playerName: 'Ale',
          browserId: 'browser-new',
        ),
        throwsA(isA<GameException>()),
      );
    });
  });
}
