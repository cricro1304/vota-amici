export function generateRoomCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 5; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

export function getPlayerInitials(name: string): string {
  return name.slice(0, 2).toUpperCase();
}

export const PLAYER_COLORS = [
  'hsl(350, 80%, 55%)',
  'hsl(210, 70%, 55%)',
  'hsl(160, 60%, 45%)',
  'hsl(45, 100%, 50%)',
  'hsl(280, 60%, 55%)',
  'hsl(30, 90%, 55%)',
  'hsl(190, 70%, 45%)',
  'hsl(330, 60%, 50%)',
];

export function getPlayerColor(index: number): string {
  return PLAYER_COLORS[index % PLAYER_COLORS.length];
}
