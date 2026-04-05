import { useState, useEffect, useCallback, useRef } from 'react';
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
  allRounds: (Round & { questionText?: string })[];
}

export function useGameState(roomId: string | null, playerId: string | null) {
  const [state, setState] = useState<GameState>({
    room: null,
    players: [],
    currentRound: null,
    votes: [],
    currentQuestion: null,
    allVotes: [],
    allRounds: [],
  });
  const [loading, setLoading] = useState(true);
  const currentRoundIdRef = useRef<string | null>(null);

  const fetchPlayers = useCallback(async () => {
    if (!roomId) return;
    const { data, error } = await supabase.from('players').select('*').eq('room_id', roomId).order('created_at');
    if (error) console.error('fetchPlayers error:', error);
    if (data) setState(s => ({ ...s, players: data }));
  }, [roomId]);

  const fetchVotesForRound = useCallback(async (roundId: string) => {
    const { data, error } = await supabase.from('votes').select('*').eq('round_id', roundId);
    if (error) console.error('fetchVotes error:', error);
    if (data) setState(s => ({ ...s, votes: data }));
  }, []);

  const fetchCurrentRound = useCallback(async () => {
    if (!roomId) return;
    // Always get fresh room state
    const { data: room, error: roomErr } = await supabase.from('rooms').select('*').eq('id', roomId).single();
    if (roomErr) console.error('fetchRoom error:', roomErr);
    if (!room) return;

    setState(s => ({ ...s, room }));

    if ((room.status === 'in_round' || room.status === 'results') && room.current_round > 0) {
      // Get the round matching current_round number
      const { data: round, error: roundErr } = await supabase
        .from('rounds')
        .select('*')
        .eq('room_id', roomId)
        .eq('round_number', room.current_round)
        .single();
      if (roundErr) console.error('fetchRound error:', roundErr);

      if (round) {
        currentRoundIdRef.current = round.id;
        setState(s => ({ ...s, currentRound: round }));

        // Fetch question
        const { data: question } = await supabase
          .from('questions')
          .select('text')
          .eq('id', round.question_id)
          .single();
        if (question) setState(s => ({ ...s, currentQuestion: question.text }));

        // Fetch votes ONLY for this round
        await fetchVotesForRound(round.id);
      }
    } else {
      // Reset round state when not in a round
      currentRoundIdRef.current = null;
      setState(s => ({ ...s, currentRound: null, votes: [], currentQuestion: null }));
    }
  }, [roomId, fetchVotesForRound]);

  const fetchAllVotes = useCallback(async () => {
    if (!roomId) return;
    const { data: rounds } = await supabase.from('rounds').select('*').eq('room_id', roomId).order('round_number');
    if (!rounds || rounds.length === 0) return;
    const roundIds = rounds.map(r => r.id);
    const { data: votes } = await supabase.from('votes').select('*').in('round_id', roundIds);

    // Fetch question texts for all rounds
    const questionIds = [...new Set(rounds.map(r => r.question_id))];
    const { data: questions } = await supabase.from('questions').select('id, text').in('id', questionIds);
    const questionMap: Record<string, string> = {};
    questions?.forEach(q => { questionMap[q.id] = q.text; });

    const allRounds = rounds.map(r => ({ ...r, questionText: questionMap[r.question_id] || '' }));

    setState(s => ({ ...s, allVotes: votes || [], allRounds }));
  }, [roomId]);

  // Initial fetch
  useEffect(() => {
    if (!roomId) return;
    setLoading(true);
    Promise.all([fetchPlayers(), fetchCurrentRound(), fetchAllVotes()]).finally(() =>
      setLoading(false)
    );
  }, [roomId, fetchPlayers, fetchCurrentRound, fetchAllVotes]);

  // Realtime subscriptions
  useEffect(() => {
    if (!roomId) return;

    const channel = supabase
      .channel(`room-${roomId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` }, () => {
        console.log('[realtime] room changed');
        fetchCurrentRound();
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, () => {
        console.log('[realtime] players changed');
        fetchPlayers();
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rounds', filter: `room_id=eq.${roomId}` }, () => {
        console.log('[realtime] rounds changed');
        fetchCurrentRound();
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'votes' }, (payload) => {
        console.log('[realtime] vote inserted', payload);
        // Only refetch votes for current round
        const roundId = currentRoundIdRef.current;
        if (roundId) {
          fetchVotesForRound(roundId);
        }
        fetchAllVotes();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roomId, fetchPlayers, fetchCurrentRound, fetchVotesForRound, fetchAllVotes]);

  const isHost = state.room?.host_player_id === playerId;
  const currentPlayer = state.players.find(p => p.id === playerId);
  // Derive hasVoted from DB votes for current round
  const hasVoted = state.currentRound
    ? state.votes.some(v => v.voter_id === playerId && v.round_id === state.currentRound?.id)
    : false;

  return { ...state, loading, isHost, currentPlayer, hasVoted, refetch: fetchCurrentRound };
}
