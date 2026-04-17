/// Unambiguous chars for room codes (no 0/O/I/1 etc).
const String kRoomCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const int kRoomCodeLength = 5;
const int kMaxRounds = 10;

/// Minimum players to start the default (classic) pack. Couples overrides
/// this to 2 — see `Pack.minPlayers` on the couples catalog entry.
const int kMinPlayersToStart = 3;

/// Fixed UUIDs for the seeded question packs. Must match the rows inserted
/// by the migrations under supabase/migrations/. The Flutter `Pack` catalog
/// references these so it can pass a concrete `pack_id` into `createRoom`
/// without a lookup round-trip.
const String kClassicPackId = '00000000-0000-0000-0000-000000000001';
const String kCouplesPackId = '00000000-0000-0000-0000-000000000002';

/// Kept as an alias for pre-existing call sites. Points at Classico, which
/// is still the default fallback when a room has no `pack_id` (legacy rows
/// created before the couples-pack migration).
const String kDefaultQuestionPackId = kClassicPackId;

/// Compile-time opt-in for the dev/bot-mode UI in *release* builds — e.g. on
/// Vercel preview deploys where we want to click through a game alone.
///
/// Set via `--dart-define=ENABLE_DEV_MODE=true` at build time. In a normal
/// `flutter run` this stays `false` but [kDebugMode] is already `true`, so
/// the toggle shows up anyway. In release it's the only way to get the
/// toggle to appear.
const bool kEnableDevMode =
    bool.fromEnvironment('ENABLE_DEV_MODE', defaultValue: false);
