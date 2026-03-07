import { Button } from '@/components/ui/button';
import { PlayerAvatar } from './PlayerAvatar';
import { nextRound, endGame } from '@/lib/gameActions';
import { toast } from 'sonner';
import type { Tables } from '@/integrations/supabase/types';

interface ResultsScreenProps {
  room: Tables<'rooms'>;
  players: Tables<'players'>[];
  currentRound: Tables<'rounds'>;
  question: string;
  votes: Tables<'votes'>[];
  isHost: boolean;
}

export function ResultsScreen({ room, players, currentRound, question, votes, isHost }: ResultsScreenProps) {
  // Tally votes
  const voteCounts: Record<string, number> = {};
  players.forEach(p => (voteCounts[p.id] = 0));
  votes.forEach(v => {
    if (voteCounts[v.voted_for_id] !== undefined) {
      voteCounts[v.voted_for_id]++;
    }
  });

  const maxVotes = Math.max(...Object.values(voteCounts));
  const sorted = [...players].sort((a, b) => (voteCounts[b.id] || 0) - (voteCounts[a.id] || 0));

  const handleNext = async () => {
    try {
      await nextRound(room.id, room.current_round);
    } catch (e: any) {
      toast.error(e.message);
    }
  };

  const handleEnd = async () => {
    try {
      await endGame(room.id);
    } catch (e: any) {
      toast.error(e.message);
    }
  };

  return (
    <div className="flex-1 flex flex-col items-center gap-6 w-full animate-pop-in">
      <div className="text-center">
        <p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1">
          Round {room.current_round}
        </p>
        <h2 className="text-xl font-display font-bold text-foreground">
          {question}
        </h2>
      </div>

      {/* Results */}
      <div className="w-full flex flex-col gap-3">
        {sorted.map((p) => {
          const count = voteCounts[p.id] || 0;
          const isWinner = count === maxVotes && count > 0;
          const playerIndex = players.findIndex(pl => pl.id === p.id);

          return (
            <div
              key={p.id}
              className={`
                flex items-center gap-4 p-4 rounded-2xl transition-all
                ${isWinner ? 'bg-winner/20 winner-glow' : 'bg-card card-shadow'}
              `}
            >
              <PlayerAvatar name={p.name} index={playerIndex} size="md" isWinner={isWinner} />
              <div className="flex-1">
                <p className="font-bold text-foreground">
                  {p.name} {isWinner && '🏆'}
                </p>
                <div className="flex items-center gap-2 mt-1">
                  <div className="flex-1 bg-muted rounded-full h-2 overflow-hidden">
                    <div
                      className={`h-full rounded-full transition-all duration-700 ${isWinner ? 'bg-winner' : 'bg-primary/50'}`}
                      style={{ width: votes.length > 0 ? `${(count / votes.length) * 100}%` : '0%' }}
                    />
                  </div>
                  <span className="text-sm font-bold text-muted-foreground min-w-[2rem] text-right">
                    {count}
                  </span>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Host controls */}
      {isHost && (
        <div className="mt-auto w-full max-w-xs flex flex-col gap-3">
          <Button
            size="lg"
            className="w-full h-14 text-lg font-display font-bold rounded-2xl"
            onClick={handleNext}
          >
            ➡️ Prossimo Round
          </Button>
          <Button
            variant="secondary"
            className="w-full h-12 font-display font-bold rounded-2xl"
            onClick={handleEnd}
          >
            🏁 Fine Partita
          </Button>
        </div>
      )}
    </div>
  );
}
