import { useState, useRef, useEffect } from 'react';
import { PlayerAvatar } from './PlayerAvatar';
import { submitVote } from '@/lib/gameActions';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import type { Tables } from '@/integrations/supabase/types';

interface VotingScreenProps {
  room: Tables<'rooms'>;
  players: Tables<'players'>[];
  currentRound: Tables<'rounds'>;
  question: string;
  hasVoted: boolean;
  playerId: string;
  votes: Tables<'votes'>[];
}

export function VotingScreen({ room, players, currentRound, question, hasVoted, playerId, votes }: VotingScreenProps) {
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const submittedRef = useRef(false);
  const lastRoundIdRef = useRef<string | null>(null);

  // Reset local state when round changes
  useEffect(() => {
    if (currentRound.id !== lastRoundIdRef.current) {
      lastRoundIdRef.current = currentRound.id;
      setSelectedId(null);
      setSubmitting(false);
      submittedRef.current = false;
    }
  }, [currentRound.id]);

  const totalPlayers = players.length;
  // Only count votes for THIS round
  const currentRoundVotes = votes.filter(v => v.round_id === currentRound.id);
  const votedCount = currentRoundVotes.length;

  const handleVote = async (votedForId: string) => {
    if (submittedRef.current || submitting || hasVoted) return;
    submittedRef.current = true;
    setSelectedId(votedForId);
    setSubmitting(true);

    try {
      await submitVote(currentRound.id, playerId, votedForId);
      console.log('[vote] submitted successfully');

      // After vote, check actual count from DB to decide auto-reveal
      const { data: allVotes, error } = await supabase
        .from('votes')
        .select('id')
        .eq('round_id', currentRound.id);

      if (error) {
        console.error('[vote] count check error:', error);
      } else if (allVotes && allVotes.length >= totalPlayers) {
        console.log('[vote] all players voted, auto-revealing');
        const { revealResults } = await import('@/lib/gameActions');
        await revealResults(currentRound.id, room.id);
      }
    } catch (e: any) {
      toast.error(e.message);
      submittedRef.current = false;
      setSelectedId(null);
    } finally {
      setSubmitting(false);
    }
  };

  if (hasVoted || selectedId) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center gap-6 w-full animate-pop-in">
        <div className="text-5xl animate-float">✅</div>
        <h2 className="text-xl font-display font-bold text-foreground text-center">
          Voto registrato!
        </h2>
        <p className="text-muted-foreground font-semibold text-center">
          In attesa degli altri giocatori... ({votedCount}/{totalPlayers})
        </p>
        <div className="w-full max-w-xs bg-muted rounded-full h-3 overflow-hidden">
          <div
            className="h-full bg-primary rounded-full transition-all duration-500"
            style={{ width: `${(votedCount / totalPlayers) * 100}%` }}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col items-center gap-6 w-full animate-pop-in">
      {/* Round info */}
      <div className="bg-card card-shadow rounded-2xl p-5 text-center w-full">
        <p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-2">
          Round {room.current_round}
        </p>
        <h2 className="text-2xl font-display font-bold text-foreground">
          {question}
        </h2>
      </div>

      {/* Voting options */}
      <div className="grid grid-cols-2 gap-4 w-full">
        {players.map((p) => {
          const playerIndex = players.findIndex(pl => pl.id === p.id);
          return (
            <button
              key={p.id}
              onClick={() => handleVote(p.id)}
              disabled={submitting || hasVoted}
              className="flex flex-col items-center gap-2 p-4 rounded-2xl transition-all duration-200 bg-card card-shadow hover:scale-105 active:scale-95 disabled:opacity-50 disabled:pointer-events-none"
            >
              <PlayerAvatar name={p.name} index={playerIndex} size="lg" />
              <span className="font-bold text-foreground">
                {p.name}{p.id === playerId ? ' (Tu)' : ''}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
