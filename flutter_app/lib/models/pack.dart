import '../core/constants.dart';
import 'question.dart';

/// Availability state of a pack. Mirrors the tags shown on `packs.html`:
///   - `available` → "✅ Gratis"
///   - `comingSoon` → "🔜 In arrivo"
///   - `ageRestricted` → "🔞" (18+, also gated behind a future release)
enum PackStatus { available, comingSoon, ageRestricted }

/// Shape of the game flow a pack uses. Orthogonal to [PackStatus] and
/// [QuestionMode] — `kind` picks the *rules* (how many players, what the
/// reveal looks like, what the end screen shows), while modes pick the
/// *tone* and status picks the availability.
///
///   - `classic` → N players (≥ [kMinPlayersToStart]); per-round winner
///     by vote count; end screen shows vote totals.
///   - `couples` → exactly 2 players; per-round reveal is one of three
///     outcomes (agree / each-picked-the-other / each-picked-themselves);
///     end screen shows a compatibility % + per-mode breakdown, hides
///     individual tallies.
enum PackKind { classic, couples }

/// A question pack that the host picks before creating a room. The set of
/// packs is a purely client-side catalog today — the backend stores the
/// resulting `modes` on the room row, so a pack effectively maps 1:N onto
/// the existing `light | neutro | spicy` modes until a real `pack_id`
/// column lands on `public.rooms`.
///
/// Keep this list in sync with `packs.html` on the marketing site so the
/// in-app picker reads like a continuation of the landing page.
class Pack {
  const Pack({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.chips,
    required this.questionCount,
    required this.status,
    required this.modes,
    this.kind = PackKind.classic,
    this.dbId,
    this.minPlayers = kMinPlayersToStart,
    this.maxPlayers,
  });

  /// Client-side slug (`originale`, `coppie`, `spicy`, …). Used for
  /// navigation, analytics, and matching the landing-page cards — NOT
  /// persisted to the database.
  final String id;
  final String emoji;
  final String title;
  final String description;

  /// A handful of example prompts — shown as small chips on the pack card,
  /// same as the landing page. Keep short (2–4 items).
  final List<String> chips;

  /// Approximate question count displayed on the card ("+100 domande").
  final int questionCount;

  final PackStatus status;

  /// Which `QuestionMode`s this pack enables on the created room. Used
  /// directly as the `modes` payload when calling `createRoom`.
  final List<QuestionMode> modes;

  /// Game-flow archetype. Drives lobby rules, the reveal widget, and the
  /// end screen. See [PackKind] for the taxonomy.
  final PackKind kind;

  /// UUID of the matching row in `public.question_packs`. Null for packs
  /// that don't have a DB row yet (the "comingSoon" marketing cards) —
  /// those are not playable so no one ever reads this null.
  final String? dbId;

  /// Lower bound on the lobby. Classic packs inherit [kMinPlayersToStart]
  /// (3). Couples packs override to 2.
  final int minPlayers;

  /// Optional upper bound on the lobby. Null = no cap (classic). Couples
  /// sets this to 2 so a third joiner is blocked at the service layer.
  final int? maxPlayers;

  bool get isPlayable => status == PackStatus.available;

  /// Canonical catalog. Only `originale` is playable today — the rest are
  /// marketing teasers mirroring the landing-page "In arrivo" cards.
  static const List<Pack> catalog = [
    Pack(
      id: 'originale',
      emoji: '🎭',
      title: 'Originale',
      description:
          'Le domande essenziali per qualsiasi serata tra amici. Il punto di partenza perfetto per scoprire cosa pensano davvero di te.',
      chips: [
        '😴 il più pigro',
        '🎭 il più drammatico',
        '💪 il più testardo',
        '😄 il più simpatico',
      ],
      questionCount: 100,
      status: PackStatus.available,
      modes: [QuestionMode.light, QuestionMode.neutro],
      kind: PackKind.classic,
      dbId: kClassicPackId,
    ),
    Pack(
      id: 'coppie',
      emoji: '💑',
      title: 'Coppie',
      description:
          'Quanto vi conoscete davvero? Le domande che metteranno alla prova anche le coppie più solide.',
      chips: [
        '💤 chi russa di più',
        '📱 chi sta più al telefono',
        '🍽️ chi cucina meglio',
        '🛒 chi spende di più',
      ],
      questionCount: 18,
      status: PackStatus.available,
      modes: [QuestionMode.light, QuestionMode.neutro],
      kind: PackKind.couples,
      dbId: kCouplesPackId,
      // The couples flow is literally about *a* couple — lobby enforces
      // exactly 2 players; the reveal taxonomy (agree / cross / self)
      // only makes sense at N=2.
      minPlayers: 2,
      maxPlayers: 2,
    ),
    Pack(
      id: 'fratelli',
      emoji: '👫',
      title: 'Fratelli',
      description:
          'Chi era il preferito della mamma? Chi rompeva sempre tutto? Regolamenti di conti tra fratelli e sorelle, finalmente nero su bianco.',
      chips: [
        '👑 il preferito di mamma',
        '💥 chi rompeva tutto',
        '🤫 chi faceva la spia',
        '🎒 chi copiava i compiti',
      ],
      questionCount: 50,
      status: PackStatus.comingSoon,
      modes: [QuestionMode.light, QuestionMode.neutro],
    ),
    Pack(
      id: 'famiglia',
      emoji: '👨‍👩‍👧‍👦',
      title: 'Famiglia',
      description:
          'Da nonni a nipoti, tutti votano. Scopri chi è il vero capofamiglia e chi è la pecora nera. Perfetto per pranzi della domenica.',
      chips: [
        '👴 chi racconta le stesse storie',
        '🍝 chi cucina meglio',
        '🎁 chi fa i regali migliori',
        '🙈 la pecora nera',
      ],
      questionCount: 50,
      status: PackStatus.comingSoon,
      modes: [QuestionMode.light, QuestionMode.neutro],
    ),
    Pack(
      id: 'colleghi',
      emoji: '💼',
      title: 'Colleghi',
      description:
          'Chi sparisce sempre in pausa pranzo? Chi risponde alle mail a mezzanotte? L\'ufficio si confessa. Ideale per team building.',
      chips: [
        '☕ chi fa più pause caffè',
        '📧 chi risponde a mezzanotte',
        '🎯 chi rispetta sempre le scadenze',
        '😴 chi dorme in riunione',
      ],
      questionCount: 50,
      status: PackStatus.comingSoon,
      modes: [QuestionMode.light, QuestionMode.neutro],
    ),
    Pack(
      id: 'coinquilini',
      emoji: '🏠',
      title: 'Coinquilini',
      description:
          'Chi lascia i piatti nel lavandino? Chi ruba il cibo degli altri? La convivenza non avrà più segreti.',
      chips: [
        '🍳 chi non cucina mai',
        '🧹 chi non pulisce',
        '🔊 chi fa più rumore',
        '🚿 chi sta ore in bagno',
      ],
      questionCount: 50,
      status: PackStatus.comingSoon,
      modes: [QuestionMode.light, QuestionMode.neutro],
    ),
    Pack(
      id: 'viaggi',
      emoji: '✈️',
      title: 'Viaggi',
      description:
          'Chi perderebbe il passaporto? Chi si lamenterebbe di tutto? Perfetto per il gruppo viaggi, da giocare in aeroporto o in spiaggia.',
      chips: [
        '🗺️ chi si perde sempre',
        '💸 chi spende di più',
        '😴 chi dorme in aereo',
        '📸 chi fa più foto',
      ],
      questionCount: 50,
      status: PackStatus.comingSoon,
      modes: [QuestionMode.light, QuestionMode.neutro],
    ),
    Pack(
      id: 'conoscersi',
      emoji: '🤝',
      title: 'Per conoscersi meglio',
      description:
          'Perfetto per rompere il ghiaccio. Le domande giuste per scoprire chi hai davvero davanti, dalle passioni nascoste ai sogni nel cassetto.',
      chips: [
        '🌍 chi viaggerebbe di più',
        '🎤 chi canterebbe al karaoke',
        '🤫 chi ha più segreti',
        '🌙 chi è più nottambulo',
      ],
      questionCount: 50,
      status: PackStatus.comingSoon,
      modes: [QuestionMode.light, QuestionMode.neutro],
    ),
    Pack(
      id: 'spicy',
      emoji: '🌶️',
      title: 'Spicy',
      description:
          'Le domande che nessuno osa fare a voce alta. Flirt, segreti e confessioni imbarazzanti. Solo per i più coraggiosi. 18+',
      chips: [
        '💋 chi flirta di più',
        '🔥 chi è il più passionale',
        '😏 chi ha più scheletri',
        '🍷 chi regge meno l\'alcol',
      ],
      questionCount: 50,
      status: PackStatus.ageRestricted,
      modes: [QuestionMode.spicy],
    ),
  ];

  static Pack byId(String id) =>
      catalog.firstWhere((p) => p.id == id, orElse: () => catalog.first);

  /// Resolve a pack from its database UUID. Used by screens that only see
  /// `room.packId` (a nullable FK) and need to branch on the pack's
  /// [kind]. A null or unknown id falls back to Originale/classic — the
  /// right behaviour for pre-migration rooms that have `pack_id IS NULL`.
  static Pack byDbId(String? dbId) {
    if (dbId == null) return catalog.first;
    for (final p in catalog) {
      if (p.dbId == dbId) return p;
    }
    return catalog.first;
  }
}
