# Option B — Broadcast-based live voting

Design draft for reducing the per-round write volume on Supabase by moving live vote transport off `postgres_changes` and onto Supabase Broadcast, while keeping Postgres as the source of truth for persistence and the end screen. Companion to the "Cheaper transport protocols" section in `architecture-notes.md`.

## Why

Every vote today is a row INSERT into `public.votes`. With N players and R rounds a finished game produces N·R vote rows, each one replicated through the `supabase_realtime` publication to every subscriber in the room. At steady state the replication traffic scales as N²·R. It's fine at current volume, but it's the single biggest knob we can turn if Realtime usage starts showing up on the cost dashboard, and it's the only transition-related change that isn't already covered by the RPC migration.

Option A (the RPC migration that shipped in `20260417093000_add_round_transition_rpcs.sql`) collapses per-round *transition* writes from 4-5 down to 1. Option B targets the per-round *vote* writes: N INSERTs become one, via a single batch persist at reveal time.

## Target architecture

Per room we open one Supabase Broadcast channel, name `room:{roomId}`. Votes are emitted as broadcast messages and **not** persisted individually. Each client subscribes to the channel and accumulates a local view of votes for the current round. When the host taps "Reveal" (or the timer expires), the reveal RPC atomically writes all votes for the round plus the status flips, in a single transaction.

The `votes` table stays exactly as it is — same columns, same `UNIQUE (round_id, voter_id)` constraint, same end-screen queries — it just receives one INSERT per round instead of N. The key change on the database side is that `votes` is removed from the `supabase_realtime` publication, so it no longer replicates row deltas; live vote state flows through broadcast instead.

## Data flow, step by step

Round opens via `advance_round` (Option A). Every client subscribed to the room already watches `rounds` via realtime and notices the new row, so each client initializes a local `Map<voterId, votedForId>` for the new `round_id`.

A player casts their vote. The voting screen calls a new `voteLocally` service method which:
- stores the vote in the local map (for optimistic UI: the player sees their own vote applied immediately, same as today)
- broadcasts `{type: 'vote', roundId, voterId, votedForId}` on `room:{roomId}`

Every other client receives the broadcast and merges it into its own local map. Because the map is keyed by `voterId`, duplicate broadcasts (reconnect-replay, accidental double-emit) collapse to the same state — idempotent by construction. The `currentRoundVotesProvider` in `state/providers.dart:65-70` is replaced by a provider that exposes this in-memory map instead of the DB stream; the voting and results screens read from it with no other changes.

When the host taps "Reveal" the client calls `reveal_round_with_votes(room_id, round_id, votes_jsonb)`, passing the locally-aggregated vote map as a JSON array. The RPC:
1. Locks `rooms` FOR UPDATE (same pattern as Option A).
2. Checks whether the round is already `revealed`. If so, returns — idempotent.
3. Inserts every vote row in one statement: `INSERT INTO votes (round_id, voter_id, voted_for_id) SELECT … FROM jsonb_to_recordset(…) ON CONFLICT (round_id, voter_id) DO NOTHING`.
4. Updates `rounds.status` to `revealed` and `rooms.status` to `results`.
5. Commits.

All subscribers see the `rounds` and `rooms` updates through existing realtime streams and transition to the results screen, exactly as they do today. The end screen reads from `votes` unchanged — it was already an on-demand one-shot fetch, not a stream.

## Sketch: the RPC

```sql
CREATE OR REPLACE FUNCTION public.reveal_round_with_votes(
  p_room_id uuid,
  p_round_id uuid,
  p_votes  jsonb  -- [{ "voter_id": "…", "voted_for_id": "…" }, …]
) RETURNS void AS $$
BEGIN
  PERFORM 1 FROM public.rooms WHERE id = p_room_id FOR UPDATE;

  -- Idempotency: if the round is already revealed, do nothing. Prevents
  -- a second "Reveal" tap (or a reconnecting client re-firing the RPC)
  -- from double-inserting votes.
  IF EXISTS (
    SELECT 1 FROM public.rounds
    WHERE id = p_round_id AND status = 'revealed'
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.votes (round_id, voter_id, voted_for_id)
  SELECT p_round_id,
         (v->>'voter_id')::uuid,
         (v->>'voted_for_id')::uuid
    FROM jsonb_array_elements(p_votes) AS v
  ON CONFLICT (round_id, voter_id) DO NOTHING;

  UPDATE public.rounds SET status = 'revealed' WHERE id = p_round_id;
  UPDATE public.rooms  SET status = 'results'   WHERE id = p_room_id;
END;
$$ LANGUAGE plpgsql;
```

Paired with `ALTER PUBLICATION supabase_realtime DROP TABLE public.votes;` in the same migration so the vote INSERTs don't generate realtime traffic on top of what's already being broadcast.

## Sketch: the Dart layer

A new class `LiveVoteChannel` owns the broadcast side per room. Instantiated on room-load, disposed on leave.

```dart
class LiveVoteChannel {
  LiveVoteChannel(this._client, this._roomId) {
    _channel = _client.channel('room:$_roomId')
      ..onBroadcast(
        event: 'vote',
        callback: (payload) => _apply(payload),
      )
      ..subscribe();
  }

  final SupabaseClient _client;
  final String _roomId;
  late final RealtimeChannel _channel;

  // round_id → (voter_id → voted_for_id)
  final _votesByRound = <String, Map<String, String>>{};
  final _controller = StreamController<Map<String, Map<String, String>>>.broadcast();
  Stream<Map<String, Map<String, String>>> get stream => _controller.stream;

  Future<void> castVote({
    required String roundId,
    required String voterId,
    required String votedForId,
  }) async {
    _apply({'roundId': roundId, 'voterId': voterId, 'votedForId': votedForId});
    await _channel.sendBroadcastMessage(
      event: 'vote',
      payload: {
        'roundId': roundId,
        'voterId': voterId,
        'votedForId': votedForId,
      },
    );
  }

  Map<String, String> votesFor(String roundId) =>
      Map.unmodifiable(_votesByRound[roundId] ?? const {});

  void _apply(Map payload) {
    final r = payload['roundId'] as String;
    final v = payload['voterId'] as String;
    final tgt = payload['votedForId'] as String;
    (_votesByRound[r] ??= {})[v] = tgt;
    _controller.add(Map.unmodifiable(_votesByRound));
  }

  Future<void> dispose() async {
    await _channel.unsubscribe();
    await _controller.close();
  }
}
```

`currentRoundVotesProvider` switches from watching the DB stream to watching this channel's stream, and `GameService.submitVote` routes through `LiveVoteChannel.castVote` instead of `GameRepository.submitVote`. `GameService.revealResults` switches from `revealResultsRpc` to a new `revealRoundWithVotesRpc(roomId, roundId, votes)` that takes the map from `LiveVoteChannel.votesFor(roundId)` and serializes it.

## What stays the same

End-screen queries (`fetchAllVotes`, the question-by-round join) are unchanged — they read the `votes` table, which still contains one row per vote, just written in a burst at reveal rather than one-by-one during voting. All Riverpod wiring in `state/providers.dart` stays except the one provider that was watching `votes`. No schema change to any table.

## What changes in observable behavior

Live vote UI during a round no longer pulls through the database. That has two consequences the product should explicitly accept.

**Late joiners miss in-progress votes.** A player joining mid-round via the share link sees an empty vote state until someone votes *after* they arrived. Their own vote still counts, and the reveal-time DB write backfills the authoritative tally for everyone including them. For a game where rounds are short and "joined mid-round" already has a confusing UX (you missed the question reveal, the timer, etc.), I think this is acceptable. If it isn't, we add a snapshot request protocol: the joiner broadcasts `{type: 'sync_request', roundId, playerId}`, one peer responds with its current `votesByRound[roundId]` as a `sync_response` event, and the joiner merges it in. Easy to add later, don't ship it v1.

**A disconnected host loses the aggregation.** In the design as written, the caller of `reveal_round_with_votes` is whichever client the host happens to be on, and it passes *its* view of the round. If that view missed broadcasts while the host was briefly offline, the reveal-time write is incomplete. Two mitigations, pick one: (a) have every client call the reveal RPC with its own view, relying on `ON CONFLICT DO NOTHING` to merge — wasteful but bulletproof; (b) designate any connected client as the "leader" via a simple "lowest `player.id` alphabetically" rule, so the aggregator role survives host disconnect. I lean toward (a) for v1 because the N clients each doing one RPC is still one network write per client instead of one per *vote*.

**No audit trail of vote timing.** Today the `votes.created_at` column records the exact moment each vote was cast. Under option B all votes for a round share a `created_at` within milliseconds of reveal time. If we ever wanted "who voted first?" analytics, we'd lose it. Easy to preserve by including a `cast_at` timestamp in the broadcast payload and writing it into a new column; not worth doing preemptively.

## Risks and why I'd still ship it

The concurrency model is strictly simpler on the DB side (one write per round instead of N), so DB load goes down unambiguously. The broadcast side is a new dependency surface, but it's Supabase-native, shares the same auth/connection as the existing `postgres_changes` subscriptions, and disconnection is already a thing we handle (room reconnection logic in `game_service.dart:119-138` survives tab refreshes, so a broadcast drop fits in the same envelope). The one genuinely new failure mode is "broadcast drops a message silently", which would manifest as a missing vote in the reveal-time tally. That's mitigated by the mitigation (a) above (every client writes its view) and, if paranoia is warranted, by a fallback "one-shot `votes` INSERT per vote" that the voter's own client performs as a belt-and-braces write — this keeps per-vote writes but eliminates the N² *fan-out* traffic, which is almost all of the savings anyway.

## Suggested rollout

Ship option A first (already done: `20260417093000_add_round_transition_rpcs.sql` + the `GameService` refactor). Let it bake on dev and in production for a week. Measure the Realtime message count via the Supabase dashboard to establish a baseline. Then ship option B behind a feature flag, probably reusing the existing dev-mode flag (`2afa23f dev mode on dev branch toggled`), so a QA pass can confirm:

1. Live vote counts match the old behavior during a round.
2. Reveal correctly persists all votes.
3. A deliberately dropped client (close-tab-then-rejoin mid-round) recovers to the right state after reveal.
4. Two clients tapping "Reveal" at the same moment don't double-insert votes.

Flip the flag for everyone once those four checks pass. Then drop `votes` from the realtime publication in a follow-up migration — deferring that until after the flag is rolled out means we can toggle back to the DB-subscription code path without an extra migration if something goes wrong.

## Out of scope for this doc

The host-leaves-the-room case, RLS tightening, and auth migration are all separate concerns tracked in `architecture-notes.md` under "To verify next session". None of them block option B, but they interact — in particular, once we have Supabase Auth, the reveal RPC should verify `auth.uid()` matches the host (or at least a player in the room) before accepting the vote batch.
