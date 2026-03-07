import { Button } from '@/components/ui/button';
import { PlayerAvatar } from './PlayerAvatar';
import { startGame } from '@/lib/gameActions';
import { toast } from 'sonner';
import type { Tables } from '@/integrations/supabase/types';

interface LobbyScreenProps {
  room: Tables<'rooms'>;
  players: Tables<'players'>[];
  isHost: boolean;
  playerId: string;
}

export function LobbyScreen({ room, players, isHost, playerId }: LobbyScreenProps) {
  const handleStart = async () => {
    if (players.length < 3) {
      toast.error('Servono almeno 3 giocatori!');
      return;
    }
    try {
      await startGame(room.id);
    } catch (e: any) {
      toast.error(e.message);
    }
  };

  return (
    <div className="flex-1 flex flex-col items-center gap-6 w-full animate-pop-in">
      {/* Room Code */}
      <div className="bg-card card-shadow rounded-2xl p-6 text-center w-full">
        <p className="text-sm font-semibold text-muted-foreground uppercase tracking-wider mb-1">
          Codice Stanza
        </p>
        <p className="text-4xl font-display font-bold tracking-[0.4em] text-primary">
          {room.code}
        </p>
        <p className="text-xs text-muted-foreground mt-2">
          Condividi questo codice con i tuoi amici!
        </p>
      </div>

      {/* Players */}
      <div className="w-full">
        <h3 className="text-lg font-display font-bold text-foreground mb-4 text-center">
          Giocatori ({players.length})
        </h3>
        <div className="flex flex-wrap justify-center gap-4">
          {players.map((p, i) => (
            <div key={p.id} className="flex flex-col items-center gap-1 animate-pop-in" style={{ animationDelay: `${i * 0.05}s` }}>
              <PlayerAvatar name={p.name} index={i} size="md" />
              <span className={`text-sm font-semibold ${p.id === playerId ? 'text-primary' : 'text-foreground'}`}>
                {p.name}
                {p.is_host && ' 👑'}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Waiting / Start */}
      <div className="mt-auto w-full max-w-xs">
        {isHost ? (
          <Button
            size="lg"
            className="w-full h-14 text-lg font-display font-bold rounded-2xl"
            onClick={handleStart}
          >
            🚀 Inizia Partita
          </Button>
        ) : (
          <div className="text-center">
            <div className="text-3xl animate-float mb-2">⏳</div>
            <p className="text-muted-foreground font-semibold">
              In attesa che l'host inizi la partita...
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
