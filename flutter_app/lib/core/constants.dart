/// Unambiguous chars for room codes (no 0/O/I/1 etc).
const String kRoomCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const int kRoomCodeLength = 5;
const int kMaxRounds = 10;
const int kMinPlayersToStart = 3;

/// Current single question pack. Matches the web app's hardcoded pack id.
const String kDefaultQuestionPackId = '00000000-0000-0000-0000-000000000001';

/// Compile-time opt-in for the dev/bot-mode UI in *release* builds — e.g. on
/// Vercel preview deploys where we want to click through a game alone.
///
/// Set via `--dart-define=ENABLE_DEV_MODE=true` at build time. In a normal
/// `flutter run` this stays `false` but [kDebugMode] is already `true`, so
/// the toggle shows up anyway. In release it's the only way to get the
/// toggle to appear.
const bool kEnableDevMode =
    bool.fromEnvironment('ENABLE_DEV_MODE', defaultValue: false);
