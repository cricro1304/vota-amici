# Architecture Notes & Observed Issues

Running log of bugs, smells, and optimization opportunities found while reviewing the codebase. Add to this as we go.

---

## Verdict on current architecture (2026-04-14)

**Supabase + Vercel is suitable for this game.** The game is turn-based voting — low message frequency, seconds between actions, not milliseconds. Postgres-as-source-of-truth gives you persistence, reconnection, late joiners, and spectator support essentially for free. WebRTC would only pay off if adding latency-sensitive games (drawing, reflex, live cursors) OR if Supabase costs become material (~10K+ games/month on free tier).

Recommendation: **stay on current architecture**, optimize Realtime chattiness instead of refactoring transport.

---

## Update 2026-04-17 — status after the Flutter rewrite

The React/Vite client was replaced with a Flutter Web app in commit `a2e7086` (2026-04-15) and cleaned up in `e0c99cc`. The notes below were all written against the old `src/hooks/useGameState.ts`, which no longer exists. The rewrite uses Riverpod + Supabase Realtime streams that are **filtered server-side** and derives the "current round" synchronously from existing streams, so the three runtime issues listed below are resolved by construction rather than by a targeted patch. File references in each section have been updated to the Flutter equivalents.

---

## Observed issues / opportunities

### 1. Over-fetching on every vote insert — RESOLVED (2026-04-17)

**Old file:** `src/hooks/useGameState.ts` (React, removed)
**New file:** `flutter_app/lib/repositories/game_repository.dart:68`, `flutter_app/lib/services/game_service.dart:24-30`

In the React version, every `INSERT` on `votes` ran BOTH `fetchVotesForRound` and `fetchAllVotes`; the latter re-fetched all rounds, all votes, and all question texts for the room. With 4 players and 10 rounds a single vote caused roughly 4 clients × 4 queries = 16 DB reads.

The Flutter rewrite removed this entirely. `GameRepository.watchVotesForRound(roundId)` returns a Supabase Realtime stream scoped to a single round; Supabase sends row deltas, so clients do not re-query on each vote. `fetchAllVotes` is now an explicit one-shot, called only when the end screen is rendered (it's documented in the repository as "fetched once on demand for the end screen, NOT streamed"). Questions are cached for the lifetime of the app session in `GameService._questionCache`, so round transitions no longer trigger a question re-fetch either.

### 2. Realtime votes filter is too broad — RESOLVED (2026-04-17)

**Old file:** `src/hooks/useGameState.ts` (React, removed)
**New file:** `flutter_app/lib/repositories/game_repository.dart:68-74`

The old `.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'votes' }, …)` subscription had no filter and every client received vote INSERTs from every room, filtering client-side via `currentRoundIdRef`.

The Flutter streams all apply server-side filters: `watchVotesForRound` filters by `round_id=eq.{roundId}`, `watchRoom` by `id=eq.{roomId}` (`room_repository.dart:39`), `watchPlayers` by `room_id=eq.{roomId}` (`room_repository.dart:86`), and `watchRounds` by `room_id=eq.{roomId}` (`game_repository.dart:17`). Supabase Realtime applies the filter before pushing, so events from other rooms never reach this client.

### 3. Race in `currentRoundIdRef` — RESOLVED (2026-04-17)

**Old file:** `src/hooks/useGameState.ts` (React, removed)
**New file:** `flutter_app/lib/state/providers.dart:52-70`

The old code stored the active round id in a mutable `useRef` that was populated inside an async fetch; a vote-insert event arriving between the round transition and the fetch completing could read a stale id (or null).

The Flutter version replaces the imperative ref with a **derived** provider. `currentRoundProvider` computes the active round synchronously by matching `room.currentRound` against the already-streamed rounds list, and `currentRoundVotesProvider` reactively re-watches that derived value. When the round changes, Riverpod tears down the old vote stream and subscribes to the new one atomically — there is no mutable state to race against.

### 4. Stale Vite config timestamps — RESOLVED (2026-04-17)

The `vite.config.ts.timestamp-*.mjs` files are gone; no `vite.config*` exists anywhere in the repo now that the Vite build has been replaced with the Flutter build in `build.sh`.

---

## Cheaper transport protocols — what to consider

The current design is cheap per-event (filtered streams, no refetch storms), but every vote is still a row INSERT that gets replicated through `postgres_changes` to every subscriber. For a room with N players over R rounds that's roughly N·R vote INSERTs and on the order of N²·R realtime messages, on top of the per-round room/round writes. Several options would cut DB operations further, each with its own trade-off. I'd order them from "safest win" to "only if we grow".

**A. Consolidate round transitions into a single Postgres RPC.** `GameService.nextRound` currently does four separate round-trips against Supabase: `fetchRoundsForRoom`, `updateRoundStatus` on the old round, `createRound` for the new round, and `updateRoomStatus`. Collapsing these into one `advance_round(room_id, prev_round_id)` SQL function would drop the round-transition cost from four round-trips to one, run the idempotency check (duplicate `round_number`) as a server-side CAS instead of a Dart-side re-fetch, and remove a whole class of "two clients tapped Next at the same time" races. Same story for `startGame` (three writes). This is the change with the best risk/reward ratio: no protocol change, no client complexity, immediate latency win, and the Dart-side idempotency guards in `game_service.dart:199` and `game_service.dart:274` become obsolete.

**B. Live votes over Supabase Broadcast, persist only the tally.** Instead of inserting one row per vote and relying on `postgres_changes` replication, each client could publish its vote to a per-room Supabase Broadcast channel and one designated aggregator (the host, or whichever client holds a "leader" lock) writes a single `round_results` row at reveal time. Broadcast messages don't touch Postgres or the WAL, so this converts N vote INSERTs + N replicated deltas per round into N broadcast frames and one INSERT — roughly an N× reduction in write volume. The cost is reconnection logic: a late joiner or a reconnecting client has no DB trail to catch up on for the *current* round, so we'd need either a "request snapshot" broadcast message or a tolerance for "your vote won't appear until reveal if you rejoin mid-round". Worth doing if we see Realtime usage become the dominant cost driver, or if we add modes with many votes per round (e.g. multi-choice or ranking).

**C. Presence for lobby membership.** `_uniqueNameFor` in `game_service.dart:165` takes the first frame of the players stream to detect name collisions, which is fine but still a DB-backed subscription. Replacing the lobby view of `players` with a Supabase Presence channel — where join/leave is a client-emitted event, not a DB write — would remove the `players` INSERT at join time (we'd only write to `players` once the player commits to starting a round) and eliminate the lobby-only realtime subscription. Modest win on its own, but it composes well with option B. Trade-off: presence state is ephemeral, so cached-playerId rejoin (`game_service.dart:120-125`) has to keep working off the DB row once the player is persisted.

**D. Server-authoritative round ticker via an Edge Function.** A scheduled or triggered Edge Function that owns the timer and round transitions removes the "which client presses Next" coordination entirely. Clients only ever INSERT a vote; the server decides when the round closes (all players voted OR timer elapsed) and writes the transition atomically. Combined with option A, this makes the client layer pure input/display. The cost is cold-start latency and a second runtime to maintain; it's the right move if we start seeing dropped hosts mid-game, because the Edge Function becomes the source of truth instead of whichever client happens to be connected.

**E. Collapse `votes` into a JSONB column on `rounds`.** Store the round's votes as a single `votes_jsonb` field on the `rounds` row; each vote becomes an UPDATE on that row rather than an INSERT on a separate table. Halves the row count and the replication traffic, and makes "all votes for a round" a single column read. Not recommended: all N voters now contend on the same row, which means either optimistic concurrency failures or a server-side merge function, and we lose the per-vote audit trail (`created_at`, individual deletability) that makes debugging easy. Only worth it at a scale where we're genuinely being billed by row count.

**F. WebRTC mesh for live events.** Covered in the top-level verdict: the game's voting frequency is measured in seconds, not milliseconds, so the latency upside is essentially zero, and we'd take on all the signaling and NAT-traversal complexity without a corresponding product benefit. Revisit only if we add a drawing or reflex mode.

**Recommended next step.** If we pick one thing to do, it's A. It ships as a migration + a single service method swap, has no user-visible behavior change, measurably reduces per-round round-trips, and removes both existing race-guards in `GameService`. B is where the real scaling headroom is, but it's a bigger design change and should wait until Realtime usage actually shows up in the cost dashboard.

---

## To verify next session

Confirm the host-leaves-room scenario is still handled by the browser-id rejoin path (`game_service.dart:130-138`) — the notes from before the rewrite flagged this as unreviewed. Review RLS policies on the migrations in `supabase/migrations/` now that the Flutter client talks to the same tables.
