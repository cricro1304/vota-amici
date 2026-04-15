import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/room_repository.dart';
import '../repositories/game_repository.dart';
import '../services/session_service.dart';
import '../services/game_service.dart';
import '../services/dev_bot_service.dart';
import '../services/share_service.dart';

/// GetIt container. Registering concrete implementations here lets us
/// override them in tests (per flutter-tester skill conventions).
final GetIt locator = GetIt.instance;

Future<void> configureDependencies() async {
  final client = Supabase.instance.client;
  final prefs = await SharedPreferences.getInstance();

  locator
    ..registerSingleton<SupabaseClient>(client)
    ..registerSingleton<SharedPreferences>(prefs)
    // Repositories — raw data access, one per domain.
    ..registerLazySingleton<RoomRepository>(
      () => RoomRepository(locator<SupabaseClient>()),
    )
    ..registerLazySingleton<GameRepository>(
      () => GameRepository(locator<SupabaseClient>()),
    )
    // Services — business logic composed on top of repositories.
    ..registerLazySingleton<SessionService>(
      () => SessionService(locator<SharedPreferences>()),
    )
    ..registerLazySingleton<GameService>(
      () => GameService(
        roomRepository: locator<RoomRepository>(),
        gameRepository: locator<GameRepository>(),
      ),
    )
    ..registerLazySingleton<ShareService>(() => const ShareService())
    ..registerLazySingleton<DevBotService>(
      () => DevBotService(
        roomRepository: locator<RoomRepository>(),
        gameRepository: locator<GameRepository>(),
        gameService: locator<GameService>(),
      ),
    );
}
