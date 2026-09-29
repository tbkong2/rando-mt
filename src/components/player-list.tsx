import { StyleSheet, Text, View } from 'react-native';

import { COLORS } from '@/components/pixel';
import type { GamePlayer } from '@/lib/game';

// Names as chips. With showDone, finished players get a check mark, so
// everyone can see who the round is waiting on.
export function PlayerList({ players, showDone = false }: { players: GamePlayer[]; showDone?: boolean }) {
  return (
    <View style={styles.list}>
      {players.map((p) => (
        <View key={p.id} style={[styles.chip, p.is_me && styles.me, showDone && p.done && styles.done]}>
          <Text style={styles.name} numberOfLines={1}>
            {p.is_host ? '★ ' : ''}
            {p.name}
            {showDone ? (p.done ? '  ✓' : '  …') : ''}
          </Text>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  list: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  chip: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    backgroundColor: COLORS.panel,
    borderWidth: 1.5,
    borderColor: COLORS.border,
  },
  me: {
    borderColor: COLORS.accent,
  },
  done: {
    backgroundColor: 'rgba(143,227,154,0.18)',
  },
  name: {
    color: COLORS.cream,
    fontSize: 12,
    fontWeight: '700',
    maxWidth: 140,
  },
});
