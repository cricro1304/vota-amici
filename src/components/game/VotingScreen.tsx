import { useState } from 'react';
import { Button } from '@/components/ui/button';
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
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const otherPlayers = players.filter(p => p.id !== playerId);
  const totalPlayers = players.length;
  const votedCount = votes.length;
  const allVoted = votedCount >= totalPlayers;
  const isHost = room.host_player_id === playerId;

  const handleVote = async () => {
    if (!selectedId || !currentRound) return;
    setSubmitting(true);
    try {
      await submitVote(currentRound.id, playerId, selectedId);
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setSubmitting(false);
    }
  };

  // Auto-reveal if all voted and host
  const handleReveal = async () => {
    try {
      await revealResults(currentRound.id, room.id);
    } catch (e: any) {
      toast.error(e.message);
    }
  };

  if (hasVoted) {
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
        {isHost && allVoted && (
          <Button
            size="lg"
            className="h-14 text-lg font-display font-bold rounded-2xl w-full max-w-xs"
            onClick={handleReveal}
          >
            📊 Mostra Risultati
          </Button>
        )}
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
        {otherPlayers.map((p, i) => {
          const playerIndex = players.findIndex(pl => pl.id === p.id);
          const isSelected = selectedId === p.id;
          return (
            <button
              key={p.id}
              onClick={() => setSelectedId(p.id)}
              className={`
                flex flex-col items-center gap-2 p-4 rounded-2xl transition-all duration-200
                ${isSelected
                  ? 'bg-primary/10 ring-2 ring-primary scale-105'
                  : 'bg-card card-shadow hover:scale-105 active:scale-95'
                }
              `}
            >
              <PlayerAvatar name={p.name} index={playerIndex} size="lg" />
              <span className="font-bold text-foreground">{p.name}</span>
            </button>
          );
        })}
      </div>

      {/* Submit */}
      <div className="mt-auto w-full max-w-xs">
        <Button
          size="lg"
          className="w-full h-14 text-lg font-display font-bold rounded-2xl"
          onClick={handleVote}
          disabled={!selectedId || submitting}
        >
          {submitting ? '⏳ Votando...' : '🗳️ Vota!'}
        </Button>
      </div>
    </div>
  );
}
