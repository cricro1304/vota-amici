-- Couples pack: first pack with a game flow that diverges from Classico.
--
-- Three changes in one migration:
--   1. Add `pack_id` to `public.rooms` so the server knows which pack a
--      room belongs to. Previously the pack was a purely client-side
--      catalog (flutter_app/lib/models/pack.dart) — the server only saw
--      `modes`. Couples needs different reveal + end-screen logic, which
--      the client will branch on `room.pack_id`.
--   2. Seed the `Coppie` pack row with a stable UUID so the Flutter
--      catalog can reference it by constant (kCouplesPackId).
--   3. Seed ~18 couples questions across all three modes so the Coppie
--      pack actually plays. 2-person framing: voters pick between
--      themselves and their partner for every prompt.
--
-- Back-compat: `pack_id` is nullable and existing rooms are NOT
-- backfilled. The client treats NULL pack_id as "legacy classic" to
-- avoid a storm of writes against in-flight games. New rooms always
-- stamp a pack_id.

-- ---------------------------------------------------------------------------
-- 1. Seed the Coppie pack row.
-- ---------------------------------------------------------------------------
-- Fixed UUID so the Flutter constant `kCouplesPackId` can reference it
-- without a lookup. Matches the pattern used for Classico
-- (`00000000-0000-0000-0000-000000000001`).

INSERT INTO public.question_packs (id, name)
VALUES ('00000000-0000-0000-0000-000000000002', 'Coppie')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Add `pack_id` to rooms.
-- ---------------------------------------------------------------------------
-- Nullable on purpose: pre-migration rooms stay NULL (client interprets
-- NULL as classic), post-migration rooms always set it explicitly. The
-- FK cascades nothing by design — deleting a pack shouldn't orphan a
-- live room, and we never delete packs in practice.

ALTER TABLE public.rooms
  ADD COLUMN IF NOT EXISTS pack_id UUID
  REFERENCES public.question_packs(id);

CREATE INDEX IF NOT EXISTS idx_rooms_pack_id
  ON public.rooms(pack_id);

-- ---------------------------------------------------------------------------
-- 3. Seed Coppie questions.
-- ---------------------------------------------------------------------------
-- Mode split roughly 6 light / 7 neutro / 5 spicy, loosely matching the
-- Classico balance. Phrasing is deliberately 2-player framed ("chi
-- dei due...", "chi russa di più") so the voter always has a clear
-- binary choice between themselves and their partner — this is what
-- enables the agree / cross-disagree / self-disagree reveal taxonomy.

INSERT INTO public.questions (pack_id, text, mode) VALUES
  -- Light
  ('00000000-0000-0000-0000-000000000002', 'Chi è il più romantico?',                         'light'),
  ('00000000-0000-0000-0000-000000000002', 'Chi fa più foto in vacanza?',                     'light'),
  ('00000000-0000-0000-0000-000000000002', 'Chi ha detto "ti amo" per primo?',                    'light'),
  ('00000000-0000-0000-0000-000000000002', 'Chi è il più coccolone?',                         'light'),
  ('00000000-0000-0000-0000-000000000002', 'Chi ricorda meglio gli anniversari?',             'light'),
  ('00000000-0000-0000-0000-000000000002', 'Chi prepara la colazione più spesso?',            'light'),
  -- Neutro
  ('00000000-0000-0000-0000-000000000002', 'Chi è il più geloso?',                            'neutro'),
  ('00000000-0000-0000-0000-000000000002', 'Chi russa di più?',                               'neutro'),
  ('00000000-0000-0000-0000-000000000002', 'Chi sta più al telefono?',                        'neutro'),
  ('00000000-0000-0000-0000-000000000002', 'Chi cucina meglio?',                              'neutro'),
  ('00000000-0000-0000-0000-000000000002', 'Chi spende di più?',                              'neutro'),
  ('00000000-0000-0000-0000-000000000002', 'Chi è il più disordinato?',                       'neutro'),
  ('00000000-0000-0000-0000-000000000002', 'Chi è il più testardo?',                          'neutro'),
  -- Spicy
  ('00000000-0000-0000-0000-000000000002', 'Chi scrive messaggi imbarazzanti dopo qualche drink?', 'spicy'),
  ('00000000-0000-0000-0000-000000000002', 'Chi è più curioso del telefono dell''altro?',     'spicy'),
  ('00000000-0000-0000-0000-000000000002', 'Chi guarda più spesso un ex sui social?',         'spicy'),
  ('00000000-0000-0000-0000-000000000002', 'Chi è il più sporcaccione?',                      'spicy'),
    ('00000000-0000-0000-0000-000000000002', 'Chi è il più responsabile?',                    'neutro'),
  ('00000000-0000-0000-0000-000000000002', 'Chi mente più spesso sulle piccole cose?',        'spicy'),
  ('00000000-0000-0000-0000-000000000002', 'Chi flirta di più (anche solo per gioco)?',       'spicy');
