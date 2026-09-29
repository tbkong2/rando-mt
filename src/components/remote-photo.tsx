import { Image } from 'expo-image';
import { useEffect, useState } from 'react';
import { ActivityIndicator, StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native';

import { COLORS } from '@/components/pixel';
import { photoUrl } from '@/lib/game';

// Shows a photo from the private "photos" bucket via a signed URL.
export function RemotePhoto({ path, style }: { path: string; style?: StyleProp<ViewStyle> }) {
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    setUrl(null);
    photoUrl(path)
      .then((u) => live && setUrl(u))
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [path]);

  return (
    <View style={[styles.box, style]}>
      {url ? (
        <Image source={{ uri: url }} style={StyleSheet.absoluteFill} contentFit="cover" />
      ) : (
        <ActivityIndicator color={COLORS.textDim} />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  box: {
    aspectRatio: 1,
    width: '100%',
    borderRadius: 6,
    borderWidth: 2,
    borderColor: COLORS.border,
    backgroundColor: COLORS.panelSoft,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
