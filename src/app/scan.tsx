import { CameraView, useCameraPermissions } from 'expo-camera';
import { router } from 'expo-router';
import { useRef, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { PixelButton, PixelFrame, PixelPanel, PixelText } from '@/components/pixel';
import { roomIdFromLink } from '@/lib/game';

export default function Scan() {
  const [permission, requestPermission] = useCameraPermissions();
  const [message, setMessage] = useState<string | null>(null);
  // the camera reports the same code many times a second; act on it once
  const handled = useRef(false);

  function onScanned({ data }: { data: string }) {
    if (handled.current) return;
    const roomId = roomIdFromLink(data);
    if (!roomId) {
      setMessage("That QR code isn't a Caption It room.");
      return;
    }
    handled.current = true;
    router.replace({ pathname: '/join/[roomId]', params: { roomId } });
  }

  return (
    <PixelFrame title="Join a room">
      <View style={styles.body}>
        {!permission ? null : permission.granted ? (
          <View style={styles.cameraBox}>
            <CameraView
              style={StyleSheet.absoluteFill}
              facing="back"
              barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
              onBarcodeScanned={onScanned}
            />
          </View>
        ) : (
          <PixelPanel style={styles.panel}>
            <PixelText>The camera is needed to scan the host's QR code.</PixelText>
            <PixelButton label="Allow camera" onPress={requestPermission} />
          </PixelPanel>
        )}

        <PixelText kind="dim" style={styles.hint}>
          {message ?? "Point your camera at the QR code on the host's phone."}
        </PixelText>
        <PixelButton label="Back" variant="secondary" onPress={() => router.back()} />
      </View>
    </PixelFrame>
  );
}

const styles = StyleSheet.create({
  body: {
    flex: 1,
    justifyContent: 'center',
    gap: 16,
  },
  cameraBox: {
    aspectRatio: 1,
    width: '100%',
    borderRadius: 8,
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.35)',
    overflow: 'hidden',
  },
  panel: {
    gap: 12,
  },
  hint: {
    textAlign: 'center',
  },
});
