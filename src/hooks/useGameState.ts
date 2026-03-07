import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { Tables } from '@/integrations/supabase/types';

type Room = Tables<'rooms'>;
type Player = Tables<'players'>;
type Round = Tables<'rounds'>;
type Vote = Tables<'votes'>;

interface GameState {
  room: Room | null;
  players: Player[];
  currentRound: Round | null;
  votes: Vote[];
  currentQuestion: string | null;
  allVotes: Vote[];
}

export function useGameState(roomId: string | null, playerId: string | null) {
  const [state, setState] = useState<GameState>({
    room: null,
    players: [],
    currentRound: null,
    votes: [],
    currentQuestion: null,
    allVotes: [],
  });
  const [loading, setLoading] = useState(true);

  const fetchRoom = useCallback(async () => {
    if (!roomId) return;
    const { data } = await supabase.from('rooms').select('*').eq('id', roomId).single();
    if (data) setState(s => ({ ...s, room: data }));
  }, [roomId]);

  const fetchPlayers = useCallback(async () => {
    if (!roomId) return;
    const { data } = await supabase.from('players').select('*').eq('room_id', roomId).order('created_at');
    if (data) setState(s => ({ ...s, players: data }));
  }, [roomId]);

  const fetchCurrentRound = useCallback(async () => {
    if (!roomId) return;
    const { data: room } = await supabase.from('rooms').select('*').eq('id', roomId).single();
    if (!room) return;
    setState(s => ({ ...s, room }));

    if (room.status === 'in_round' || room.status === 'results') {
      const { data: round } = await supabase
        .from('rounds')
        .select('*')
        .eq('room_id', roomId)
        .eq('round_number', room.current_round)
        .single();
      if (round) {
        setState(s => ({ ...s, currentRound: round }));
        // Fetch question
        const { data: question } = await supabase
          .from('questions')
          .select('text')
          .eq('id', round.question_id)
          .single();
        if (question) setState(s => ({ ...s, currentQuestion: question.text }));
        // Fetch votes for this round
        const { data: votes } = await supabase.from('votes').select('*').eq('round_id', round.id);
        if (votes) setState(s => ({ ...s, votes }));
      }
    }
  }, [roomId]);

  const fetchAllVotes = useCallback(async () => {
    if (!roomId) return;
    const { data: rounds } = await supabase.from('rounds').select('id').eq('room_id', roomId);
    if (!rounds || rounds.length === 0) return;
    const roundIds = rounds.map(r => r.id);
    const { data: votes } = await supabase.from('votes').select('*').in('round_id', roundIds);
    if (votes) setState(s => ({ ...s, allVotes: votes }));
  }, [roomId]);

  // Initial fetch
  useEffect(() => {
    if (!roomId) return;
    setLoading(true);
    Promise.all([fetchRoom(), fetchPlayers(), fetchCurrentRound(), fetchAllVotes()]).finally(() =>
      setLoading(false)
    );
  }, [roomId, fetchRoom, fetchPlayers, fetchCurrentRound, fetchAllVotes]);

  // Realtime subscriptions
  useEffect(() => {
    if (!roomId) return;

    const roomChannel = supabase
      .channel(`room-${roomId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` }, () => {
        fetchRoom();
        fetchCurrentRound();
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, () => {
        fetchPlayers();
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rounds', filter: `room_id=eq.${roomId}` }, () => {
        fetchCurrentRound();
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'votes' }, () => {
        fetchCurrentRound();
        fetchAllVotes();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(roomChannel);
    };
  }, [roomId, fetchRoom, fetchPlayers, fetchCurrentRound, fetchAllVotes]);

  const isHost = state.room?.host_player_id === playerId;
  const currentPlayer = state.players.find(p => p.id === playerId);
  const hasVoted = state.votes.some(v => v.voter_id === playerId);

  return { ...state, loading, isHost, currentPlayer, hasVoted, refetch: fetchCurrentRound };
}
