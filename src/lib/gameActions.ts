import { supabase } from '@/integrations/supabase/client';
import { generateRoomCode } from './gameUtils';

export async function createRoom(hostName: string, timerSeconds: number | null = null) {
  const code = generateRoomCode();

  const { data: room, error: roomError } = await supabase
    .from('rooms')
    .insert({ code, status: 'lobby', timer_seconds: timerSeconds })
    .select()
    .single();

  if (roomError || !room) {
    console.error('Room creation error:', roomError);
    throw new Error('Errore nella creazione della stanza');
  }

  const { data: player, error: playerError } = await supabase
    .from('players')
    .insert({ room_id: room.id, name: hostName, is_host: true })
    .select()
    .single();

  if (playerError || !player) throw new Error('Errore nella creazione del giocatore');

  await supabase.from('rooms').update({ host_player_id: player.id }).eq('id', room.id);

  return { room, player };
}

export async function joinRoom(roomCode: string, playerName: string) {
  const { data: room, error: roomError } = await supabase
    .from('rooms')
    .select('*')
    .eq('code', roomCode.toUpperCase())
    .single();

  if (roomError || !room) throw new Error('Stanza non trovata');

  // Cerca se esiste già un player con questo nome nella stanza
  const { data: existing } = await supabase
    .from('players')
    .select('*')
    .eq('room_id', room.id)
    .eq('name', playerName)
    .maybeSingle();

  if (existing) {
    // Ritorna il player esistente senza crearne uno nuovo
    return { room, player: existing };
  }

  // Solo se la partita è già iniziata E il giocatore non esiste, blocca
  if (room.status !== 'lobby') throw new Error('La partita è già iniziata');

  const { data: player, error: playerError } = await supabase
    .from('players')
    .insert({ room_id: room.id, name: playerName })
    .select()
    .single();

  if (playerError || !player) throw new Error("Errore nell'unirsi alla stanza");

  return { room, player };
}

export async function startGame(roomId: string) {
  // Get random questions
  const { data: questions } = await supabase
    .from('questions')
    .select('id')
    .eq('pack_id', '00000000-0000-0000-0000-000000000001');

  if (!questions || questions.length === 0) throw new Error('Nessuna domanda disponibile');

  // Shuffle and pick first question
  const shuffled = questions.sort(() => Math.random() - 0.5);
  const firstQuestion = shuffled[0];

  // Create first round
  await supabase.from('rounds').insert({
    room_id: roomId,
    question_id: firstQuestion.id,
    round_number: 1,
    status: 'voting',
  });

  // Update room
  await supabase.from('rooms').update({ status: 'in_round', current_round: 1 }).eq('id', roomId);
}

export async function submitVote(roundId: string, voterId: string, votedForId: string) {
  const { error } = await supabase.from('votes').insert({
    round_id: roundId,
    voter_id: voterId,
    voted_for_id: votedForId,
  });
  if (error) throw new Error('Errore nel voto');
}

export async function revealResults(roundId: string, roomId: string) {
  await supabase.from('rounds').update({ status: 'revealed' }).eq('id', roundId);
  await supabase.from('rooms').update({ status: 'results' }).eq('id', roomId);
}

export async function nextRound(roomId: string, currentRoundNumber: number) {
  // Get already used question IDs
  const { data: usedRounds } = await supabase
    .from('rounds')
    .select('question_id')
    .eq('room_id', roomId);
  const usedIds = usedRounds?.map(r => r.question_id) || [];

  // Get available questions
  const { data: questions } = await supabase
    .from('questions')
    .select('id')
    .eq('pack_id', '00000000-0000-0000-0000-000000000001');

  const available = questions?.filter(q => !usedIds.includes(q.id)) || [];

  if (available.length === 0 || currentRoundNumber >= 10) {
    // End game (no more questions or max 10 rounds reached)
    await supabase.from('rooms').update({ status: 'finished' }).eq('id', roomId);
    return;
  }

  const nextQuestion = available[Math.floor(Math.random() * available.length)];
  const nextRoundNum = currentRoundNumber + 1;

  // Close current round
  const { data: currentRound } = await supabase
    .from('rounds')
    .select('id')
    .eq('room_id', roomId)
    .eq('round_number', currentRoundNumber)
    .single();
  if (currentRound) {
    await supabase.from('rounds').update({ status: 'closed' }).eq('id', currentRound.id);
  }

  await supabase.from('rounds').insert({
    room_id: roomId,
    question_id: nextQuestion.id,
    round_number: nextRoundNum,
    status: 'voting',
  });

  await supabase.from('rooms').update({ status: 'in_round', current_round: nextRoundNum }).eq('id', roomId);
}

export async function endGame(roomId: string) {
  await supabase.from('rooms').update({ status: 'finished' }).eq('id', roomId);
}
