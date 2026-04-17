-- Round transition RPCs.
--
-- Collapses the multi-step startGame / nextRound / revealResults flows from
-- GameService into single Postgres functions, each guarded by a FOR UPDATE
-- row lock on `rooms`. This gives us:
--
--   * One network round-trip per transition instead of 2–5.
--   * Atomicity: either all of (close prev round, insert new round, bump
--     room.current_round) commits, or none of it does.
--   * Concurrency safety: two clients racing a transition serialize behind
--     the room lock; the second call takes the idempotent branch instead of
--     inserting a duplicate round_number.
--
-- Paired with the UNIQUE(room_id, round_number) constraint below as
-- belt-and-braces: even if the function were bypassed, the database would
-- refuse a second insert at the same round_number.
--
-- Realtime: `rooms` and `rounds` are already in the supabase_realtime
-- publication (see 20260307175211_*.sql). Every row affected by these
-- functions still fires postgres_changes events at commit, so existing
-- Flutter streams pick up the new state without any client subscription
-- changes.

-- ---------------------------------------------------------------------------
-- One-time cleanup: dedupe ghost rounds left over from the pre-RPC days.
-- ---------------------------------------------------------------------------
-- When the old multi-step nextRound/startGame flow raced (double-tap,
-- two tabs), it could insert two `rounds` rows with the same
-- (room_id, round_number). Those rows block the unique constraint
-- below, so we need to resolve them first.
--
-- Policy: for each colliding group, keep the row with the most votes;
-- tie-break on oldest `created_at`. The deleted rows' votes cascade
-- away via the existing ON DELETE CASCADE on `votes.round_id` — for a
-- friends game that's acceptable data loss on rounds that were
-- effectively abandoned anyway. Merging votes instead would risk
-- violating the `UNIQUE (round_id, voter_id)` constraint.
--
-- This block is safe to re-run: on a clean database it selects no
-- rows and deletes nothing.

WITH ranked_rounds AS (
  SELECT
    r.id,
    ROW_NUMBER() OVER (
      PARTITION BY r.room_id, r.round_number
      ORDER BY
        (SELECT COUNT(*) FROM public.votes v WHERE v.round_id = r.id) DESC,
        r.created_at ASC
    ) AS rn
  FROM public.rounds r
)
DELETE FROM public.rounds
 WHERE id IN (SELECT id FROM ranked_rounds WHERE rn > 1);

-- ---------------------------------------------------------------------------
-- Idempotency constraint
-- ---------------------------------------------------------------------------
-- Guarded so re-running the migration is safe (Postgres' ADD CONSTRAINT
-- does not support IF NOT EXISTS for UNIQUE).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'rounds_room_id_round_number_key'
  ) THEN
    ALTER TABLE public.rounds
      ADD CONSTRAINT rounds_room_id_round_number_key
      UNIQUE (room_id, round_number);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- start_game(room_id, first_question_id)
-- ---------------------------------------------------------------------------
-- Lobby → in_round, round 1. Returns void; the client picks up the new
-- round via the existing watchRounds stream. Idempotent: if any round
-- already exists for the room, just bumps the room status to `in_round`
-- at the highest existing round_number and exits.

CREATE OR REPLACE FUNCTION public.start_game(
  p_room_id uuid,
  p_first_question_id uuid
) RETURNS void AS $$
DECLARE
  v_room public.rooms%ROWTYPE;
  v_existing_round public.rounds%ROWTYPE;
BEGIN
  SELECT * INTO v_room FROM public.rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'room not found: %', p_room_id;
  END IF;

  -- Idempotency: mirrors the Dart guard we're replacing
  -- (game_service.dart:199). A duplicate `Start` tap or a lobby auto-start
  -- racing a manual click ends up here on the second caller.
  SELECT * INTO v_existing_round
    FROM public.rounds
   WHERE room_id = p_room_id
   ORDER BY round_number DESC
   LIMIT 1;

  IF FOUND THEN
    UPDATE public.rooms
       SET status = 'in_round',
           current_round = v_existing_round.round_number
     WHERE id = p_room_id;
    RETURN;
  END IF;

  INSERT INTO public.rounds (room_id, question_id, round_number, status)
  VALUES (p_room_id, p_first_question_id, 1, 'voting');

  UPDATE public.rooms
     SET status = 'in_round',
         current_round = 1
   WHERE id = p_room_id;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- advance_round(room_id, next_question_id)
-- ---------------------------------------------------------------------------
-- Closes the current round, inserts the next round, bumps
-- rooms.current_round. Idempotent: if round `current_round + 1` already
-- exists (double-tap, two clients racing) we take the existing row and
-- just bump the room status — matches the Dart guard at
-- game_service.dart:274.

CREATE OR REPLACE FUNCTION public.advance_round(
  p_room_id uuid,
  p_next_question_id uuid
) RETURNS void AS $$
DECLARE
  v_room public.rooms%ROWTYPE;
  v_next_number int;
  v_existing public.rounds%ROWTYPE;
BEGIN
  SELECT * INTO v_room FROM public.rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'room not found: %', p_room_id;
  END IF;

  v_next_number := v_room.current_round + 1;

  -- Idempotent short-circuit: the next round already exists.
  SELECT * INTO v_existing
    FROM public.rounds
   WHERE room_id = p_room_id AND round_number = v_next_number;
  IF FOUND THEN
    UPDATE public.rooms
       SET status = 'in_round',
           current_round = v_next_number
     WHERE id = p_room_id;
    RETURN;
  END IF;

  -- Close the previous round. Guard on status <> 'closed' so a retry
  -- (unlikely but cheap) doesn't fire an unnecessary UPDATE.
  UPDATE public.rounds
     SET status = 'closed'
   WHERE room_id = p_room_id
     AND round_number = v_room.current_round
     AND status <> 'closed';

  INSERT INTO public.rounds (room_id, question_id, round_number, status)
  VALUES (p_room_id, p_next_question_id, v_next_number, 'voting');

  UPDATE public.rooms
     SET status = 'in_round',
         current_round = v_next_number
   WHERE id = p_room_id;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- reveal_results(room_id, round_id)
-- ---------------------------------------------------------------------------
-- Flips the given round to 'revealed' and the room to 'results', in a
-- single transaction. Idempotent: a second call while already in
-- 'results' is a no-op.

CREATE OR REPLACE FUNCTION public.reveal_results(
  p_room_id uuid,
  p_round_id uuid
) RETURNS void AS $$
BEGIN
  -- Lock the room to serialize against any concurrent advance_round /
  -- start_game call. Without this a "Reveal" tap racing a "Next" tap
  -- could interleave the two UPDATEs on `rooms` in a confusing order.
  PERFORM 1 FROM public.rooms WHERE id = p_room_id FOR UPDATE;

  UPDATE public.rounds
     SET status = 'revealed'
   WHERE id = p_round_id
     AND status = 'voting';

  UPDATE public.rooms
     SET status = 'results'
   WHERE id = p_room_id
     AND status <> 'results';
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- Grant execute to the PostgREST roles used by the Flutter client.
-- ---------------------------------------------------------------------------
-- `anon` covers unauthenticated client calls (current state — no auth),
-- `authenticated` covers the post-auth path once we add Supabase Auth.
-- Keeping both future-proofs the migration against the auth rollout that
-- the architecture notes flag for a later pass.

GRANT EXECUTE ON FUNCTION public.start_game(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.advance_round(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reveal_results(uuid, uuid) TO anon, authenticated;
