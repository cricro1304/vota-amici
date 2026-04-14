class Vote {
  final String id;
  final String roundId;
  final String voterId;
  final String votedForId;
  final DateTime createdAt;

  const Vote({
    required this.id,
    required this.roundId,
    required this.voterId,
    required this.votedForId,
    required this.createdAt,
  });

  factory Vote.fromJson(Map<String, dynamic> json) => Vote(
        id: json['id'] as String,
        roundId: json['round_id'] as String,
        voterId: json['voter_id'] as String,
        votedForId: json['voted_for_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
