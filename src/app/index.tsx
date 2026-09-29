import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';

import { COLORS, ErrorNote, PixelButton, PixelFrame, PixelPanel, PixelText } from '@/components/pixel';
import { createRoom, loadName, MAX_NAME, saveName } from '@/lib/game';

export default function Home() {
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadName().then(setName);
  }, []);

  const trimmed = name.trim();

  async function host() {
    setBusy(true);
    setError(null);
    try {
      await saveName(trimmed);
      const roomId = await createRoom(trimmed);
      router.replace({ pathname: '/lobby/[roomId]', params: { roomId } });
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  async function join() {
    await saveName(trimmed);
    router.push('/scan');
  }

  return (
    <PixelFrame title="rando">
      <View style={styles.body}>
        <View style={styles.hero}>
          <PixelText kind="label">a party game for 3–8</PixelText>
          <PixelText style={styles.logo}>CAPTION IT</PixelText>
        </View>

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
          <PixelButton label="Host a game" onPress={host} busy={busy} disabled={!trimmed} />
          <PixelButton
            label="Join with QR"
            variant="secondary"
            onPress={join}
            disabled={!trimmed || busy}
          />
          <ErrorNote message={error} />
        </PixelPanel>
      </View>
    </PixelFrame>
  );
}

const styles = StyleSheet.create({
  body: {
    flex: 1,
    justifyContent: 'center',
    gap: 28,
  },
  hero: {
    alignItems: 'center',
    gap: 6,
  },
  logo: {
    color: COLORS.accent,
    fontSize: 38,
    fontWeight: '900',
    letterSpacing: 2,
    textShadowColor: 'rgba(0,0,0,0.9)',
    textShadowOffset: { width: 0, height: 4 },
    textShadowRadius: 0,
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
