import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { GameLayout } from '@/components/game/GameLayout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { createRoom, joinRoom } from '@/lib/gameActions';
import { toast } from 'sonner';

type Mode = 'home' | 'create' | 'join';

export default function Home() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<Mode>('home');
  const [name, setName] = useState('');
  const [roomCode, setRoomCode] = useState('');
  const [loading, setLoading] = useState(false);
  const [timerEnabled, setTimerEnabled] = useState(false);

  const handleCreate = async () => {
    if (!name.trim()) return toast.error('Inserisci il tuo nome!');
    setLoading(true);
    try {
      const { room, player } = await createRoom(name.trim());
      localStorage.setItem(`playerId:${room.code}`, player.id);
      navigate(`/room/${room.code}`);
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setLoading(false);
    }
  };

  const handleJoin = async () => {
    if (!name.trim()) return toast.error('Inserisci il tuo nome!');
    if (!roomCode.trim()) return toast.error('Inserisci il codice stanza!');
    setLoading(true);
    try {
      const { room, player } = await joinRoom(roomCode.trim(), name.trim());
      localStorage.setItem(`playerId:${room.code}`, player.id);
      navigate(`/room/${room.code}`);
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <GameLayout>
      <div className="flex-1 flex flex-col items-center justify-center gap-8 w-full">
        <div className="text-center animate-pop-in">
          <div className="text-6xl mb-4">🎭</div>
          <h2 className="text-3xl font-display font-bold text-foreground">
            Chi è il più...?
          </h2>
          <p className="text-muted-foreground mt-2 font-medium">
            Il gioco di voto tra amici!
          </p>
        </div>

        {mode === 'home' && (
          <div className="flex flex-col gap-4 w-full max-w-xs animate-pop-in" style={{ animationDelay: '0.1s' }}>
            <Button
              size="lg"
              className="h-14 text-lg font-display font-bold rounded-2xl"
              onClick={() => setMode('create')}
            >
              🏠 Crea Stanza
            </Button>
            <Button
              size="lg"
              variant="secondary"
              className="h-14 text-lg font-display font-bold rounded-2xl"
              onClick={() => setMode('join')}
            >
              🚪 Unisciti
            </Button>
          </div>
        )}

        {mode === 'create' && (
          <div className="flex flex-col gap-4 w-full max-w-xs animate-pop-in">
            <Input
              placeholder="Il tuo nome"
              value={name}
              onChange={e => setName(e.target.value)}
              className="h-14 text-lg text-center rounded-2xl font-semibold"
              maxLength={20}
              autoFocus
            />
            <Button
              size="lg"
              className="h-14 text-lg font-display font-bold rounded-2xl"
              onClick={handleCreate}
              disabled={loading}
            >
              {loading ? '⏳ Creando...' : '🎮 Crea Partita'}
            </Button>
            <Button
              variant="ghost"
              className="font-semibold text-muted-foreground"
              onClick={() => setMode('home')}
            >
              ← Indietro
            </Button>
          </div>
        )}

        {mode === 'join' && (
          <div className="flex flex-col gap-4 w-full max-w-xs animate-pop-in">
            <Input
              placeholder="Codice stanza"
              value={roomCode}
              onChange={e => setRoomCode(e.target.value.toUpperCase())}
              className="h-14 text-lg text-center rounded-2xl font-bold tracking-[0.3em]"
              maxLength={5}
              autoFocus
            />
            <Input
              placeholder="Il tuo nome"
              value={name}
              onChange={e => setName(e.target.value)}
              className="h-14 text-lg text-center rounded-2xl font-semibold"
              maxLength={20}
            />
            <Button
              size="lg"
              className="h-14 text-lg font-display font-bold rounded-2xl"
              onClick={handleJoin}
              disabled={loading}
            >
              {loading ? '⏳ Entrando...' : '🚀 Entra'}
            </Button>
            <Button
              variant="ghost"
              className="font-semibold text-muted-foreground"
              onClick={() => setMode('home')}
            >
              ← Indietro
            </Button>
          </div>
        )}
      </div>
    </GameLayout>
  );
}
