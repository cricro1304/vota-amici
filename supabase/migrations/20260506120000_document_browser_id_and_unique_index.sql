-- Documents the `browser_id` column on `public.players` and adds a
-- partial UNIQUE index that prevents same-browser-same-room duplicates.
--
-- Background: the column was added directly to the live database without
-- a corresponding migration file, so `schema-as-code` was broken. Both
-- statements use IF NOT EXISTS so this migration is idempotent on the
-- prod DB where the column already exists with this exact shape.
--
-- The column is used by `RoomRepository.findPlayerByRoomAndBrowser` as
-- a secondary rejoin signal when the per-room `playerId:CODE` cache in
-- SharedPreferences is missing (different browser-but-same-device,
-- private tab, cleared storage, Vercel preview ↔ prod origin swap).

ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS browser_id TEXT;

-- Partial UNIQUE index, NOT a UNIQUE constraint, because:
--   - We need the WHERE clause to skip NULL rows (bots seeded by
--     DevBotService and any historical pre-migration rows). PostgreSQL
--     would treat NULLs as distinct in a regular UNIQUE constraint
--     anyway, but writing it as a partial index makes that intent
--     explicit and rejects future schema changes that try to fold the
--     column into a multi-column UNIQUE without reconsidering NULLs.
--   - Backfilling a UNIQUE constraint on an existing table would error
--     if any duplicates existed; the prod DB has zero duplicates today
--     (verified before applying), so this index creates cleanly.
--
-- Effect: any future race that tried to insert a second
-- `(room_id, browser_id)` row will get a 23505 unique-violation error
-- from Postgres instead of silently producing a duplicate player. The
-- application layer (GameService.joinRoom) already returns the existing
-- row before reaching the insert when browser_id matches, so this is
-- defense-in-depth, not a primary path.
CREATE UNIQUE INDEX IF NOT EXISTS players_room_browser_unique_idx
  ON public.players (room_id, browser_id)
  WHERE browser_id IS NOT NULL;
