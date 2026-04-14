enum RoundStatus { voting, revealed, closed }

RoundStatus _parse(String s) {
  switch (s) {
    case 'revealed':
      return RoundStatus.revealed;
    case 'closed':
      return RoundStatus.closed;
    case 'voting':
    default:
      return RoundStatus.voting;
  }
}

String roundStatusToString(RoundStatus s) {
  switch (s) {
    case RoundStatus.revealed:
      return 'revealed';
    case RoundStatus.closed:
      return 'closed';
    case RoundStatus.voting:
      return 'voting';
  }
}

class Round {
  final String id;
  final String roomId;
  final String questionId;
  final int roundNumber;
  final RoundStatus status;
  final DateTime createdAt;

  const Round({
    required this.id,
    required this.roomId,
    required this.questionId,
    required this.roundNumber,
    required this.status,
    required this.createdAt,
  });

  factory Round.fromJson(Map<String, dynamic> json) => Round(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        questionId: json['question_id'] as String,
        roundNumber: json['round_number'] as int,
        status: _parse(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
