import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { Tables } from '@/integrations/supabase/types';

type Room = Tables<'rooms'>;
type Player = Tables<'players'>;
type Round = Tables<'rounds'>;
type Vote = Tables<'votes'>;
type Question = Tables<'questions'>;

interface GameState {
  room: Room | null;
  players: Player[];
  rounds: Round[];
  questions: Question[];
  currentRound: Round | null;
  votes: Vote[];
  currentQuestion: string | null;
  allVotes: Vote[];
}

export function useGameState(roomId: string | null, playerId: string | null) {
  const [state, setState] = useState<GameState>({
    room: null,
    players: [],
    rounds: [],
    questions: [],
    currentRound: null,
    votes: [],
    currentQuestion: null,
    allVotes: [],
  });

  const [loading, setLoading] = useState(true);
  const currentRoundIdRef = useRef<string | null>(null);

  const fetchRoom = useCallback(async () => {
    if (!roomId) return null;

    const { data, error } = await supabase
      .from('rooms')
      .select('*')
      .eq('id', roomId)
      .single();

    if (error) {
      console.error('fetchRoom error:', error);
      return null;
    }

    if (data) {
      setState((s) => ({ ...s, room: data }));
    }

    return data;
  }, [roomId]);

  const fetchPlayers = useCallback(async () => {
    if (!roomId) return;

    const { data, error } = await supabase
      .from('players')
      .select('*')
      .eq('room_id', roomId)
      .order('created_at');

    if (error) {
      console.error('fetchPlayers error:', error);
      return;
    }

    if (data) {
      setState((s) => ({ ...s, players: data }));
    }
  }, [roomId]);

  const fetchRounds = useCallback(async () => {
    if (!roomId) return [];

    const { data, error } = await supabase
      .from('rounds')
      .select('*')
      .eq('room_id', roomId)
      .order('round_number', { ascending: true });

    if (error) {
      console.error('fetchRounds error:', error);
      return [];
    }

    const rounds = data || [];
    setState((s) => ({ ...s, rounds }));
    return rounds;
  }, [roomId]);

  const fetchQuestionsForRounds = useCallback(async (rounds: Round[]) => {
    if (!rounds.length) {
      setState((s) => ({ ...s, questions: [] }));
      return [];
    }

    const questionIds = [...new Set(rounds.map((r) => r.question_id).filter(Boolean))];

    if (!questionIds.length) {
      setState((s) => ({ ...s, questions: [] }));
      return [];
    }

    const { data, error } = await supabase
      .from('questions')
      .select('*')
      .in('id', questionIds);

    if (error) {
      console.error('fetchQuestions error:', error);
      return [];
    }

    const questions = data || [];
    setState((s) => ({ ...s, questions }));
    return questions;
  }, []);

  const fetchVotesForRound = useCallback(async (roundId: string) => {
    const { data, error } = await supabase
      .from('votes')
      .select('*')
      .eq('round_id', roundId);

    if (error) {
      console.error('fetchVotesForRound error:', error);
      return;
    }

    if (data) {
      setState((s) => ({ ...s, votes: data }));
    }
  }, []);

  const fetchAllVotes = useCallback(async (roundsArg?: Round[]) => {
    if (!roomId) return;

    let roundsToUse = roundsArg;

    if (!roundsToUse) {
      const { data: fetchedRounds, error: roundsError } = await supabase
        .from('rounds')
        .select('id')
        .eq('room_id', roomId);

      if (roundsError) {
        console.error('fetchAllVotes rounds error:', roundsError);
        return;
      }

      roundsToUse = (fetchedRounds || []) as Round[];
    }

    if (!roundsToUse.length) {
      setState((s) => ({ ...s, allVotes: [] }));
      return;
    }

    const roundIds = roundsToUse.map((r) => r.id);

    const { data, error } = await supabase
      .from('votes')
      .select('*')
      .in('round_id', roundIds);

    if (error) {
      console.error('fetchAllVotes error:', error);
      return;
    }

    setState((s) => ({ ...s, allVotes: data || [] }));
  }, [roomId]);

  const fetchCurrentRound = useCallback(async (roomArg?: Room | null, roundsArg?: Round[]) => {
    if (!roomId) return;

    const room = roomArg ?? (await fetchRoom());
    if (!room) return;

    const rounds = roundsArg ?? state.rounds;

    if ((room.status === 'in_round' || room.status === 'results') && room.current_round > 0) {
      const round =
        rounds.find((r) => r.round_number === room.current_round) || null;

      if (!round) {
        console.warn('fetchCurrentRound: no round found for current_round', room.current_round);
        currentRoundIdRef.current = null;
        setState((s) => ({
          ...s,
          currentRound: null,
          votes: [],
          currentQuestion: null,
        }));
        return;
      }

      currentRoundIdRef.current = round.id;

      const question =
        state.questions.find((q) => q.id === round.question_id) || null;

      setState((s) => ({
        ...s,
        currentRound: round,
        currentQuestion: question?.text || null,
      }));

      await fetchVotesForRound(round.id);
    } else {
      currentRoundIdRef.current = null;
      setState((s) => ({
        ...s,
        currentRound: null,
        votes: [],
        currentQuestion: null,
      }));
    }
  }, [roomId, fetchRoom, fetchVotesForRound, state.rounds, state.questions]);

  const fetchEverything = useCallback(async () => {
    if (!roomId) return;

    setLoading(true);

    try {
      const room = await fetchRoom();
      await fetchPlayers();

      const rounds = await fetchRounds();
      await fetchQuestionsForRounds(rounds);
      await fetchAllVotes(rounds);
      await fetchCurrentRound(room, rounds);
    } finally {
      setLoading(false);
    }
  }, [
    roomId,
    fetchRoom,
    fetchPlayers,
    fetchRounds,
    fetchQuestionsForRounds,
    fetchAllVotes,
    fetchCurrentRound,
  ]);

  useEffect(() => {
    if (!roomId) return;
    fetchEverything();
  }, [roomId, fetchEverything]);

  useEffect(() => {
    if (!roomId) return;

    const channel = supabase
      .channel(`room-${roomId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` },
        async () => {
          console.log('[realtime] room changed');
          const room = await fetchRoom();
          await fetchCurrentRound(room, state.rounds);
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` },
        async () => {
          console.log('[realtime] players changed');
          await fetchPlayers();
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rounds', filter: `room_id=eq.${roomId}` },
        async () => {
          console.log('[realtime] rounds changed');
          const rounds = await fetchRounds();
          await fetchQuestionsForRounds(rounds);
          await fetchAllVotes(rounds);

          const room = state.room ?? (await fetchRoom());
          await fetchCurrentRound(room, rounds);
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'questions' },
        async () => {
          console.log('[realtime] questions changed');
          await fetchQuestionsForRounds(state.rounds);
        }
      )
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'votes' },
        async () => {
          console.log('[realtime] vote inserted');

          const roundId = currentRoundIdRef.current;
          if (roundId) {
            await fetchVotesForRound(roundId);
          }

          await fetchAllVotes(state.rounds);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [
    roomId,
    fetchRoom,
    fetchPlayers,
    fetchRounds,
    fetchQuestionsForRounds,
    fetchVotesForRound,
    fetchAllVotes,
    fetchCurrentRound,
    state.room,
    state.rounds,
  ]);

  const isHost = state.room?.host_player_id === playerId;
  const currentPlayer = state.players.find((p) => p.id === playerId) || null;

  const hasVoted = state.currentRound
    ? state.votes.some(
        (v) => v.voter_id === playerId && v.round_id === state.currentRound?.id
      )
    : false;

  return {
    ...state,
    loading,
    isHost,
    currentPlayer,
    hasVoted,
    refetch: fetchEverything,
  };
}
