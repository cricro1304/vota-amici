import { useState, useEffect, useRef } from 'react';
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
  const voteCounts: Record<string, number> = {};
  players.forEach(p => (voteCounts[p.id] = 0));
  votes.forEach(v => {
    if (voteCounts[v.voted_for_id] !== undefined) {
      voteCounts[v.voted_for_id]++;
    }
  });

  const maxVotes = Math.max(...Object.values(voteCounts));
  // Sort ascending (least votes first) so we reveal from last place to first
  // Sort descending (most votes first) - but reveal from last to first
  const sorted = [...players].sort((a, b) => (voteCounts[b.id] || 0) - (voteCounts[a.id] || 0));

  const [revealedCount, setRevealedCount] = useState(0);
  const roundIdRef = useRef(currentRound.id);

  // Reset reveal when round changes
  useEffect(() => {
    if (roundIdRef.current !== currentRound.id) {
      roundIdRef.current = currentRound.id;
      setRevealedCount(0);
    }
  }, [currentRound.id]);

  // Progressively reveal players
  useEffect(() => {
    if (revealedCount >= sorted.length) return;
    const timer = setTimeout(() => {
      setRevealedCount(prev => prev + 1);
    }, revealedCount === 0 ? 500 : 2000);
    return () => clearTimeout(timer);
  }, [revealedCount, sorted.length]);

  const allRevealed = revealedCount >= sorted.length;

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

      {/* Results - revealed one by one from last to first */}
      <div className="w-full flex flex-col gap-3">
        {sorted.map((p, index) => {
          const isVisible = index < revealedCount;
          if (!isVisible) return null;

          const count = voteCounts[p.id] || 0;
          const isWinner = allRevealed && count === maxVotes && count > 0;
          const playerIndex = players.findIndex(pl => pl.id === p.id);
          // Display position from bottom: last revealed = last place visually shown first
          const position = sorted.length - index;

          return (
            <div
              key={p.id}
              className={`
                flex items-center gap-4 p-4 rounded-2xl transition-all duration-500 animate-pop-in
                ${isWinner ? 'bg-winner/20 winner-glow' : 'bg-card card-shadow'}
              `}
            >
              <span className="text-lg font-bold text-muted-foreground w-6 text-center">
                {position}°
              </span>
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

      {/* Host controls - only show after all revealed */}
      {isHost && allRevealed && (
        <div className="mt-auto w-full max-w-xs flex flex-col gap-3 animate-pop-in">
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
