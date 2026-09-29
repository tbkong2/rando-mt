import { useCallback, useEffect, useRef, useState } from 'react';

import { getGameState, type GameState } from '@/lib/game';
import { supabase } from '@/lib/supabase';

// Keeps a room's game state fresh. The server bumps rooms.version on every
// change, and Realtime pushes that row update to every phone in the room; each
// push triggers a refetch. A slow poll backs it up in case a push is missed
// (e.g. the phone was asleep).
export function useGameState(roomId: string) {
  const [state, setState] = useState<GameState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const versionRef = useRef(-1);

  const refresh = useCallback(async () => {
    try {
      const next = await getGameState(roomId);
      // responses can arrive out of order; never go back to an older state
      if (next.room.version >= versionRef.current) {
        versionRef.current = next.room.version;
        setState(next);
      }
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }, [roomId]);

  useEffect(() => {
    versionRef.current = -1;
    refresh();

    const channel = supabase
      .channel(`room:${roomId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` },
        () => refresh()
      )
      .subscribe();
    const poll = setInterval(refresh, 5000);

    return () => {
      clearInterval(poll);
      supabase.removeChannel(channel);
    };
  }, [roomId, refresh]);

  return { state, error, refresh };
}
