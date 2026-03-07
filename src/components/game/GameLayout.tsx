import { ReactNode } from 'react';

interface GameLayoutProps {
  children: ReactNode;
}

export function GameLayout({ children }: GameLayoutProps) {
  return (
    <div className="min-h-screen bg-background flex flex-col">
      <header className="game-gradient py-3 px-4 text-center">
        <h1 className="text-xl font-display font-bold text-primary-foreground tracking-wide">
          🎉 Chi è il più...?
        </h1>
      </header>
      <main className="flex-1 flex flex-col items-center px-4 py-6 max-w-lg mx-auto w-full">
        {children}
      </main>
    </div>
  );
}
