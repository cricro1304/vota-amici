import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import type { Tables } from '@/integrations/supabase/types';

interface RoundWithQuestion {
  id: string;
  round_number: number;
  question_id: string;
  questionText?: string;
}

interface EndScreenProps {
  players: Tables<'players'>[];
  allVotes: Tables<'votes'>[];
  allRounds: RoundWithQuestion[];
}

export function EndScreen({ players, allVotes, allRounds }: EndScreenProps) {
  const navigate = useNavigate();

  const playerMap: Record<string, string> = {};
  players.forEach(p => { playerMap[p.id] = p.name; });

  // Per-round results
  const roundResults = allRounds
    .sort((a, b) => a.round_number - b.round_number)
    .map(round => {
      const roundVotes = allVotes.filter(v => v.round_id === round.id);
      const counts: Record<string, number> = {};
      roundVotes.forEach(v => {
        counts[v.voted_for_id] = (counts[v.voted_for_id] || 0) + 1;
      });
      const maxVotes = Math.max(0, ...Object.values(counts));
      const winners = Object.entries(counts)
        .filter(([, c]) => c === maxVotes && c > 0)
        .map(([id, c]) => ({ name: playerMap[id] || '?', votes: c }));

      return {
        roundNumber: round.round_number,
        question: round.questionText || '',
        winners,
      };
    });

  const handleNewGame = () => {
    sessionStorage.clear();
    navigate('/');
  };

  return (
    <div className="flex-1 flex flex-col items-center gap-6 w-full animate-pop-in">
      <div className="text-center">
        <div className="text-5xl mb-2">🏆</div>
        <h2 className="text-2xl font-display font-bold text-foreground">
          Classifica Finale
        </h2>
      </div>

      <div className="w-full flex flex-col gap-3">
        {roundResults.map(r => (
          <div
            key={r.roundNumber}
            className="p-4 rounded-2xl bg-card card-shadow"
          >
            <p className="text-sm font-bold text-muted-foreground mb-1">
              Round {r.roundNumber})
            </p>
            <p className="font-display font-bold text-foreground">
              {r.question}
            </p>
            <p className="text-primary font-bold mt-1">
              {r.winners.length > 0
                ? r.winners.map(w => `${w.name} (${w.votes})`).join(', ')
                : 'Nessun voto'}
            </p>
          </div>
        ))}
      </div>

      <div className="mt-auto w-full max-w-xs">
        <Button
          size="lg"
          className="w-full h-14 text-lg font-display font-bold rounded-2xl"
          onClick={handleNewGame}
        >
          🎮 Nuova Partita
        </Button>
      </div>
    </div>
  );
}
