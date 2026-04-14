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
        'Given existing player with same name, When joinRoom called, '
        'Then returns existing without creating', () async {
      final room = Room(
        id: 'r1',
        code: 'ABCDE',
        hostPlayerId: 'p1',
        status: RoomStatus.inRound,
        currentRound: 1,
        timerSeconds: null,
        createdAt: DateTime.now(),
      );
      final existing = Player(
        id: 'p1',
        roomId: 'r1',
        name: 'Ale',
        isHost: true,
        createdAt: DateTime.now(),
      );
      when(roomRepo.findRoomByCode('ABCDE')).thenAnswer((_) async => room);
      when(roomRepo.findPlayerByName(roomId: 'r1', name: 'Ale'))
          .thenAnswer((_) async => existing);

      final result =
          await service.joinRoom(roomCode: 'ABCDE', playerName: 'Ale');

      expect(result.player.id, 'p1');
      verifyNever(roomRepo.createPlayer(
        roomId: anyNamed('roomId'),
        name: anyNamed('name'),
      ));
    });
  });
}
