import { useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import type { Tables } from '@/integrations/supabase/types';

interface EndScreenProps {
  players: Tables<'players'>[];
  allVotes: Tables<'votes'>[];
  rounds?: Tables<'rounds'>[];
  questions?: Tables<'questions'>[];
}

type RecapItem = {
  roundNumber: number;
  questionText: string;
  winnerNames: string[];
  winnerVotes: number;
};

export function EndScreen({
  players,
  allVotes,
  rounds = [],
  questions = [],
}: EndScreenProps) {
  const navigate = useNavigate();

  const recap = useMemo<RecapItem[]>(() => {
    const questionMap = new Map(questions.map((q) => [q.id, q.text]));
    const playerMap = new Map(players.map((p) => [p.id, p.name]));

    return [...rounds]
      .sort((a, b) => a.round_number - b.round_number)
      .map((round) => {
        const roundVotes = allVotes.filter((v) => v.round_id === round.id);

        const counts: Record<string, number> = {};
        for (const vote of roundVotes) {
          counts[vote.voted_for_id] = (counts[vote.voted_for_id] || 0) + 1;
        }

        const maxVotes =
          Object.keys(counts).length > 0 ? Math.max(...Object.values(counts)) : 0;

        const winnerIds =
          maxVotes > 0
            ? Object.entries(counts)
                .filter(([_, count]) => count === maxVotes)
                .map(([playerId]) => playerId)
            : [];

        const winnerNames =
          winnerIds.length > 0
            ? winnerIds.map((id) => playerMap.get(id) || 'Sconosciuto')
            : ['Nessuno'];

        return {
          roundNumber: round.round_number,
          questionText: questionMap.get(round.question_id) || `Round ${round.round_number}`,
          winnerNames,
          winnerVotes: maxVotes,
        };
      });
  }, [players, allVotes, rounds, questions]);

  const handleNewGame = () => {
    sessionStorage.clear();
    navigate('/');
  };

  return (
    <div className="flex-1 flex flex-col items-center gap-6 w-full animate-pop-in">
      <div className="text-center">
        <div className="text-5xl mb-2">🏁</div>
        <h2 className="text-2xl font-display font-bold text-foreground">
          Recap Finale
        </h2>
      </div>

      <div className="w-full flex flex-col gap-3">
        {recap.length > 0 ? (
          recap.map((item) => (
            <div
              key={item.roundNumber}
              className="bg-card card-shadow rounded-2xl p-4"
            >
              <p className="font-bold text-foreground text-lg leading-relaxed">
                {item.roundNumber}) {item.questionText}: {item.winnerNames.join(', ')}{' '}
                <span className="text-primary">({item.winnerVotes} voti)</span>
              </p>
            </div>
          ))
        ) : (
          <div className="bg-card card-shadow rounded-2xl p-4 text-center">
            <p className="font-bold text-foreground">Nessun recap disponibile</p>
            <p className="text-muted-foreground text-sm mt-1">
              Controlla che rounds e questions vengano passati correttamente a EndScreen.
            </p>
          </div>
        )}
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
