import { useEffect, useMemo, useState, useCallback } from 'react';
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

  const normalizedCode = useMemo(() => (code ? code.toUpperCase() : ''), [code]);
  const storageKey = useMemo(
    () => (normalizedCode ? `playerId:${normalizedCode}` : 'playerId'),
    [normalizedCode]
  );

  const [roomId, setRoomId] = useState<string | null>(null);
  const [playerId, setPlayerId] = useState<string | null>(() => {
    if (!code) return null;
    return localStorage.getItem(`playerId:${code.toUpperCase()}`);
  });

  const [rejoinName, setRejoinName] = useState('');
  const [rejoining, setRejoining] = useState(false);
  const [resolvingRoom, setResolvingRoom] = useState(true);

  const resolveRoom = useCallback(async () => {
    if (!normalizedCode) {
      navigate('/');
      return;
    }

    setResolvingRoom(true);

    const { data, error } = await supabase
      .from('rooms')
      .select('id')
      .eq('code', normalizedCode)
      .maybeSingle();

    if (error) {
      console.error('[room] failed to resolve room code:', error);
      toast.error('Errore nel caricamento della stanza');
      navigate('/');
      return;
    }

    if (!data) {
      navigate('/');
      return;
    }

    setRoomId(data.id);
    setResolvingRoom(false);
  }, [normalizedCode, navigate]);

  useEffect(() => {
    resolveRoom();
  }, [resolveRoom]);

  const gameState = useGameState(roomId, playerId);

  const handleRejoin = useCallback(async () => {
    if (!rejoinName.trim() || !normalizedCode) return;

    setRejoining(true);

    try {
      const { player } = await joinRoom(normalizedCode, rejoinName.trim());
      localStorage.setItem(storageKey, player.id);
      setPlayerId(player.id);
    } catch (e: any) {
      console.error('[room] rejoin error:', e);
      toast.error(e?.message || 'Errore durante il rientro nella stanza');
    } finally {
      setRejoining(false);
    }
  }, [normalizedCode, rejoinName, storageKey]);

  if (resolvingRoom) {
    return (
      <GameLayout>
        <div className="flex-1 flex items-center justify-center">
          <div className="text-2xl font-display animate-float">🎲</div>
        </div>
      </GameLayout>
    );
  }

  // Nessun player nella sessione: proponi rejoin
  if (!playerId) {
    return (
      <GameLayout>
        <div className="flex-1 flex flex-col items-center justify-center gap-6 w-full animate-pop-in">
          <div className="text-5xl">🔄</div>

          <h2 className="text-xl font-display font-bold text-foreground text-center">
            Rientra nella stanza
          </h2>

          <p className="text-muted-foreground text-center text-sm">
            Codice: <span className="font-bold tracking-widest">{normalizedCode}</span>
          </p>

          <div className="flex flex-col gap-3 w-full max-w-xs">
            <Input
              placeholder="Il tuo nome"
              value={rejoinName}
              onChange={(e) => setRejoinName(e.target.value)}
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
          key={gameState.currentRound.id}
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
          key={gameState.currentRound.id}
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
