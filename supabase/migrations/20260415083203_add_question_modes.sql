-- Game modes: classify questions as Light / Neutro / Spicy and let the host
-- pick which modes to include when creating a room. This is orthogonal to
-- the existing `question_packs` (themed sets like Coppie, Fratelli) — a
-- single pack can contain questions of any mode.

-- 1. Add a `mode` column to questions. Default 'neutro' so existing rows
--    have a non-null value before we reclassify them below.
ALTER TABLE public.questions
  ADD COLUMN mode TEXT NOT NULL DEFAULT 'neutro'
    CHECK (mode IN ('light', 'neutro', 'spicy'));

CREATE INDEX IF NOT EXISTS idx_questions_pack_mode
  ON public.questions(pack_id, mode);

-- 2. Add a `modes` column to rooms. Default to all three so existing rows
--    keep working unchanged. The host's create-room picker writes this.
ALTER TABLE public.rooms
  ADD COLUMN modes TEXT[] NOT NULL DEFAULT ARRAY['light', 'neutro', 'spicy'];

-- 3. Reclassify the 20 seeded questions in the Classico pack.
--    - Light: warm / wholesome / aspirational. Safe with anyone.
--    - Neutro: neutral observations about habits / personality. Default vibe.
--    - Spicy: more provocative. (Empty for now — author will add.)
UPDATE public.questions SET mode = 'light' WHERE text IN (
  'Chi è il più simpatico?',
  'Chi è il più generoso?',
  'Chi è il più romantico?',
  'Chi è il più creativo?',
  'Chi è il più fortunato?',
  'Chi è il più affidabile?',
  'Chi è il più avventuroso?',
  'Chi è il più goloso?',
  'Chi farebbe il miglior presidente?',
  'Chi sopravviverebbe più a lungo su un''isola deserta?',
  'Chi è il più probabile che diventi famoso?'
);

UPDATE public.questions SET mode = 'neutro' WHERE text IN (
  'Chi è il più introverso?',
  'Chi è il più ritardatario?',
  'Chi è il più disordinato?',
  'Chi è il più competitivo?',
  'Chi è il più pigro?',
  'Chi è il più chiacchierone?',
  'Chi è il più testardo?',
  'Chi è il più drammatico?',
  'Chi è il più permaloso?'
);

-- Spicy seed left intentionally empty. Author will add via a follow-up
-- migration once the spicy prompts are reviewed.
