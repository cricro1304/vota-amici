# Feasibility Report: Room Joining & Device Uniqueness

**Project:** vota-amici (small online games with friends)
**Date:** 2026-04-14

## Summary

| Feature | Difficulty | Effort | Reliability |
|---|---|---|---|
| Join room by link | Easy | ~½ day | Very high |
| Join via AirDrop | Easy (it's just a link) | ~0 extra | High on Apple-only groups |
| Device / user uniqueness | Hard to make bullet-proof | 1–5 days depending on rigor | Medium at best without accounts |

---

## 1. Room joining by link

**Verdict: trivial.** This is the standard pattern for every web-based party game (Jackbox, skribbl.io, gartic.io, kahoot, etc.).

**How it works**
- Each room has a short ID (e.g. 4–6 chars, base32, profanity-filtered).
- URL shape: `https://vota-amici.app/r/AB12` or `?room=AB12`.
- On load, the client reads the ID, opens a websocket / Supabase Realtime / Firebase channel scoped to that room, and joins.

**Work required**
- Random ID generator with collision check (10 lines).
- A `rooms` table or in-memory map keyed by ID with `created_at`, `state`, `players[]`.
- A "Copy invite link" button (`navigator.clipboard.writeText`).
- Optional: short-link or QR code (`qrcode` npm package, ~5 lines).

**Edge cases worth handling**
- Expired / closed rooms → friendly "this room is over" page.
- Full rooms → cap player count.
- Profanity in auto-generated IDs → use a curated alphabet or a wordlist (`adjective-noun-42`).

## 2. AirDrop joining

**Verdict: nothing extra to build.** AirDrop is just an OS-level transport for a URL or text. If your invite is a normal HTTPS link, the host can already AirDrop it from Safari's share sheet, Messages, Notes, etc. The receiving device opens it in the browser → joins the room.

**Caveats**
- AirDrop is Apple-only (iOS/macOS). Android friends need a different transport (QR code, copy-paste, WhatsApp link, etc.) — a QR code on the lobby screen covers everyone in the room with one mechanism.
- No SDK, no entitlements, no special metadata required for a web app. (Native iOS apps can register custom share targets, but you don't need that.)
- If you ever wrap the game as a PWA / native app, you can register a URL scheme or Universal Link so AirDropped URLs deep-link into the app instead of the browser. That's a small extra step (Apple App Site Association file) but not required.

**Recommendation:** ship a "Copy link" button + a QR code in the lobby. That covers AirDrop, iMessage, WhatsApp, in-person, and Android in one stroke.

---

## 3. Device / user uniqueness

This is the hard one. **There is no perfect, abuse-proof way to identify a unique person from a browser without forcing them to log in.** Every approach is a tradeoff between friction, privacy, and how determined the "cheater" is.

### Threat model — be specific about what you're defending against

1. **Honest mistake** — user opens a second tab to check the rules and accidentally joins twice.
2. **Casual ballot-stuffing** — user opens an incognito window to vote twice in a poll game.
3. **Determined abuse** — user uses a different browser, a VPN, or another device to impersonate multiple players.

Difficulty scales sharply with each tier.

### Tier 1 — Honest mistake (Easy, ~½ day)

The cheap, friendly fix:

- On first visit, generate a random `playerId` (UUID) and store it in `localStorage` keyed per origin.
- When joining a room, send `{ roomId, playerId }`. If that `playerId` is already in the room, the server treats the new connection as a **reconnect** (close the old socket, attach the new one) instead of creating a second player.
- Bonus: also use a **BroadcastChannel** in the browser. When tab B opens the same room, tab A receives a message and either kicks tab B back to the lobby ("you're already in this room in another tab") or hands the session over.

This catches ~95% of real-world double-joins with almost no code.

### Tier 2 — Casual ballot-stuffing (Medium, 1–2 days)

`localStorage` doesn't survive incognito mode or a different browser. To raise the bar:

- **Server-side fingerprinting**: combine IP + User-Agent + a hashed canvas/audio fingerprint. Libraries like FingerprintJS (open-source version) give you a stable-ish ID without an account.
  - Pros: catches the lazy "open a private window" cheat.
  - Cons: false positives when two roommates share a Wi-Fi (same IP, similar UA), and the open-source FingerprintJS is much weaker than the paid version. Also raises GDPR/consent questions in EU.
- **Per-room invite tokens**: instead of one shared link, the host generates N single-use tokens (one per friend) and sends them individually. A token can be redeemed once. This converts the problem from "is this the same person?" to "did this slot get claimed?" — much easier to reason about, but adds friction to the host.
- **WebAuthn / passkey** as a soft sign-in: very modern, no password, but real setup cost and UX explanation.

### Tier 3 — Determined abuse (Hard, only solvable with accounts)

If a player wants two votes badly enough, they will use their phone's cellular data + their laptop's Wi-Fi and a different browser. The only robust defenses are:

- **Real authentication** (Google / Apple / email magic link) — Supabase Auth or Auth0 makes this ~1 day of work but adds a sign-in wall that kills the "tap a link, play in 5 seconds" feel that party games depend on.
- **Phone-number verification** (Twilio Verify) — strongest, but costs money per SMS and is heavy for a casual game.
- **Host moderation** — the simplest "social" defense: show the host a list of joined players with their IPs/devices and let them kick duplicates. Cheap to build and matches how Jackbox / Kahoot lobbies work in practice.

### Comparison: "Honest-mistake auto-dedupe" vs. "Host manually removes"

These are the two cheapest options. Worth weighing them directly.

| Dimension | Auto-dedupe (localStorage UUID + reconnect + BroadcastChannel) | Host manual kick |
|---|---|---|
| **Build effort** | ~½–1 day. Need a stable client ID, server-side "is this ID already in the room?" check, socket handover logic, and a small BroadcastChannel listener. | ~1–2 hours. Just a list of players in the lobby with an "X" button next to each, wired to a `kick(playerId)` server action. |
| **Server complexity** | Has to handle reconnect semantics carefully: which socket "wins", what happens to in-flight game state, what if the old tab is mid-vote. Edge cases multiply if a game is already in progress. | Almost none. Removing a player is a state mutation you already need for "player left" / "player disconnected" anyway. |
| **UX when it works** | Invisible. The user opens a second tab, the first one quietly takes over (or the second is told "you're already here"). Feels magical. | Visible. The host sees "Alex" and "Alex (2)" and clicks remove. Mildly awkward but understandable. |
| **UX when it fails** | Fails silently and confusingly. If localStorage is cleared (private window, "clear site data", different browser), the same human shows up as a new UUID and the dedupe doesn't fire. User thinks it's working when it isn't. | Fails loudly and obviously. Host can always see the duplicates and act. No false sense of security. |
| **Catches incognito / second browser?** | No. Different storage = different UUID = looks like a new player. | Yes — host sees the extra entry regardless of how it got there. |
| **Catches second device (phone + laptop)?** | No. | Yes, if the host recognises the duplicate name/avatar. |
| **Requires host attention?** | No — runs automatically. | Yes — host has to be watching the lobby. Fine before a round starts; annoying mid-game. |
| **Risk of false positive** | Low but real: two friends on the same shared family iPad with the same browser profile would collide and kick each other. | Zero — host has full context and judgment. |
| **Scales to "determined cheater"?** | No. | Partially — host can see and remove obvious duplicates, but can't tell a stranger's two devices apart. |

**They are not mutually exclusive — and shouldn't be.** Auto-dedupe handles the silent 95% case (the same person genuinely opening a second tab); host-kick is the safety net for everything auto-dedupe misses (incognito, different browser, different device, weird edge case). The combined cost is still under a day.

If you had to pick **only one**, pick **host kick**. Reasoning:
- Strictly cheaper to build.
- Fails visibly, not silently — the host always has the final word, so you never accidentally trust a broken signal.
- Covers more of the threat surface (incognito, second browser, second device).
- Matches the social model of friends playing together: the person who set up the game is implicitly the referee.

Auto-dedupe's main win is the "double-tabbed by accident" recovery flow (especially mid-game, when the host shouldn't have to babysit the lobby). That's a real UX win, but it's a **polish** layer on top of host-kick, not a replacement for it.

### Recommended stack for vota-amici

Given the product is "small games with friends" — low-stakes, trust-based — the right answer is almost certainly:

1. **Host can see and kick** anyone in the lobby (cheapest, most reliable, covers the most cases).
2. **localStorage UUID + reconnect-on-collision** as a polish layer (catches the silent honest-mistake case, especially mid-game).
3. **BroadcastChannel guard** for same-browser duplicate tabs (prevents the most common accidental double-join with ~10 lines of code).
4. Skip fingerprinting and accounts unless a specific game (e.g. a serious vote) actually needs them.

Order matters: ship host-kick first (a few hours), then layer auto-dedupe on top if needed. Together they're ~1 day total and match the UX of every successful party-game competitor.

### What NOT to rely on

- **IP address alone** — NAT, mobile carriers, and shared Wi-Fi make this both lossy (false positives) and bypassable (cellular data).
- **Cookies without `SameSite` / partitioned storage care** — Safari and Brave aggressively clear them.
- **Browser fingerprinting as a hard block** — false-positive rate is too high to be the *only* signal; use it as a tiebreaker, not a gate.

---

## Bottom line

Room-link joining and AirDrop are essentially free — ship them. Device uniqueness should be solved at the lowest tier that fits the threat model: a localStorage ID plus a BroadcastChannel guard plus host-kick covers the realistic cases for a friends-only party game. Anything stronger than that means accounts, and accounts mean losing the "click a link and play" magic that this category relies on.
