#!/usr/bin/env bash
# DB-level concurrency stress for the partial UNIQUE index on
# players(room_id, browser_id). Creates a throwaway room and fires N
# parallel inserts with the SAME browser_id; the index should reject
# all but one with 23505. Anything other than "1 success, N-1 rejects"
# means the index regressed.
#
# Usage:
#   SUPABASE_URL=https://<ref>.supabase.co \
#   SUPABASE_ANON_KEY=eyJ... \
#   ./scripts/stress_unique_index.sh [N]            # default N=20
#
# Cleans up the room on exit (CASCADE removes the players too).

set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is required}"
N="${1:-20}"

auth=(-H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY")
json=(-H "Content-Type: application/json" -H "Prefer: return=representation")
api="$SUPABASE_URL/rest/v1"

# Random 5-char room code so we don't collide with real rooms.
code=$(LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c 5)
browser="stress-$(date +%s)-$$"

echo "▶ Creating throwaway room ($code)…"
room_id=$(curl -fsS "${auth[@]}" "${json[@]}" \
  -X POST "$api/rooms" \
  -d "{\"code\":\"$code\",\"status\":\"lobby\",\"modes\":[\"neutro\"]}" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["id"])')
echo "  room_id=$room_id  browser_id=$browser"

cleanup() {
  echo "▶ Cleaning up room…"
  curl -fsS "${auth[@]}" -X DELETE "$api/rooms?id=eq.$room_id" >/dev/null || true
}
trap cleanup EXIT

echo "▶ Firing $N parallel inserts with the same browser_id…"
tmpdir=$(mktemp -d)
for i in $(seq 1 "$N"); do
  (
    code=$(curl -s -o "$tmpdir/$i.body" -w "%{http_code}" "${auth[@]}" "${json[@]}" \
      -X POST "$api/players" \
      -d "{\"room_id\":\"$room_id\",\"name\":\"Stress $i\",\"browser_id\":\"$browser\"}")
    echo "$code" > "$tmpdir/$i.code"
  ) &
done
wait

ok=0
dup=0
other=0
for i in $(seq 1 "$N"); do
  code=$(cat "$tmpdir/$i.code")
  case "$code" in
    201) ok=$((ok+1)) ;;
    409) dup=$((dup+1)) ;;
    *)
      other=$((other+1))
      echo "  ⚠ unexpected $code on attempt $i:"
      sed 's/^/      /' "$tmpdir/$i.body"
      ;;
  esac
done
rm -rf "$tmpdir"

echo
echo "  201 created  : $ok  (expected: 1)"
echo "  409 conflict : $dup (expected: $((N-1)))"
echo "  other        : $other"

# Independent cross-check: how many rows actually landed?
rows=$(curl -fsS "${auth[@]}" \
  "$api/players?room_id=eq.$room_id&browser_id=eq.$browser&select=id" \
  | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')
echo "  rows in DB   : $rows  (expected: 1)"

if [ "$ok" -eq 1 ] && [ "$dup" -eq $((N-1)) ] && [ "$rows" -eq 1 ] && [ "$other" -eq 0 ]; then
  echo "✅ PASS — UNIQUE index is enforcing under concurrency."
  exit 0
else
  echo "❌ FAIL — see counts above."
  exit 1
fi
