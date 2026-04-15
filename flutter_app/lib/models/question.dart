/// Tone of a question. Mirrors the `mode` CHECK constraint on
/// `public.questions` (light | neutro | spicy). Host picks which modes to
/// include when creating the room (see `Room.modes`).
enum QuestionMode { light, neutro, spicy }

QuestionMode parseQuestionMode(String? raw) {
  switch (raw) {
    case 'light':
      return QuestionMode.light;
    case 'spicy':
      return QuestionMode.spicy;
    case 'neutro':
    default:
      return QuestionMode.neutro;
  }
}

String questionModeToString(QuestionMode m) {
  switch (m) {
    case QuestionMode.light:
      return 'light';
    case QuestionMode.spicy:
      return 'spicy';
    case QuestionMode.neutro:
      return 'neutro';
  }
}

class Question {
  final String id;
  final String packId;
  final String text;
  final QuestionMode mode;

  const Question({
    required this.id,
    required this.packId,
    required this.text,
    required this.mode,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        packId: json['pack_id'] as String,
        text: json['text'] as String,
        mode: parseQuestionMode(json['mode'] as String?),
      );
}
