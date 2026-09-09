import { useEffect, useRef, useState } from 'react';
import { Dimensions, PanResponder, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

const AVATAR_SIZE = 40;
const ROOM_MARGIN = 16;
const BORDER_WIDTH = 6;
const JOYSTICK_SIZE = 100;
const THUMB_SIZE = 40;
const MAX_RADIUS = (JOYSTICK_SIZE - THUMB_SIZE) / 2;
const MOVE_SPEED = 3; // lower = slower/more controlled, higher = faster



export default function Index() {
  const screen = Dimensions.get('window');
  const roomWidth = screen.width - ROOM_MARGIN * 2 - BORDER_WIDTH * 2;
  const roomHeight = screen.height - ROOM_MARGIN * 2 - BORDER_WIDTH * 2;
  const [position, setPosition] = useState({ x: 150, y: 200 });
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
      newX = Math.max(0, Math.min(newX, roomWidth - AVATAR_SIZE));
      newY = Math.max(0, Math.min(newY, roomHeight - AVATAR_SIZE));

      const newPosition = { x: newX, y: newY };
      positionRef.current = newPosition;
      setPosition(newPosition);
    }, 16);

    return () => clearInterval(interval);
  }, [roomWidth, roomHeight]);

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
    <View style={styles.room}>
      <Text style={styles.roomLabel}>LOBBY</Text>
      <View style={styles.floor} />

      {/* Avatar no longer has panHandlers - it's just a visual now */}
      <View style={[styles.avatar, { top: position.y, left: position.x }]}>
        <Text style={styles.avatarLabel}>YOU</Text>
      </View>

     
      {/* NEW: small toggle button, top corner */}
      <TouchableOpacity
        style={styles.toggleButton}
        onPress={() => setJoystickSide((prev) => (prev === 'right' ? 'left' : 'right'))}
      >
        <Text style={styles.toggleButtonText}>⇄</Text>
      </TouchableOpacity>

      {/* Joystick position now depends on joystickSide */}
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
  );
}

const styles = StyleSheet.create({
  room: {
    flex: 1,
    backgroundColor: '#3a2f4a',
    margin: ROOM_MARGIN,
    borderWidth: BORDER_WIDTH,
    borderColor: '#f0c674',
    position: 'relative',
    overflow: 'hidden',
  },
  roomLabel: {
    color: '#f0c674',
    fontSize: 18,
    fontWeight: 'bold',
    letterSpacing: 2,
    textAlign: 'center',
    marginTop: 16,
    fontFamily: 'monospace',
  },
  floor: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: '35%',
    backgroundColor: '#5c4a6e',
    borderTopWidth: 4,
    borderTopColor: '#f0c674',
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