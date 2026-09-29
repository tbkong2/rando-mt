import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, TextInput, View } from 'react-native';

import { COLORS, ErrorNote, PixelButton, PixelFrame, PixelPanel, PixelText } from '@/components/pixel';
import { joinRoom, loadName, MAX_NAME, saveName } from '@/lib/game';

// Reached from the in-app scanner, or straight from a scanned deep link. If
// the phone already has a name saved it joins immediately; otherwise it asks.
export default function Join() {
  const { roomId } = useLocalSearchParams<{ roomId: string }>();
  const [name, setName] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const tried = useRef(false);

  async function join(asName: string) {
    setBusy(true);
    setError(null);
    try {
      await saveName(asName);
      await joinRoom(roomId, asName);
      router.replace({ pathname: '/lobby/[roomId]', params: { roomId } });
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  // one automatic attempt with the saved name, on first render only
  useEffect(() => {
    loadName().then((saved) => {
      setName(saved);
      if (saved.trim() && !tried.current) {
        tried.current = true;
        join(saved.trim());
      }
    });
  }, []);

  if (name === null || (busy && !error)) {
    return (
      <PixelFrame title="Joining">
        <View style={styles.center}>
          <ActivityIndicator color={COLORS.accent} size="large" />
        </View>
      </PixelFrame>
    );
  }

  return (
    <PixelFrame title="Join a room">
      <View style={styles.center}>
        <PixelPanel style={styles.panel}>
          <PixelText kind="label">Your name</PixelText>
          <TextInput
            value={name}
            onChangeText={setName}
            placeholder="e.g. Tony"
            placeholderTextColor={COLORS.textDim}
            maxLength={MAX_NAME}
            autoCorrect={false}
            style={styles.input}
          />
          <PixelButton label="Join" onPress={() => join(name.trim())} disabled={!name.trim()} busy={busy} />
          <PixelButton label="Cancel" variant="secondary" onPress={() => router.replace('/')} />
          <ErrorNote message={error} />
        </PixelPanel>
      </View>
    </PixelFrame>
  );
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    justifyContent: 'center',
  },
  panel: {
    gap: 12,
  },
  input: {
    color: COLORS.text,
    fontSize: 17,
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 6,
    borderWidth: 1.5,
    borderColor: COLORS.border,
    backgroundColor: 'rgba(0,0,0,0.35)',
  },
});
