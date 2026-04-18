# Mobile app design — vota_amici (Flutter, iOS + Android)

Date: 2026-04-17
Owner: Alessandro
Status: design, reviewed pre-implementation

This document describes how we turn the existing Flutter web app at `flutter_app/` into a real iOS + Android product while (a) keeping the web build unchanged, (b) reusing the match logic as-is today, and (c) leaving a clean seam where local-network / Bluetooth multiplayer can plug in later without a rewrite.

---

## 1. Goals and non-goals

Goals:
- Ship a native iOS and Android app from the same codebase as web.
- Keep the web app exactly as it is today: free-to-play, no landing, no account, no onboarding. It stays a PWA-style link-joining experience.
- Give the mobile app the extra surface that a store app is expected to have: onboarding, optional account, profile, pack browser, recent games.
- Design the match layer so that a future "offline" mode (local LAN or Bluetooth, no internet) can reuse the same `GameService` and screens without touching the repositories or UI.

Non-goals for this first pass:
- Actually implementing LAN/Bluetooth. We design the seam now and stub the transport so that when we add `nearby_connections` or similar later, only one new file appears and no existing file is rewritten.
- Shipping a marketplace, in-app purchases, or paid packs. The pack picker already has coming-soon / 18+ states — those stay visual-only for now.
- Replacing Supabase. The architecture notes already concluded Supabase + Vercel is the right transport for online play.

---

## 2. Ground truth — what's in `flutter_app/` right now

Layering (see `README.md`):

```
models/        Room, Player, Round, Vote, Question, Pack  (pure data)
  ↑
repositories/  RoomRepository, GameRepository              (Supabase only)
  ↑
services/      GameService (match logic), SessionService (browserId prefs),
               DevBotService, ShareService
  ↑
state/         Riverpod providers + StreamProvider.family over repo streams
  ↑
screens/       HomeScreen, RoomScreen (phase router), LobbyScreen,
               VotingScreen, ResultsScreen, EndScreen
```

`GameService` is the match engine. It owns room lifecycle (`createRoom`, `joinRoom`), round progression (`startGame`, `nextRound`, `revealResults`), and vote submission. It talks only to the two repositories — no direct Supabase imports.

Both repositories wrap `SupabaseClient`. They expose:
- Streams for realtime row deltas (`watchRoom`, `watchPlayers`, `watchRounds`, `watchVotesForRound`) — server-side-filtered, so we never receive events for other rooms.
- One-shot reads (`findRoomById`, `findRoomByCode`, `findPlayerById`, `fetchAllVotes`, `fetchAllQuestions`).
- Writes (`createRoom`, `createPlayer`, `setHost`, `submitVote`, `updateRoomStatus`).
- Three Postgres RPCs for atomic transitions: `start_game`, `advance_round`, `reveal_results`. These are the pieces that a non-Supabase transport must emulate locally.

Session identity today is purely client-local: a `browserId` generated in `SessionService` (128 bits of entropy in SharedPreferences) + a per-room `playerId:CODE` cache. There is no user account and no cross-room persistence.

Web is the only platform that's been driven through the full flow. The build.sh script produces the Vercel deploy from `flutter build web`. No iOS/Android config has been generated yet (`flutter create . --platforms=ios,android` hasn't been run on this branch).

---

## 3. Mobile vs. web: what diverges

The rule: **web stays exactly as-is. Everything new is mobile-only, gated by `kIsWeb`.**

Concretely, the router branches at the root:

```dart
// core/router.dart
final routerProvider = Provider<GoRouter>((ref) {
  final initial = kIsWeb ? '/' : '/mobile';
  return GoRouter(
    initialLocation: initial,
    routes: [
      // Web routes — unchanged from today.
      GoRoute(path: '/',          builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/room/:code', builder: (_, s) => RoomScreen(code: s.pathParameters['code']!)),

      // Mobile-only shell with bottom nav.
      ShellRoute(
        builder: (_, __, child) => MobileShell(child: child),
        routes: [
          GoRoute(path: '/mobile',        builder: (_, __) => const MobileHomeTab()),
          GoRoute(path: '/mobile/packs',  builder: (_, __) => const PacksTab()),
          GoRoute(path: '/mobile/profile',builder: (_, __) => const ProfileTab()),
        ],
      ),
      // Onboarding + auth are full-screen, outside the shell.
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/auth',       builder: (_, __) => const AuthScreen()),
    ],
  );
});
```

`/room/:code` is shared — once we're in a room, the same phase router (`RoomScreen`) and phase screens (`LobbyScreen`, `VotingScreen`, ...) serve both web and mobile. This is the point: the match surface is platform-agnostic.

What a new mobile user sees on first launch:

```
first launch
   └─ OnboardingScreen (3 cards: what is this game, packs, privacy)
        └─ "Continua" → AuthScreen
             ├─ "Entra con email" → magic-link flow → MobileHomeTab
             └─ "Gioca come ospite" → MobileHomeTab (no auth)
```

Returning launches skip straight to `MobileHomeTab` (or resume a room if the app was killed mid-game — see §6).

The `MobileHomeTab` is itself richer than the web home screen. It has four regions stacked:
1. A hero ("Bentornato, Ale 👋") with a primary CTA — either "Rientra nella partita" if there's a live room the user is still in, or "Gioca ora" otherwise.
2. A "Unisciti con un codice" field — inline, not hidden behind a sub-mode like web.
3. A "Recenti" strip (stub for now) showing the last 3 rooms the user played in. Requires auth to be meaningful; for guests, it reads from local history.
4. A "Prova un pacchetto" strip that links into `PacksTab`.

The pack picker that lives inside web's `HomeScreen` today (the `_Mode.selectPack` step) is promoted to its own tab on mobile (`PacksTab`), so packs become a first-class surface rather than a step inside "create a room".

---

## 4. Auth — optional, not required

Mobile supports two identities:

Guest mode (default, same as web). The existing `SessionService.browserId()` fingerprint is the identity; nothing new required. All online games work. "Recenti" uses a local store. Profile tab offers "Crea un account per salvare le partite".

Signed-in mode. Supabase Auth magic link (email). Adds `user_id` to player rows so:
- Recent games can be queried across devices.
- Friend lists and invites (future) become possible.
- A phone swap doesn't lose game history.

The `AuthService` is a thin wrapper over `supabase.auth`:

```dart
class AuthService {
  AuthService(this._supabase, this._session);
  final SupabaseClient _supabase;
  final SessionService _session;

  Stream<AuthState> authState() => _supabase.auth.onAuthStateChange;
  User? get currentUser => _supabase.auth.currentUser;

  Future<void> signInWithMagicLink(String email) =>
      _supabase.auth.signInWithOtp(
        email: email,
        emailRedirectTo: 'votaamici://auth-callback',  // deep link handler
      );

  Future<void> signOut() => _supabase.auth.signOut();
  bool get isGuest => currentUser == null;
}
```

RLS policies on `players` / `rooms` stay open to anon (web depends on this). A `user_id` column added to `players` is nullable and only populated when signed in. Guest rows look identical to today's web-produced rows, so there's no behavior divergence inside a game.

Schema addition (one migration):

```sql
alter table public.players add column user_id uuid references auth.users(id);
create index players_user_id_idx on public.players(user_id);
```

No existing query breaks; `user_id` is always nullable.

---

## 5. Reusing the match logic: the transport seam

The current match logic is already well-isolated — `GameService` only knows about `RoomRepository` and `GameRepository`. The crack we open now is at the repository layer:

**Turn the two repositories into interfaces; the current Supabase-backed classes become one concrete implementation. A future `LocalRoomRepository` / `LocalGameRepository` will be the offline implementation.**

This is the smallest change that unlocks offline. No refactor of `GameService`, no touching of screens, no Riverpod provider changes. `service_locator.dart` is the only file that chooses which implementation to wire up at boot, and we pick based on whether we're in an online or local session.

Concretely:

```dart
// repositories/room_repository.dart — becomes abstract.
abstract class RoomRepository {
  Future<Room?> findRoomByCode(String code);
  Future<Room?> findRoomById(String id);
  Stream<Room?>   watchRoom(String roomId);
  Stream<List<Player>> watchPlayers(String roomId);
  Future<Room> createRoom({...});
  Future<Player> createPlayer({...});
  Future<Player?> findPlayerById(String id);
  Future<Player?> findPlayerByRoomAndBrowser({...});
  Future<void> setHost(String roomId, String playerId);
  Future<void> updateRoomStatus(String roomId, {RoomStatus? status, int? currentRound});
}

// repositories/supabase_room_repository.dart — the current concrete class,
// renamed. Implementation unchanged.
class SupabaseRoomRepository implements RoomRepository { /* … */ }

// repositories/local_room_repository.dart — new, stubbed.
//
// Runs the room authoritatively on the HOST device. Broadcasts state
// deltas to connected guests over a MatchTransport (LAN/BT).
// Guests' LocalRoomRepository mirrors the host's state read-only and
// sends writes (votes, join requests) back as transport frames.
class LocalRoomRepository implements RoomRepository {
  LocalRoomRepository({required MatchTransport transport, required LocalRole role});
  /* TODO: implement against an in-memory store + transport */
}
```

Same split for `GameRepository`. The three Postgres RPCs (`start_game`, `advance_round`, `reveal_results`) become in-process methods on `LocalGameRepository` — the host just runs the SQL body's logic in Dart (it's a few lines of "update status, insert next round, bump round number").

### The `MatchTransport` contract

This is the one new abstraction. It's what `LocalRoomRepository` / `LocalGameRepository` sit on top of, and it's what a `nearby_connections` plugin, a WebRTC mesh, or an in-process loopback (for tests) will implement:

```dart
/// Bidirectional frame-based transport between a host device and N guests
/// on the same local network. Not used by the Supabase path at all.
abstract class MatchTransport {
  /// Role of this device for the current session.
  LocalRole get role;

  /// Frames received from the other end. On the host, this is every guest's
  /// frames multiplexed together. On guests, this is only the host.
  Stream<TransportFrame> incoming();

  /// Send a frame. On the host, [to] targets a specific guest (or null to
  /// broadcast). On guests, [to] is ignored — frames always go to the host.
  Future<void> send(TransportFrame frame, {String? to});

  /// Connected peers. On the host, the set of guests currently reachable.
  /// On guests, a singleton with the host only.
  Stream<Set<String>> peers();

  Future<void> close();
}

enum LocalRole { host, guest }

/// Frame kinds map 1:1 onto repository operations. This is the contract.
sealed class TransportFrame {
  const TransportFrame();
}
class JoinRequestFrame  extends TransportFrame { /* name, browserId */ }
class StateDeltaFrame   extends TransportFrame { /* room, players, rounds, votes */ }
class VoteFrame         extends TransportFrame { /* roundId, voterId, votedForId */ }
class AdvanceRoundFrame extends TransportFrame { /* issued by host only */ }
class RevealFrame       extends TransportFrame { /* issued by host only */ }
class ErrorFrame        extends TransportFrame { /* message */ }
```

`LocalRoomRepository` + `LocalGameRepository` translate repository calls into frames. `watchRoom` on a guest is just "the latest `StateDeltaFrame.room` seen on `incoming()`". `submitVote` on a guest is "send a `VoteFrame`; the host will accept it and broadcast an updated state delta".

For local tests, `InMemoryMatchTransport` is a dart-only pair that loops frames between a host and N guests with zero I/O — this is what the contract test uses.

### Why at the repository layer and not higher

Two alternatives I rejected:

Pushing the transport seam above `GameService` — i.e. `OnlineGameService` vs `LocalGameService`. It duplicates all the room-lifecycle code (name de-duplication, rejoin priority, question caching, round-scoping), which is exactly the code we want to test once and use everywhere. The current `GameService` is transport-agnostic by accident; we want to make it transport-agnostic by contract, and the cleanest way to do that is below it.

Pushing it below the repositories — i.e. introducing a `DataSource` layer that both repositories wrap. That adds a layer for a gain we don't have a use case for; the repositories are already the narrow surface we need.

The repository-layer split is also the point at which the existing Riverpod providers don't care which backend is live. `locator<RoomRepository>()` resolves either to Supabase or local at boot; everything above is unchanged.

---

## 6. Mobile-only platform concerns

Background/foreground resume. When the app is backgrounded during a round and comes back, today's code reconnects the Supabase Realtime subscription because Riverpod re-runs the stream builders on `invalidate`. We need a `resumeRoomRoute` that restores the user to `/room/CODE` if a room was active when the app was killed, driven by a persisted "last-active room code" in `SessionService`.

Push notifications (post-v1). "È il tuo turno" notifications from Supabase Edge Functions triggered by `advance_round`. Not in scope for first release.

Deep links. `votaamici://room/ABCDE` for invite links from messaging apps. iOS Universal Links + Android App Links should both route through the same `/room/:code` path; the existing path-based URL strategy already handles this cleanly.

Keyboard behavior. `TextField` in `HomeScreen` currently assumes desktop keyboard dismissal; on mobile we need `SingleChildScrollView` + `resizeToAvoidBottomInset` + `Focus.unfocus()` on tap-outside so the keyboard covering the CTA doesn't trap users.

App icons, splash, store assets. Generated from the existing hero mark. Not architecturally interesting, but needs to land before beta.

Accessibility. Voice Control on iOS / TalkBack on Android pick up `Semantics` labels. The current screens don't set any. Audit before release.

---

## 7. Test strategy

Four tiers, bottom-up:

### 7a. Service-layer unit tests (expand what exists)

`test/services/game_service_test.dart` already covers the `joinRoom` rejoin matrix. Expand to cover the other service methods, because they currently have zero coverage and they are the most critical code in the app:

- `createRoom` — with/without pack, empty modes collapses to all modes, browserId is stamped on the host row, `setHost` called with the right id.
- `startGame` — empty question pool throws, first question drawn only from pack + modes scope, falls back to "all packs" when pack has no seeded questions.
- `nextRound` — already-used questions are excluded; exhausted pool flips room to `finished`; `kMaxRounds` cap triggers `finished`.
- `revealResults` — delegates to the RPC; no double-fire.

Pattern: Given-When-Then, mocked repositories per flutter-tester skill, regenerate mocks with build_runner.

### 7b. Repository contract test (the important new piece)

One test file, two implementations run through it. This is what makes the transport seam real rather than just a type:

- `test/repositories/room_repository_contract_test.dart`
- `test/repositories/game_repository_contract_test.dart`

Each file defines a set of abstract behaviors ("given createRoom then findRoomByCode returns it", "given a player joins then watchPlayers emits them", "given submitVote then watchVotesForRound emits the vote") and runs them against:
1. An in-memory fake repository (for now, this is all that exists — `FakeRoomRepository`, `FakeGameRepository` — backed by plain Dart maps).
2. Later: the Supabase implementation against a local Supabase container (via docker-compose).
3. Later: the local-transport implementation against an `InMemoryMatchTransport`.

The contract test is the spec. Any new transport has to pass it or it's broken. The first cut lands now with only the fake implementation so the contract is written down and exercised.

### 7c. Widget tests with provider overrides

Per flutter-tester skill: `createContainer(overrides: [roomRepositoryProvider.overrideWithValue(FakeRoomRepository(...))])`. Screens that matter to test first:

- `MobileHomeTab` — renders "Rientra" CTA when there's a persisted active room; renders "Gioca ora" otherwise; join-by-code field validates length.
- `OnboardingScreen` — "Continua come ospite" skips auth; "Entra con email" navigates to `AuthScreen`.
- `LobbyScreen` — already painful to test given the countdown animations, but a smoke test ("renders all players, CTA enabled at 3 players") catches regressions.

### 7d. Integration smoke

One golden flow driven end-to-end against a real Supabase dev project: create room → join 3 bots → play 3 rounds → reveal → end. This is what `DevBotService` already enables; promote it from a dev toggle to a CI-runnable integration target. Not a blocker for v1.

### What the first-commit test deliverable looks like

1. The contract test file for `RoomRepository` runs against an in-memory fake and passes.
2. The existing `game_service_test.dart` grows 4-5 new tests for `createRoom` / `startGame` / `nextRound`.
3. No CI integration yet.

This is enough to anchor the design in verifiable behavior without spending a week on test infra.

---

## 8. Phased implementation plan

Each phase is sized so it can ship behind its own PR and the previous phase is still deployable on web.

### Phase 0 — Platform scaffolding (1 day)

Run `flutter create . --platforms=ios,android` in `flutter_app/` to generate the iOS and Android projects (idempotent, doesn't touch `lib/` or `pubspec.yaml`). Set app icons, splash, bundle ids. Wire deep-link handlers for `votaamici://room/...`. Web build untouched.

### Phase 1 — Repository interfaces (1-2 days, no behavior change)

Lift `RoomRepository` and `GameRepository` to abstract classes. Rename current classes to `SupabaseRoomRepository` / `SupabaseGameRepository`. Add `FakeRoomRepository` / `FakeGameRepository` for tests. `service_locator.dart` still wires Supabase by default. Contract test lands with the fake impl.

After this phase, the web build is bit-identical and the service layer tests can run without touching Supabase.

### Phase 2 — Mobile shell + onboarding (2-3 days)

Add `MobileShell`, `MobileHomeTab`, `PacksTab`, `ProfileTab`, `OnboardingScreen`, `AuthScreen`. Gate on `kIsWeb` in the router. Web stays on `HomeScreen` as today.

Add `AuthService` and the `user_id` column migration. `MobileHomeTab` shows "Gioca ora" which routes into the existing `HomeScreen` create-flow (we can embed or duplicate the create form — duplicating is fine given how little logic is in the form itself). All online play goes through the existing Supabase path.

### Phase 3 — Store-shippable beta (1-2 days)

App icons, splash, store listings, accessibility pass, resume-to-active-room logic. Push TestFlight + Play Internal builds. This is where we validate that the mobile UX actually works before pouring effort into offline.

### Phase 4 — Offline transport (1 week, gated on Phase 3 feedback)

Add `MatchTransport` interface and `InMemoryMatchTransport`. Add `LocalRoomRepository` / `LocalGameRepository` that implement the same contract as Supabase. Contract test runs them and proves behavior parity. UI: add a "Gioca offline" option on `MobileHomeTab` that creates a local-host session and shows a QR code.

Pick the real transport plugin: `nearby_connections` on Android is first-party and works offline; iOS MultipeerConnectivity via `flutter_nearby_connections` or similar. Start with a single cross-platform plugin that speaks both.

### Phase 5 — Polish (ongoing)

Push notifications, friend lists, cross-device recent games. Each lands on top of the account plumbing from Phase 2.

---

## 9. Open questions to decide before Phase 2

- Auth: magic link only, or also Apple Sign In (required for iOS if any third-party sign-in is offered) and Google Sign In?
- Is guest mode a persistent choice or a one-time "skip" that keeps nagging to sign up? First feel: nag gently from Profile tab, don't block Play.
- Packs tab — does this become a storefront eventually, or is it forever a static catalog? The `PackStatus.comingSoon` / `ageRestricted` enums suggest we've already reserved space for paid packs.
- For offline mode, what's the minimum player count? Couples pack at 2 works beautifully offline; classic at 3-8 needs real discovery/join UX.

---

## 10. Summary

The existing `flutter_app/` is already the right foundation. The work is: (a) turn the two repositories into interfaces so the match engine is transport-agnostic (Phase 1), (b) build the mobile-only shell around the existing room flow (Phase 2), (c) ship a store beta (Phase 3), (d) plug in a local-transport repository implementation when we're ready for offline (Phase 4). Web doesn't change at any point. The contract test is the linchpin — it's what lets us swap transports with confidence.
