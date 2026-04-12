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

type RevealPhase = 'intro' | 'suspense' | 'reveal';

export function ResultsScreen({ room, players, currentRound, question, votes, isHost }: ResultsScreenProps) {
  const voteCounts: Record<string, number> = {};
  players.forEach(p => (voteCounts[p.id] = 0));
  votes.forEach(v => {
    if (voteCounts[v.voted_for_id] !== undefined) {
      voteCounts[v.voted_for_id]++;
    }
  });

  const maxVotes = Math.max(0, ...Object.values(voteCounts));
  const winners = maxVotes > 0
    ? players.filter(p => voteCounts[p.id] === maxVotes)
    : [];

  const [phase, setPhase] = useState<RevealPhase>('intro');
  const roundIdRef = useRef(currentRound.id);

  useEffect(() => {
    if (roundIdRef.current !== currentRound.id) {
      roundIdRef.current = currentRound.id;
      setPhase('intro');
    }
  }, [currentRound.id]);

  useEffect(() => {
    if (phase === 'intro') {
      const t = setTimeout(() => setPhase('suspense'), 1500);
      return () => clearTimeout(t);
    }
    if (phase === 'suspense') {
      const t = setTimeout(() => setPhase('reveal'), 3000);
      return () => clearTimeout(t);
    }
  }, [phase]);

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
    <div className="flex-1 flex flex-col items-center justify-center gap-6 w-full">
      {/* Question context */}
      <div className="text-center">
        <p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1">
          Round {room.current_round}
        </p>
      </div>

      {/* Phase: intro */}
      {phase === 'intro' && (
        <div className="text-center animate-fade-in">
          <h2 className="text-2xl font-display font-bold text-foreground">
            {question.replace(/^Chi è il più /, 'Il più ').replace(/^Chi è la più /, 'La più ').replace(/\?$/, '')} è...
          </h2>
        </div>
      )}

      {/* Phase: suspense - dots animation */}
      {phase === 'suspense' && (
        <div className="text-center flex flex-col items-center gap-4">
          <h2 className="text-2xl font-display font-bold text-foreground">
            {question.replace(/^Chi è il più /, 'Il più ').replace(/^Chi è la più /, 'La più ').replace(/\?$/, '')} è...
          </h2>
          <div className="flex gap-2 mt-4">
            <span className="w-4 h-4 rounded-full bg-primary animate-bounce" style={{ animationDelay: '0ms' }} />
            <span className="w-4 h-4 rounded-full bg-primary animate-bounce" style={{ animationDelay: '150ms' }} />
            <span className="w-4 h-4 rounded-full bg-primary animate-bounce" style={{ animationDelay: '300ms' }} />
          </div>
        </div>
      )}

      {/* Phase: reveal */}
      {phase === 'reveal' && (
        <div className="text-center flex flex-col items-center gap-6 animate-pop-in">
          <h2 className="text-xl font-display font-bold text-muted-foreground">
            {question.replace(/^Chi è il più /, 'Il più ').replace(/^Chi è la più /, 'La più ').replace(/\?$/, '')} è...
          </h2>

          {winners.length === 0 ? (
            <p className="text-2xl font-display font-bold text-foreground">Nessun voto!</p>
          ) : (
            <div className="flex flex-col items-center gap-4">
              <div className="flex flex-wrap justify-center gap-6">
                {winners.map(w => {
                  const playerIndex = players.findIndex(pl => pl.id === w.id);
                  return (
                    <div key={w.id} className="flex flex-col items-center gap-2">
                      <PlayerAvatar name={w.name} index={playerIndex} size="lg" isWinner />
                      <p className="text-3xl font-display font-bold text-foreground">
                        {w.name}
                      </p>
                    </div>
                  );
                })}
              </div>
              <p className="text-lg text-muted-foreground font-bold">
                🏆 {winners.length > 1 ? `${maxVotes} voti a testa!` : `con ${maxVotes} vot${maxVotes === 1 ? 'o' : 'i'}!`}
              </p>
            </div>
          )}
        </div>
      )}

      {/* Host controls */}
      {isHost && phase === 'reveal' && (
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
