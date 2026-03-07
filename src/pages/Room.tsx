import { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useGameState } from '@/hooks/useGameState';
import { GameLayout } from '@/components/game/GameLayout';
import { LobbyScreen } from '@/components/game/LobbyScreen';
import { VotingScreen } from '@/components/game/VotingScreen';
import { ResultsScreen } from '@/components/game/ResultsScreen';
import { EndScreen } from '@/components/game/EndScreen';

export default function Room() {
  const { code } = useParams<{ code: string }>();
  const navigate = useNavigate();
  const [roomId, setRoomId] = useState<string | null>(null);
  const playerId = sessionStorage.getItem('playerId');

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

  if (!playerId) {
    navigate('/');
    return null;
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
