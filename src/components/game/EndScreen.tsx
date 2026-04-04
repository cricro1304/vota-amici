import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { PlayerAvatar } from './PlayerAvatar';
import type { Tables } from '@/integrations/supabase/types';

interface EndScreenProps {
  players: Tables<'players'>[];
  allVotes: Tables<'votes'>[];
}

export function EndScreen({ players, allVotes }: EndScreenProps) {
  const navigate = useNavigate();

  // Tally all votes across rounds
  const voteCounts: Record<string, number> = {};
  players.forEach(p => (voteCounts[p.id] = 0));
  allVotes.forEach(v => {
    if (voteCounts[v.voted_for_id] !== undefined) {
      voteCounts[v.voted_for_id]++;
    }
  });

  const sorted = [...players].sort((a, b) => (voteCounts[b.id] || 0) - (voteCounts[a.id] || 0));
  const maxVotes = sorted.length > 0 ? voteCounts[sorted[0].id] : 0;

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
        {sorted.map((p, rank) => {
          const count = voteCounts[p.id] || 0;
          const isTop = count === maxVotes && count > 0;
          const playerIndex = players.findIndex(pl => pl.id === p.id);
          const medal = rank === 0 ? '🥇' : rank === 1 ? '🥈' : rank === 2 ? '🥉' : '';

          return (
            <div
              key={p.id}
              className={`
                flex items-center gap-4 p-4 rounded-2xl
                ${isTop ? 'bg-winner/20 winner-glow' : 'bg-card card-shadow'}
              `}
            >
              <span className="text-2xl w-8 text-center">{medal || `${rank + 1}.`}</span>
              <PlayerAvatar name={p.name} index={playerIndex} size="md" isWinner={isTop} />
              <div className="flex-1">
                <p className="font-bold text-foreground">{p.name}</p>
              </div>
              <span className="text-xl font-display font-bold text-primary">
                {count}
              </span>
            </div>
          );
        })}
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
