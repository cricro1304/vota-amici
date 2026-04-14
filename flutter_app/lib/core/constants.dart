/// Unambiguous chars for room codes (no 0/O/I/1 etc).
const String kRoomCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const int kRoomCodeLength = 5;
const int kMaxRounds = 10;
const int kMinPlayersToStart = 3;

/// Current single question pack. Matches the web app's hardcoded pack id.
const String kDefaultQuestionPackId = '00000000-0000-0000-0000-000000000001';
