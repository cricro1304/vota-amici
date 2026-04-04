import { useRef, useCallback } from 'react';
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
  // Use a ref map keyed by round ID to track submission state across renders
  const submittedRoundsRef = useRef<Set<string>>(new Set());
  const selectedForRoundRef = useRef<Record<string, string>>({});

  const totalPlayers = players.length;
  const currentRoundVotes = votes.filter(v => v.round_id === currentRound.id);
  const votedCount = currentRoundVotes.length;

  const alreadySubmitted = hasVoted || submittedRoundsRef.current.has(currentRound.id);
  const selectedId = selectedForRoundRef.current[currentRound.id] || null;

  const handleVote = useCallback(async (votedForId: string) => {
    // Guard: only allow one vote per round, ever
    if (submittedRoundsRef.current.has(currentRound.id)) return;
    submittedRoundsRef.current.add(currentRound.id);
    selectedForRoundRef.current[currentRound.id] = votedForId;

    // Force a re-render by using a dummy state isn't needed — the parent will
    // re-render via realtime. But we need the UI to update NOW, so we use
    // a forced update trick: we dispatch a micro-task setState from parent.
    // Actually, since refs don't trigger re-render, we need to force one.
    // We'll use the DOM directly to disable buttons immediately.
    const buttons = document.querySelectorAll('[data-vote-btn]');
    buttons.forEach(btn => (btn as HTMLButtonElement).disabled = true);

    try {
      await submitVote(currentRound.id, playerId, votedForId);
      console.log('[vote] submitted successfully for round', currentRound.id);

      // Check if all players voted
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
      // Rollback on error
      submittedRoundsRef.current.delete(currentRound.id);
      delete selectedForRoundRef.current[currentRound.id];
      buttons.forEach(btn => (btn as HTMLButtonElement).disabled = false);
    }
  }, [currentRound.id, playerId, totalPlayers, room.id]);

  if (alreadySubmitted || selectedId) {
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
          const playerIndex = players.findIndex(pl => pl.id === p.id);
          return (
            <button
              key={p.id}
              data-vote-btn
              onClick={() => handleVote(p.id)}
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
