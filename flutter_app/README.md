# vota_amici — Flutter port

Feature-parity Flutter rewrite of the React web app. Targets iOS, Android, and Web from one codebase.

This lives on the `flutter-port` branch. The React app on `main` is untouched.

## Running locally

You need the Flutter SDK installed (https://docs.flutter.dev/get-started/install). Then:

```bash
cd flutter_app

# 1. Scaffold the platform folders (ios/, android/, web/ etc).
#    This DOES NOT overwrite pubspec.yaml or lib/.
flutter create . --project-name vota_amici --platforms=web,ios,android

# 2. Copy env config
cp .env.example .env
# then edit .env with your Supabase URL and anon key
#   (same values as the web app's VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY)

# 3. Install dependencies
flutter pub get

# 4. Run
flutter run -d chrome           # web
flutter run -d <ios-simulator>  # iOS
flutter run -d <android-device> # Android
```

No backend changes required — it talks to the same Supabase project as the web app.

## Architecture

Strict layering, bottom-up:

```
models/          Pure data classes (Room, Player, Round, Vote, Question)
  ↑
repositories/    Raw Supabase access. One class per domain. No business logic.
  ↑
services/        Business logic. GameService orchestrates rooms/rounds/votes.
                 SessionService persists playerId per room (SharedPreferences).
  ↑
state/           Riverpod providers. Stream-based subscriptions wrap repo streams.
  ↑
screens/         Widgets only. Never import repositories directly.
widgets/         Shared UI (GameLayout, PlayerAvatar).
```

Dependencies are wired through `core/service_locator.dart` (GetIt) so tests can swap implementations — the pattern the flutter-tester skill expects.

## How this minimizes database interactions

The original React `useGameState` hook did full refetches on every Realtime event. Specifically, every `votes` insert triggered `fetchVotesForRound + fetchAllVotes` on every connected client, which in turn re-queried all rounds and all question texts.

This port fixes that in four ways:

1. **Streams, not refetches.** `supabase.stream()` emits row-level deltas. When a vote comes in, we receive just that vote and append it to local state — no round-trip back to the database.
2. **Narrow subscription scopes.** Votes are streamed `eq('round_id', currentRoundId)` rather than listening globally and filtering client-side. Other rooms' activity doesn't wake up our client.
3. **Derived state.** `currentRound` is computed from the `rooms` and `rounds` streams instead of being a separate fetch. Question text is resolved from a cached question map, not re-queried per round.
4. **On-demand historic fetches.** `allVotes` is fetched once when the end screen mounts, via a `FutureProvider.autoDispose` — not streamed reactively across the whole game.

Net effect: a single vote goes from ~16 DB reads (4 players × 4 queries) to 0 reads (Realtime delta only). Signaling stays the same; actual queries drop ~80%.

## Key files to read first

- `lib/state/providers.dart` — Riverpod wiring and how streams compose
- `lib/services/game_service.dart` — room lifecycle, round progression
- `lib/repositories/game_repository.dart` — where the query-minimization happens
- `lib/screens/room_screen.dart` — phase routing based on `room.status`

## Testing

Follows the flutter-tester skill's conventions (GetIt, Given-When-Then, layer isolation, override dependencies — don't mock providers).

```bash
flutter test                 # run all
flutter test --coverage      # with coverage
```

Test stubs to add:
- `test/repositories/room_repository_test.dart` — mock `SupabaseClient`
- `test/services/game_service_test.dart` — mock repositories
- `test/state/providers_test.dart` — `createContainer(overrides: [...])`
- `test/screens/lobby_screen_test.dart` — widget test with provider overrides

## Dev mode (solo testing with bots)

Testing a voting game alone is painful — you need 3+ players. Toggle **🧪 Dev mode** on the create-room screen: right after the room is created, 3 bot players (`Bot Alice`, `Bot Bruno`, `Bot Chiara`) are inserted into the `players` table via `DevBotService`. The lobby auto-starts the game once it sees them, and each bot picks a random target and submits a real vote 0.8–3s after the round begins.

The bots go through the same Supabase tables and Realtime streams as humans — no mocking — so this exercises the actual flow. Bots are regular `players` rows and will show up for anyone else in the same room.

Clean up: bots are per-room; end the game (or let it finish naturally) and the `_BotSession` disposes itself.

## Troubleshooting

**"Can't create a room" / nothing happens when I press Crea:** the create-room handler now surfaces the full error in a SnackBar (6s). Likeliest causes:

1. `.env` not loaded. It must live at `flutter_app/.env` AND be declared as an asset in `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - .env
   ```
2. Wrong variable names. The Flutter app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY`. The web app's `.env` uses `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` — copy the values, rename the keys.
3. Supabase RLS blocking anon inserts. Run the web app alongside and compare — if creating a room works there but not here, it's auth/headers, not RLS.
4. On web, CORS from a non-Vercel origin. Add `http://localhost:xxxx` to Supabase Auth → URL Configuration if needed.

**"Peer voting doesn't show up":** check `votes` RLS policy allows anon select, and that Realtime is enabled for `rooms`, `players`, `rounds`, `votes` in Supabase dashboard → Database → Replication.

## Known differences vs. the React app

- Toast notifications use `SnackBar` instead of sonner. Behavior is equivalent.
- No marketing pages ported (`landing-page.html`, `packs.html`). Those should stay as static HTML on Vercel — not worth porting to Flutter.

## What's NOT changed

- Supabase schema — identical, no migrations needed
- Question pack data — reads the same `00000000-0000-0000-0000-000000000001` pack
- Room codes, game rules, max rounds (10), min players (3) — all the same
