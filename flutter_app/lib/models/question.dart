class Question {
  final String id;
  final String packId;
  final String text;

  const Question({
    required this.id,
    required this.packId,
    required this.text,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        packId: json['pack_id'] as String,
        text: json['text'] as String,
      );
}
