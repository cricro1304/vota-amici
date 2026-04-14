enum RoomStatus { lobby, inRound, results, finished }

RoomStatus _parseStatus(String s) {
  switch (s) {
    case 'in_round':
      return RoomStatus.inRound;
    case 'results':
      return RoomStatus.results;
    case 'finished':
      return RoomStatus.finished;
    case 'lobby':
    default:
      return RoomStatus.lobby;
  }
}

String statusToString(RoomStatus s) {
  switch (s) {
    case RoomStatus.inRound:
      return 'in_round';
    case RoomStatus.results:
      return 'results';
    case RoomStatus.finished:
      return 'finished';
    case RoomStatus.lobby:
      return 'lobby';
  }
}

class Room {
  final String id;
  final String code;
  final String? hostPlayerId;
  final RoomStatus status;
  final int currentRound;
  final int? timerSeconds;
  final DateTime createdAt;

  const Room({
    required this.id,
    required this.code,
    required this.hostPlayerId,
    required this.status,
    required this.currentRound,
    required this.timerSeconds,
    required this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as String,
        code: json['code'] as String,
        hostPlayerId: json['host_player_id'] as String?,
        status: _parseStatus(json['status'] as String),
        currentRound: json['current_round'] as int? ?? 0,
        timerSeconds: json['timer_seconds'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
