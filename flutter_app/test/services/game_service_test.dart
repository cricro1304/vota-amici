// Example test scaffold following the flutter-tester skill conventions.
// Run `dart run build_runner build` after editing @GenerateMocks.

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

  setUp(() {
    roomRepo = MockRoomRepository();
    gameRepo = MockGameRepository();
    service = GameService(roomRepository: roomRepo, gameRepository: gameRepo);
  });

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
      final room = Room(
        id: 'r1',
        code: 'ABCDE',
        hostPlayerId: 'p1',
        status: RoomStatus.inRound,
        currentRound: 1,
        timerSeconds: null,
        createdAt: DateTime.now(),
      );
      final cached = Player(
        id: 'p1',
        roomId: 'r1',
        name: 'Ale',
        isHost: true,
        createdAt: DateTime.now(),
      );
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
      ));
    });

    test(
        'Given two browsers join with the same name (no cached id), '
        'When joinRoom called, Then each call creates a distinct player '
        '(regression: same-name collision bug)', () async {
      final room = Room(
        id: 'r1',
        code: 'ABCDE',
        hostPlayerId: 'p1',
        status: RoomStatus.lobby,
        currentRound: 0,
        timerSeconds: null,
        createdAt: DateTime.now(),
      );
      final newPlayer = Player(
        id: 'p2',
        roomId: 'r1',
        name: 'Ale',
        isHost: false,
        createdAt: DateTime.now(),
      );
      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      when(roomRepo.createPlayer(roomId: 'r1', name: 'Ale'))
          .thenAnswer((_) async => newPlayer);

      // No existingPlayerId → must create a fresh player even though the
      // name 'Ale' may already exist in the room from another browser.
      final result =
          await service.joinRoom(roomCode: 'ABCDE', playerName: 'Ale');

      expect(result.player.id, 'p2');
      verify(roomRepo.createPlayer(roomId: 'r1', name: 'Ale')).called(1);
      // Critically: no lookup by name — that was the old dedup that caused
      // the cross-browser-same-name bug.
      verifyNever(roomRepo.findPlayerByName(
        roomId: anyNamed('roomId'),
        name: anyNamed('name'),
      ));
    });

    test(
        'Given cached existingPlayerId points to a player in a DIFFERENT room, '
        'When joinRoom called, Then ignores the stale id and creates new',
        () async {
      final room = Room(
        id: 'r1',
        code: 'ABCDE',
        hostPlayerId: 'pX',
        status: RoomStatus.lobby,
        currentRound: 0,
        timerSeconds: null,
        createdAt: DateTime.now(),
      );
      final staleFromOtherRoom = Player(
        id: 'p9',
        roomId: 'r9', // <- different room
        name: 'Ale',
        isHost: false,
        createdAt: DateTime.now(),
      );
      final fresh = Player(
        id: 'pNew',
        roomId: 'r1',
        name: 'Ale',
        isHost: false,
        createdAt: DateTime.now(),
      );
      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      when(roomRepo.findPlayerById('p9'))
          .thenAnswer((_) async => staleFromOtherRoom);
      when(roomRepo.createPlayer(roomId: 'r1', name: 'Ale'))
          .thenAnswer((_) async => fresh);

      final result = await service.joinRoom(
        roomCode: 'ABCDE',
        playerName: 'Ale',
        existingPlayerId: 'p9',
      );

      expect(result.player.id, 'pNew');
      verify(roomRepo.createPlayer(roomId: 'r1', name: 'Ale')).called(1);
    });
  });
}
