class Player {
  final String id;
  final String roomId;
  final String name;
  final bool isHost;
  final DateTime createdAt;

  /// Persistent browser fingerprint (see SessionService.browserId). Nullable
  /// so pre-migration rows and bot players (DevBotService) still load —
  /// we only use it for the secondary rejoin-recovery match.
  final String? browserId;

  const Player({
    required this.id,
    required this.roomId,
    required this.name,
    required this.isHost,
    required this.createdAt,
    this.browserId,
  });

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        name: json['name'] as String,
        isHost: json['is_host'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        browserId: json['browser_id'] as String?,
      );
}
