import { useState, useMemo, useEffect, useCallback } from 'react';
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

export function VotingScreen({
  room,
  players,
  currentRound,
  question,
  hasVoted,
  playerId,
  votes,
}: VotingScreenProps) {
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Reset locale quando cambia round
  useEffect(() => {
    setSelectedId(null);
    setIsSubmitting(false);
  }, [currentRound.id]);

  const totalPlayers = players.length;

  const currentRoundVotes = useMemo(
    () => votes.filter((v) => v.round_id === currentRound.id),
    [votes, currentRound.id]
  );

  const votedCountFromDb = currentRoundVotes.length;
  const alreadyCountedInDb = currentRoundVotes.some((v) => v.voter_id === playerId);

  // Se ho cliccato io ma il realtime non è ancora arrivato, mostro comunque +1
  const optimisticVotedCount =
    selectedId && !alreadyCountedInDb ? votedCountFromDb + 1 : votedCountFromDb;

  const alreadySubmitted = hasVoted || alreadyCountedInDb || selectedId !== null;

  const autoRevealIfComplete = useCallback(async () => {
    const { data: allVotes, error } = await supabase
      .from('votes')
      .select('voter_id')
      .eq('round_id', currentRound.id);

    if (error) {
      console.error('[vote] error while checking vote count:', error);
      return;
    }

    const uniqueVoters = new Set((allVotes ?? []).map((v) => v.voter_id));

    if (uniqueVoters.size >= totalPlayers) {
      console.log('[vote] all players voted, auto-revealing results');
      const { revealResults } = await import('@/lib/gameActions');
      await revealResults(currentRound.id, room.id);
    }
  }, [currentRound.id, room.id, totalPlayers]);

  const handleVote = useCallback(
    async (votedForId: string) => {
      if (isSubmitting || alreadySubmitted) return;

      // UI immediata: un tap solo
      setSelectedId(votedForId);
      setIsSubmitting(true);

      try {
        await submitVote(currentRound.id, playerId, votedForId);
        await autoRevealIfComplete();
      } catch (e: any) {
        console.error('[vote] submit error:', e);
        toast.error(e?.message || 'Errore durante il voto');
        setSelectedId(null);
        setIsSubmitting(false);
      }
    },
    [isSubmitting, alreadySubmitted, currentRound.id, playerId, autoRevealIfComplete]
  );

  if (alreadySubmitted) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center gap-6 w-full animate-pop-in">
        <div className="text-5xl animate-float">✅</div>

        <h2 className="text-xl font-display font-bold text-foreground text-center">
          Voto registrato!
        </h2>

        <p className="text-muted-foreground font-semibold text-center">
          In attesa degli altri giocatori... ({optimisticVotedCount}/{totalPlayers})
        </p>

        <div className="w-full max-w-xs bg-muted rounded-full h-3 overflow-hidden">
          <div
            className="h-full bg-primary rounded-full transition-all duration-500"
            style={{ width: `${totalPlayers > 0 ? (optimisticVotedCount / totalPlayers) * 100 : 0}%` }}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col items-center gap-6 w-full animate-pop-in">
      <div className="bg-card card-shadow rounded-2xl p-5 text-center w-full">
        <p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-2">
          Round {room.current_round}
        </p>

        <h2 className="text-2xl font-display font-bold text-foreground">
          {question}
        </h2>
      </div>

      <div className="grid grid-cols-2 gap-4 w-full">
        {players.map((p) => {
          const playerIndex = players.findIndex((pl) => pl.id === p.id);
          const isSelected = selectedId === p.id;

          return (
            <button
              key={p.id}
              type="button"
              disabled={isSubmitting || alreadySubmitted}
              onPointerUp={(e) => {
                e.preventDefault();
                e.stopPropagation();
                handleVote(p.id);
              }}
              className={[
                'w-full flex flex-col items-center gap-2 p-4 rounded-2xl transition-all duration-200 bg-card card-shadow',
                'select-none touch-manipulation',
                'disabled:opacity-60 disabled:pointer-events-none',
                !isSubmitting && !alreadySubmitted ? 'cursor-pointer hover:scale-105 active:scale-95' : '',
                isSelected ? 'ring-4 ring-primary scale-105' : '',
              ].join(' ')}
            >
              <div className="pointer-events-none w-full flex flex-col items-center gap-2">
                <PlayerAvatar name={p.name} index={playerIndex} size="lg" />

                <span className="font-bold text-foreground text-center">
                  {p.name}
                  {p.id === playerId ? ' (Tu)' : ''}
                </span>
              </div>
            </button>
          );
        })}
      </div>

      {isSubmitting && (
        <p className="text-sm font-semibold text-muted-foreground">
          Invio voto...
        </p>
      )}
    </div>
  );
}
