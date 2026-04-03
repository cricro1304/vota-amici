import { useState, useRef } from 'react';
import { PlayerAvatar } from './PlayerAvatar';
import { submitVote, revealResults } from '@/lib/gameActions';
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
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const submittedRef = useRef(false);

  const totalPlayers = players.length;
  const votedCount = votes.length;

  const handleVote = async (votedForId: string) => {
    if (submittedRef.current || submitting) return;
    submittedRef.current = true;
    setSubmitting(true);
    try {
      await submitVote(currentRound.id, playerId, votedForId);
      setSubmitted(true);

      // Check if all players have now voted (this vote + existing)
      const newVoteCount = votedCount + 1;
      if (newVoteCount >= totalPlayers) {
        console.log('All players voted, auto-revealing results');
        await revealResults(currentRound.id, room.id);
      }
    } catch (e: any) {
      toast.error(e.message);
      submittedRef.current = false;
    } finally {
      setSubmitting(false);
    }
  };

  if (hasVoted || submitted) {
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

  if (submitting) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center gap-6 w-full animate-pop-in">
        <div className="text-5xl animate-float">⏳</div>
        <h2 className="text-xl font-display font-bold text-foreground text-center">
          Invio del voto...
        </h2>
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

      {/* Voting options - includes all players (self-vote allowed) */}
      <div className="grid grid-cols-2 gap-4 w-full">
        {players.map((p) => {
          const playerIndex = players.findIndex(pl => pl.id === p.id);
          return (
            <button
              key={p.id}
              onClick={() => handleVote(p.id)}
              className="flex flex-col items-center gap-2 p-4 rounded-2xl transition-all duration-200 bg-card card-shadow hover:scale-105 active:scale-95"
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
