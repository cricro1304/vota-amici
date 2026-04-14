class Player {
  final String id;
  final String roomId;
  final String name;
  final bool isHost;
  final DateTime createdAt;

  const Player({
    required this.id,
    required this.roomId,
    required this.name,
    required this.isHost,
    required this.createdAt,
  });

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        name: json['name'] as String,
        isHost: json['is_host'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
