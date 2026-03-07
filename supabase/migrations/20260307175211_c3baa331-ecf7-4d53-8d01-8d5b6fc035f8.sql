
-- Create rooms table
CREATE TABLE public.rooms (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  host_player_id UUID,
  status TEXT NOT NULL DEFAULT 'lobby' CHECK (status IN ('lobby', 'in_round', 'results', 'finished')),
  current_round INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create players table
CREATE TABLE public.players (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  is_host BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Add FK for host_player_id after players table exists
ALTER TABLE public.rooms ADD CONSTRAINT rooms_host_player_id_fkey FOREIGN KEY (host_player_id) REFERENCES public.players(id);

-- Create question_packs table
CREATE TABLE public.question_packs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create questions table
CREATE TABLE public.questions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  pack_id UUID NOT NULL REFERENCES public.question_packs(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create rounds table
CREATE TABLE public.rounds (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES public.questions(id),
  round_number INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'voting' CHECK (status IN ('voting', 'revealed', 'closed')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create votes table
CREATE TABLE public.votes (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  round_id UUID NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
  voter_id UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  voted_for_id UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(round_id, voter_id)
);

-- Enable RLS on all tables
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.question_packs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.votes ENABLE ROW LEVEL SECURITY;

-- Since no auth, allow all operations for now (MVP)
CREATE POLICY "Allow all on rooms" ON public.rooms FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on players" ON public.players FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on question_packs" ON public.question_packs FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on questions" ON public.questions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on rounds" ON public.rounds FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on votes" ON public.votes FOR ALL USING (true) WITH CHECK (true);

-- Enable realtime for key tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE public.players;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rounds;
ALTER PUBLICATION supabase_realtime ADD TABLE public.votes;

-- Seed question pack
INSERT INTO public.question_packs (id, name) VALUES ('00000000-0000-0000-0000-000000000001', 'Classico');

-- Seed questions
INSERT INTO public.questions (pack_id, text) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più simpatico?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più generoso?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più permaloso?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più introverso?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più ritardatario?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più romantico?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più disordinato?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più competitivo?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più goloso?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più avventuroso?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più pigro?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più chiacchierone?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più creativo?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più testardo?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più fortunato?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi farebbe il miglior presidente?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi sopravviverebbe più a lungo su un''isola deserta?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più probabile che diventi famoso?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più drammatico?'),
  ('00000000-0000-0000-0000-000000000001', 'Chi è il più affidabile?');
