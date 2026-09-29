// Shared look for the lobby and Caption It: a 9:16 frame letterboxed on a dark
// backdrop, pixel-art scene behind, dark translucent panels and a yellow
// accent (rando's lobby chat colours).
import { Image } from 'expo-image';
import type { ReactNode } from 'react';
import {
  ActivityIndicator,
  Dimensions,
  Pressable,
  StyleSheet,
  Text,
  View,
  type StyleProp,
  type TextStyle,
  type ViewStyle,
} from 'react-native';

const screen = Dimensions.get('window');
export const FRAME_HEIGHT = Math.min(screen.height, (screen.width * 16) / 9);
export const FRAME_WIDTH = (FRAME_HEIGHT * 9) / 16;

export const COLORS = {
  backdrop: '#0b0d12',
  panel: 'rgba(15,17,22,0.78)',
  panelSoft: 'rgba(15,17,22,0.5)',
  border: 'rgba(255,255,255,0.22)',
  text: '#ffffff',
  textDim: 'rgba(255,255,255,0.62)',
  cream: '#f2ecdf',
  accent: '#ffd60a',
  accentInk: '#241d0a',
  danger: '#ff7a7a',
  good: '#8fe39a',
};

export const SCENES = {
  chill: require('@/assets/lobbies/chill.png'),
  chaos: require('@/assets/lobbies/chaos.png'),
  sporty: require('@/assets/lobbies/sporty.png'),
};

type FrameProps = {
  children: ReactNode;
  title?: string;
  // pixel scene behind the content; darkened so text stays readable
  scene?: number;
  dim?: number;
};

export function PixelFrame({ children, title, scene = SCENES.chill, dim = 0.62 }: FrameProps) {
  return (
    <View style={styles.backdrop}>
      <View style={styles.frame}>
        <Image source={scene} style={StyleSheet.absoluteFill} contentFit="cover" />
        <View style={[StyleSheet.absoluteFill, { backgroundColor: `rgba(11,13,18,${dim})` }]} />
        {title ? <Text style={styles.title}>{title}</Text> : null}
        <View style={styles.content}>{children}</View>
      </View>
    </View>
  );
}

export function PixelPanel({ children, style }: { children: ReactNode; style?: StyleProp<ViewStyle> }) {
  return <View style={[styles.panel, style]}>{children}</View>;
}

type ButtonProps = {
  label: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary';
  disabled?: boolean;
  busy?: boolean;
  style?: StyleProp<ViewStyle>;
};

export function PixelButton({ label, onPress, variant = 'primary', disabled, busy, style }: ButtonProps) {
  const primary = variant === 'primary';
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled || busy}
      style={({ pressed }) => [
        styles.button,
        primary ? styles.buttonPrimary : styles.buttonSecondary,
        (disabled || busy) && styles.buttonDisabled,
        pressed && styles.buttonPressed,
        style,
      ]}
    >
      {busy ? (
        <ActivityIndicator color={primary ? COLORS.accentInk : COLORS.text} />
      ) : (
        <Text style={[styles.buttonText, { color: primary ? COLORS.accentInk : COLORS.text }]}>
          {label}
        </Text>
      )}
    </Pressable>
  );
}

type TextProps = {
  children: ReactNode;
  kind?: 'heading' | 'body' | 'label' | 'dim';
  style?: StyleProp<TextStyle>;
  numberOfLines?: number;
};

export function PixelText({ children, kind = 'body', style, numberOfLines }: TextProps) {
  return (
    <Text numberOfLines={numberOfLines} style={[styles.text, textKinds[kind], style]}>
      {children}
    </Text>
  );
}

export function ErrorNote({ message }: { message: string | null }) {
  if (!message) return null;
  return <PixelText style={styles.error}>{message}</PixelText>;
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: COLORS.backdrop,
    alignItems: 'center',
    justifyContent: 'center',
  },
  frame: {
    width: FRAME_WIDTH,
    height: FRAME_HEIGHT,
    overflow: 'hidden',
  },
  title: {
    position: 'absolute',
    top: 16,
    left: 14,
    zIndex: 5,
    color: COLORS.text,
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
    textShadowColor: 'rgba(0,0,0,0.8)',
    textShadowOffset: { width: 0, height: 2 },
    textShadowRadius: 8,
  },
  content: {
    flex: 1,
    paddingTop: 44,
    paddingHorizontal: 14,
    paddingBottom: 16,
  },
  panel: {
    backgroundColor: COLORS.panel,
    borderWidth: 1.5,
    borderColor: COLORS.border,
    borderRadius: 6,
    padding: 12,
  },
  button: {
    minHeight: 46,
    borderRadius: 6,
    borderWidth: 2,
    paddingHorizontal: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonPrimary: {
    backgroundColor: COLORS.accent,
    borderColor: '#b89800',
  },
  buttonSecondary: {
    backgroundColor: COLORS.panel,
    borderColor: COLORS.border,
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  buttonPressed: {
    transform: [{ translateY: 2 }],
  },
  buttonText: {
    fontSize: 14,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  text: {
    color: COLORS.text,
  },
  error: {
    color: COLORS.danger,
    fontSize: 13,
    marginTop: 8,
  },
});

const textKinds = StyleSheet.create({
  heading: {
    fontSize: 20,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  body: {
    fontSize: 15,
    lineHeight: 21,
  },
  label: {
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
    color: COLORS.textDim,
  },
  dim: {
    fontSize: 13,
    color: COLORS.textDim,
  },
});
