import { Image } from 'expo-image';
import { useEffect, useRef, useState } from 'react';
import { Dimensions, PanResponder, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

const AVATAR_SIZE = 40;
const JOYSTICK_SIZE = 100;
const THUMB_SIZE = 40;
const MAX_RADIUS = (JOYSTICK_SIZE - THUMB_SIZE) / 2;
const MOVE_SPEED = 3; // lower = slower/more controlled, higher = faster

type Arch = 'chill' | 'chaos' | 'sporty';

// RN can't do dynamic require(), so the scene art is mapped up front.
const LOBBY_BG: Record<Arch, number> = {
  chill: require('@/assets/lobbies/chill.png'),
  chaos: require('@/assets/lobbies/chaos.png'),
  sporty: require('@/assets/lobbies/sporty.png'),
};

// 9:16 letterbox frame, sized to the screen and centred on the dark backdrop
// (mirrors rando's #lobby / #lobby-frame).
const screen = Dimensions.get('window');
const FRAME_HEIGHT = Math.min(screen.height, (screen.width * 16) / 9);
const FRAME_WIDTH = (FRAME_HEIGHT * 9) / 16;

export default function Index() {
  // No archetype selector yet — change this default to preview chaos / sporty.
  const [arch] = useState<Arch>('chill');
  const [position, setPosition] = useState({
    x: FRAME_WIDTH / 2 - AVATAR_SIZE / 2,
    y: FRAME_HEIGHT / 2,
  });
  const positionRef = useRef(position);
  const [thumbOffset, setThumbOffset] = useState({ x: 0, y: 0 });
  const directionRef = useRef({ x: 0, y: 0 }); // -1 to 1 on each axis

  const [joystickSide, setJoystickSide] = useState<'left' | 'right'>('right');

  useEffect(() => {
    const interval = setInterval(() => {
      const { x: dx, y: dy } = directionRef.current;
      if (dx === 0 && dy === 0) return;

      let newX = positionRef.current.x + dx * MOVE_SPEED;
      let newY = positionRef.current.y + dy * MOVE_SPEED;
      newX = Math.max(0, Math.min(newX, FRAME_WIDTH - AVATAR_SIZE));
      newY = Math.max(0, Math.min(newY, FRAME_HEIGHT - AVATAR_SIZE));

      const newPosition = { x: newX, y: newY };
      positionRef.current = newPosition;
      setPosition(newPosition);
    }, 16);

    return () => clearInterval(interval);
  }, []);

  const joystickPanResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onPanResponderMove: (_, gesture) => {
        let { dx, dy } = gesture;

        // Keep the thumb inside the joystick's circular base
        const distance = Math.sqrt(dx * dx + dy * dy);
        if (distance > MAX_RADIUS) {
          const angle = Math.atan2(dy, dx);
          dx = Math.cos(angle) * MAX_RADIUS;
          dy = Math.sin(angle) * MAX_RADIUS;
        }

        setThumbOffset({ x: dx, y: dy });
        directionRef.current = { x: dx / MAX_RADIUS, y: dy / MAX_RADIUS };
      },
      onPanResponderRelease: () => {
        setThumbOffset({ x: 0, y: 0 });
        directionRef.current = { x: 0, y: 0 };
      },
    })
  ).current;

  return (
    <View style={styles.backdrop}>
      <View style={styles.frame}>
        {/* full-bleed pre-rendered scene */}
        <Image source={LOBBY_BG[arch]} style={StyleSheet.absoluteFill} contentFit="cover" />

        <Text style={styles.title}>{arch}</Text>

        {/* Avatar is just a visual placeholder for now (styled in a later step) */}
        <View style={[styles.avatar, { top: position.y, left: position.x }]}>
          <Text style={styles.avatarLabel}>YOU</Text>
        </View>

        {/* small toggle button, top corner */}
        <TouchableOpacity
          style={styles.toggleButton}
          onPress={() => setJoystickSide((prev) => (prev === 'right' ? 'left' : 'right'))}
        >
          <Text style={styles.toggleButtonText}>⇄</Text>
        </TouchableOpacity>

        {/* Joystick position depends on joystickSide */}
        <View
          style={[
            styles.joystickBase,
            joystickSide === 'right' ? styles.joystickRight : styles.joystickLeft,
          ]}
          {...joystickPanResponder.panHandlers}
        >
          <View
            style={[
              styles.joystickThumb,
              { transform: [{ translateX: thumbOffset.x }, { translateY: thumbOffset.y }] },
            ]}
          />
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: '#0b0d12',
    alignItems: 'center',
    justifyContent: 'center',
  },
  frame: {
    width: FRAME_WIDTH,
    height: FRAME_HEIGHT,
    position: 'relative',
    overflow: 'hidden',
  },
  title: {
    position: 'absolute',
    top: 22,
    left: 60, // clear of the toggle button until the HUD is restyled
    zIndex: 5,
    color: '#fff',
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
    textShadowColor: 'rgba(0,0,0,0.8)',
    textShadowOffset: { width: 0, height: 2 },
    textShadowRadius: 8,
  },
  avatar: {
    position: 'absolute',
    width: AVATAR_SIZE,
    height: AVATAR_SIZE,
    backgroundColor: '#ef233c',
    borderWidth: 3,
    borderColor: '#1a1a1a',
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarLabel: {
    color: 'white',
    fontSize: 8,
    fontWeight: 'bold',
    fontFamily: 'monospace',
  },
  joystickBase: {
    position: 'absolute',
    bottom: 30,
    width: JOYSTICK_SIZE,
    height: JOYSTICK_SIZE,
    borderRadius: JOYSTICK_SIZE / 2,
    backgroundColor: 'rgba(255,255,255,0.15)',
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.4)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  joystickLeft: {
    left: 30,
  },
  joystickRight: {
    right: 30,
  },
  joystickThumb: {
    width: THUMB_SIZE,
    height: THUMB_SIZE,
    borderRadius: THUMB_SIZE / 2,
    backgroundColor: '#f0c674',
    borderWidth: 2,
    borderColor: '#1a1a1a',
  },
  toggleButton: {
    position: 'absolute',
    top: 16,
    left: 16,
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.15)',
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.4)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  toggleButtonText: {
    color: '#f0c674',
    fontSize: 18,
    fontWeight: 'bold',
  },
});
