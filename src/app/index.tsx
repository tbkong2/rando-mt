import { Image } from 'expo-image';
import { useEffect, useRef, useState } from 'react';
import { Dimensions, PanResponder, StyleSheet, Text, View } from 'react-native';

const AVATAR_SIZE = 40;
const JOYSTICK_SIZE = 104;
const THUMB_SIZE = 44;
const MAX_RADIUS = (JOYSTICK_SIZE - THUMB_SIZE) / 2;
const MOVE_SPEED = 3; // lower = slower/more controlled, higher = faster

type Arch = 'chill' | 'chaos' | 'sporty';

// RN can't do dynamic require(), so the scene art is mapped up front.
const LOBBY_BG: Record<Arch, number> = {
  chill: require('@/assets/lobbies/chill.png'),
  chaos: require('@/assets/lobbies/chaos.png'),
  sporty: require('@/assets/lobbies/sporty.png'),
};

// Walkable floor per archetype, as fractions of the frame (0 = left/top edge,
// 1 = right/bottom edge) — eyeballed against each PNG so the avatar stays
// clear of the counter/stage/bar and inside the walls.
type FloorRect = { x0: number; y0: number; x1: number; y1: number };
const FLOORS: Record<Arch, FloorRect> = {
  chill:  { x0: 0.10, y0: 0.34, x1: 0.90, y1: 0.86 },
  chaos:  { x0: 0.10, y0: 0.30, x1: 0.72, y1: 0.92 },
  sporty: { x0: 0.10, y0: 0.44, x1: 0.90, y1: 0.93 },
};
// 9:16 letterbox frame, sized to the screen and centred on the dark backdrop
// (mirrors rando's #lobby / #lobby-frame).
const screen = Dimensions.get('window');
const FRAME_HEIGHT = Math.min(screen.height, (screen.width * 16) / 9);
const FRAME_WIDTH = (FRAME_HEIGHT * 9) / 16;

export default function Index() {
  // No archetype selector yet — change this default to preview chaos / sporty.
  const [arch] = useState<Arch>('chill');
  // Spawn near the bottom-centre of the floor, like walking in through a door.
  const [position, setPosition] = useState(() => {
    const floor = FLOORS[arch];
    return {
      x: ((floor.x0 + floor.x1) / 2) * FRAME_WIDTH - AVATAR_SIZE / 2,
      y: floor.y1 * FRAME_HEIGHT - AVATAR_SIZE,
    };
  });
  const positionRef = useRef(position);
  const [thumbOffset, setThumbOffset] = useState({ x: 0, y: 0 });
  const directionRef = useRef({ x: 0, y: 0 }); // -1 to 1 on each axis
  const [visual, setVisual] = useState({ scale: 1, bob: 0 }); 
  // null = hidden. Set to the touch's frame-local {x, y} the moment a drag
  // starts in the bottom half; cleared again on release.
  const [joystickOrigin, setJoystickOrigin] = useState<{ x: number; y: number } | null>(null);
  const resetJoystick = () => {
    setThumbOffset({ x: 0, y: 0 });
    directionRef.current = { x: 0, y: 0 };
    setJoystickOrigin(null);
  };
  useEffect(() => {
    // Pixel bounds for this archetype's floor rect — the avatar's top-left
    // corner is clamped here so the whole 40x40 box stays inside the tiles.
    const floor = FLOORS[arch];
    const minX = floor.x0 * FRAME_WIDTH;
    const maxX = floor.x1 * FRAME_WIDTH - AVATAR_SIZE;
    const minY = floor.y0 * FRAME_HEIGHT;
    const maxY = floor.y1 * FRAME_HEIGHT - AVATAR_SIZE;

    const interval = setInterval(() => {
      const { x: dx, y: dy } = directionRef.current;
      const moving = dx !== 0 || dy !== 0;

      if (moving) {
        let newX = positionRef.current.x + dx * MOVE_SPEED;
        // 0.82: vertical steps read as "shorter" against the angled scene art,
        // giving a hint of depth instead of flat top-down movement.
        let newY = positionRef.current.y + dy * MOVE_SPEED * 0.82;
        newX = Math.max(minX, Math.min(newX, maxX));
        newY = Math.max(minY, Math.min(newY, maxY));

        const newPosition = { x: newX, y: newY };
        positionRef.current = newPosition;
        setPosition(newPosition);
      }

      // Depth: feet position as a fraction of the frame height, same formula
      // rando uses (0.72 + y*0.55) — taller near the bottom, smaller near the top.
      const feetY = (positionRef.current.y + AVATAR_SIZE) / FRAME_HEIGHT;
      const scale = 0.72 + feetY * 0.55;

      // Walk bob: a fast little sine wave, only while actually moving.
      const bob = moving ? Math.abs(Math.sin((Date.now() / 1000) * 9)) * AVATAR_SIZE * 0.16 : 0;

      setVisual({ scale, bob });
    }, 16);

    return () => clearInterval(interval);
  }, [arch]);
  const joystickPanResponder = useRef(
    PanResponder.create({
    // Only claim the gesture if it STARTS in the bottom half of the frame.
    // locationY is relative to the view the responder is attached to (the
    // full-frame touch layer in the JSX below), so no offset math needed.
    onStartShouldSetPanResponder: (evt) => evt.nativeEvent.locationY > FRAME_HEIGHT / 2,
    onPanResponderGrant: (evt) => {
      const { locationX, locationY } = evt.nativeEvent;
      setJoystickOrigin({ x: locationX, y: locationY });
    },
    onPanResponderMove: (_, gesture) => {
      // unchanged — dx/dy are already relative to wherever the touch started,
      // so dragging past the halfway line afterward is naturally allowed.
      let { dx, dy } = gesture;
      const distance = Math.sqrt(dx * dx + dy * dy);
      if (distance > MAX_RADIUS) {
        const angle = Math.atan2(dy, dx);
        dx = Math.cos(angle) * MAX_RADIUS;
        dy = Math.sin(angle) * MAX_RADIUS;
      }
      setThumbOffset({ x: dx, y: dy });
      directionRef.current = { x: dx / MAX_RADIUS, y: dy / MAX_RADIUS };
    },
    onPanResponderRelease: resetJoystick,
    onPanResponderTerminate: resetJoystick, // e.g. an incoming call interrupts the touch
  })
).current;

  return (
    <View style={styles.backdrop}>
      <View style={styles.frame}>
        {/* full-bleed pre-rendered scene */}
        <Image source={LOBBY_BG[arch]} style={StyleSheet.absoluteFill} contentFit="cover" />

        <Text style={styles.title}>{arch}</Text>

        {/* contact shadow — anchored at the feet, grows/shrinks with depth, never bobs */}
        <View
          style={[
            styles.avatarShadow,
            {
              left: position.x + AVATAR_SIZE / 2,
              top: position.y + AVATAR_SIZE,
              transform: [{ translateX: '-50%' }, { scaleX: visual.scale }, { scaleY: visual.scale }],
            },
          ]}
        />

        <View
          style={[
            styles.avatar,
            {
              top: position.y,
              left: position.x,
              transform: [{ scale: visual.scale }, { translateY: -visual.bob }],
            },
          ]}
        >
          <Text style={styles.avatarLabel}>YOU</Text>
        </View>

        {/* invisible layer covering the whole frame — decides whether a touch starts the joystick */}
        <View style={StyleSheet.absoluteFill} {...joystickPanResponder.panHandlers} />

        {/* joystick only exists while a touch is active */}
        {joystickOrigin && (
          <View
            pointerEvents="none"
            style={[
              styles.joystickBase,
              { left: joystickOrigin.x - JOYSTICK_SIZE / 2, top: joystickOrigin.y - JOYSTICK_SIZE / 2 },
            ]}
          >
            <View
              style={[
                styles.joystickThumb,
                { transform: [{ translateX: thumbOffset.x }, { translateY: thumbOffset.y }] },
              ]}
            />
          </View>
        )}
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
    top: 16,
    left: 14, // matches rando's #lobby-title — nothing else occupies this corner now
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
    width: JOYSTICK_SIZE,
    height: JOYSTICK_SIZE,
    borderRadius: JOYSTICK_SIZE / 2,
    backgroundColor: 'rgba(15,17,22,0.28)',
    borderWidth: 1.5,
    borderColor: 'rgba(255,255,255,0.35)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  joystickThumb: {
    width: THUMB_SIZE,
    height: THUMB_SIZE,
    borderRadius: THUMB_SIZE / 2,
    backgroundColor: 'rgba(255,255,255,0.82)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.4,
    shadowRadius: 10,
    elevation: 6, // Android shadow equivalent
  },
  avatarShadow: {
    position: 'absolute',
    width: AVATAR_SIZE * 0.8,
    height: AVATAR_SIZE * 0.28,
    borderRadius: AVATAR_SIZE, // large enough to stay elliptical at any size
    backgroundColor: 'rgba(10,14,20,0.28)', // same value rando uses
  },
});
