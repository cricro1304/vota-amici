# Architecture Notes & Observed Issues

Running log of bugs, smells, and optimization opportunities found while reviewing the codebase. Add to this as we go.

---

## Verdict on current architecture (2026-04-14)

**Supabase + Vercel is suitable for this game.** The game is turn-based voting — low message frequency, seconds between actions, not milliseconds. Postgres-as-source-of-truth gives you persistence, reconnection, late joiners, and spectator support essentially for free. WebRTC would only pay off if adding latency-sensitive games (drawing, reflex, live cursors) OR if Supabase costs become material (~10K+ games/month on free tier).

Recommendation: **stay on current architecture**, optimize Realtime chattiness instead of refactoring transport.

---

## Observed issues / opportunities

### 1. Over-fetching on every vote insert
**File:** `src/hooks/useGameState.ts` (lines ~132–140)
**Issue:** Every `INSERT` on `votes` triggers BOTH `fetchVotesForRound` AND `fetchAllVotes`. The latter refetches ALL rounds, ALL votes, AND all question texts for the entire room — for every player, on every vote.
**Impact:** With 4 players and 10 rounds, a single vote causes 4 clients × (1 votes-for-round query + 1 rounds query + 1 all-votes query + 1 questions query) = 16 DB reads. Multiply by votes per game and it adds up fast.
**Fix idea:** Only call `fetchAllVotes` when transitioning to results screen, not on every vote insert. The "all rounds history" view doesn't need to update mid-round.

### 2. Realtime votes filter is too broad
**File:** `src/hooks/useGameState.ts` (line ~132)
**Issue:** The `votes` subscription has no filter — it listens to ALL vote inserts globally, then filters client-side via `currentRoundIdRef`. Other rooms' vote inserts will wake up this client.
**Fix idea:** Add a filter scoped to the current room's round IDs, or subscribe per-round.

### 3. Race in `currentRoundIdRef`
**File:** `src/hooks/useGameState.ts`
**Issue:** `currentRoundIdRef.current` is set inside an async fetch. If a vote insert event fires before `fetchCurrentRound` completes after a round transition, the ref may point to the previous round (or null).
**Severity:** Low — likely manifests as a brief stale-vote display, self-corrects on next event.

### 4. Multiple stale Vite config timestamps
**Files:** `vite.config.ts.timestamp-*.mjs` (3 files)
**Issue:** Stale build artifacts committed/present in repo root. Should be gitignored and removed.

---

## To verify next session
- Confirm vote-insert flow in `Room.tsx` (have not read yet)
- Check whether host-leaves-room scenario is handled
- Review RLS policies on the migrations
