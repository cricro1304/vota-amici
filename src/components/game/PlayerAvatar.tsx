import { getPlayerInitials, getPlayerColor } from '@/lib/gameUtils';

interface PlayerAvatarProps {
  name: string;
  index: number;
  size?: 'sm' | 'md' | 'lg';
  selected?: boolean;
  isWinner?: boolean;
  onClick?: () => void;
}

const sizeClasses = {
  sm: 'w-10 h-10 text-sm',
  md: 'w-14 h-14 text-lg',
  lg: 'w-20 h-20 text-2xl',
};

export function PlayerAvatar({ name, index, size = 'md', selected, isWinner, onClick }: PlayerAvatarProps) {
  return (
    <button
      onClick={onClick}
      disabled={!onClick}
      className={`
        ${sizeClasses[size]} rounded-full font-display font-bold
        flex items-center justify-center transition-all duration-200
        ${onClick ? 'cursor-pointer hover:scale-110 active:scale-95' : 'cursor-default'}
        ${selected ? 'ring-4 ring-primary scale-110' : ''}
        ${isWinner ? 'winner-glow animate-float' : ''}
      `}
      style={{ backgroundColor: getPlayerColor(index), color: 'white' }}
    >
      {getPlayerInitials(name)}
    </button>
  );
}
