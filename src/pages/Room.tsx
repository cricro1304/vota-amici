import { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useGameState } from '@/hooks/useGameState';
import { GameLayout } from '@/components/game/GameLayout';
import { LobbyScreen } from '@/components/game/LobbyScreen';
import { VotingScreen } from '@/components/game/VotingScreen';
import { ResultsScreen } from '@/components/game/ResultsScreen';
import { EndScreen } from '@/components/game/EndScreen';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { joinRoom } from '@/lib/gameActions';
import { toast } from 'sonner';

export default function Room() {
  const { code } = useParams<{ code: string }>();
  const navigate = useNavigate();
  const [roomId, setRoomId] = useState<string | null>(null);
  const [playerId, setPlayerId] = useState<string | null>(() => sessionStorage.getItem('playerId'));
  const [rejoinName, setRejoinName] = useState('');
  const [rejoining, setRejoining] = useState(false);

  // Resolve room code to ID
  useEffect(() => {
    if (!code) return;
    supabase
      .from('rooms')
      .select('id')
      .eq('code', code.toUpperCase())
      .single()
      .then(({ data }) => {
        if (data) setRoomId(data.id);
        else navigate('/');
      });
  }, [code, navigate]);

  const gameState = useGameState(roomId, playerId);

  // If no playerId, show rejoin form instead of redirecting
  if (!playerId) {
    const handleRejoin = async () => {
      if (!rejoinName.trim() || !code) return;
      setRejoining(true);
      try {
        const { player } = await joinRoom(code, rejoinName.trim());
        sessionStorage.setItem('playerId', player.id);
        setPlayerId(player.id);
      } catch (e: any) {
        toast.error(e.message);
      } finally {
        setRejoining(false);
      }
    };

    return (
      <GameLayout>
        <div className="flex-1 flex flex-col items-center justify-center gap-6 w-full animate-pop-in">
          <div className="text-5xl">🔄</div>
          <h2 className="text-xl font-display font-bold text-foreground text-center">
            Rientra nella stanza
          </h2>
          <p className="text-muted-foreground text-center text-sm">
            Codice: <span className="font-bold tracking-widest">{code?.toUpperCase()}</span>
          </p>
          <div className="flex flex-col gap-3 w-full max-w-xs">
            <Input
              placeholder="Il tuo nome"
              value={rejoinName}
              onChange={e => setRejoinName(e.target.value)}
              className="h-14 text-lg text-center rounded-2xl font-semibold"
              maxLength={20}
              autoFocus
            />
            <Button
              size="lg"
              className="h-14 text-lg font-display font-bold rounded-2xl"
              onClick={handleRejoin}
              disabled={rejoining}
            >
              {rejoining ? '⏳ Entrando...' : '🚀 Entra'}
            </Button>
          </div>
        </div>
      </GameLayout>
    );
  }

  if (gameState.loading || !gameState.room) {
    return (
      <GameLayout>
        <div className="flex-1 flex items-center justify-center">
          <div className="text-2xl font-display animate-float">🎲</div>
        </div>
      </GameLayout>
    );
  }

  const { room } = gameState;

  return (
    <GameLayout>
      {room.status === 'lobby' && (
        <LobbyScreen
          room={room}
          players={gameState.players}
          isHost={gameState.isHost}
          playerId={playerId}
        />
      )}
      {room.status === 'in_round' && gameState.currentRound && (
        <VotingScreen
          room={room}
          players={gameState.players}
          currentRound={gameState.currentRound}
          question={gameState.currentQuestion || ''}
          hasVoted={gameState.hasVoted}
          playerId={playerId}
          votes={gameState.votes}
        />
      )}
      {room.status === 'results' && gameState.currentRound && (
        <ResultsScreen
          room={room}
          players={gameState.players}
          currentRound={gameState.currentRound}
          question={gameState.currentQuestion || ''}
          votes={gameState.votes}
          isHost={gameState.isHost}
        />
      )}
      {room.status === 'finished' && (
        <EndScreen
          players={gameState.players}
          allVotes={gameState.allVotes}
        />
      )}
    </GameLayout>
  );
}
