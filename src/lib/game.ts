// Client side of Caption It. Every game action is a Postgres function (see
// supabase/migrations/004_final_rules.sql); this file wraps them with types
// and makes sure the phone has an (anonymous) session before calling.
import AsyncStorage from '@react-native-async-storage/async-storage';
import { decode } from 'base64-arraybuffer';
import * as Linking from 'expo-linking';

import { supabase } from '@/lib/supabase';

export type Round = 'lobby' | 'upload' | 'caption' | 'vote' | 'results';

export type GamePlayer = {
  id: string;
  name: string;
  is_host: boolean;
  score: number;
  is_me: boolean;
  // finished the current round's task (null outside upload/caption/vote)
  done: boolean | null;
};

export type Assignment = {
  photo_id: string;
  path: string;
  my_caption: string | null;
};

export type MatchupCaption = {
  id: string;
  text: string;
  is_mine: boolean;
  // null until the matchup is revealed
  author: string | null;
  votes: number | null;
  points: number | null;
};

export type Matchup = {
  photo_id: string;
  path: string;
  number: number;
  total: number;
  phase: 'voting' | 'reveal';
  owner: string | null;
  my_vote: string | null;
  votes_in: number;
  captions: MatchupCaption[];
};

export type Placing = {
  id: string;
  name: string;
  score: number;
  place: number;
  is_me: boolean;
};

export type GameState = {
  room: { id: string; round: Round; version: number };
  me: { id: string; is_host: boolean };
  players: GamePlayer[];
  my_photo: string | null;
  assignments: Assignment[] | null;
  matchup: Matchup | null;
  results: Placing[] | null;
};

export const MIN_PLAYERS = 3;
export const MAX_PLAYERS = 8;
export const MAX_CAPTION = 80;
export const MAX_NAME = 16;

export async function ensureSignedIn() {
  const { data } = await supabase.auth.getSession();
  if (data.session) return;
  const { error } = await supabase.auth.signInAnonymously();
  if (error) throw new Error(error.message);
}

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  await ensureSignedIn();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export const createRoom = (name: string) => call<string>('create_room', { p_name: name });
export const joinRoom = (roomId: string, name: string) =>
  call<string>('join_room', { p_room: roomId, p_name: name });
export const leaveRoom = (roomId: string) => call<void>('leave_room', { p_room: roomId });
export const startGame = (roomId: string) => call<void>('start_game', { p_room: roomId });
export const submitCaption = (photoId: string, text: string) =>
  call<void>('submit_caption', { p_photo: photoId, p_text: text });
export const castVote = (captionId: string) => call<void>('cast_vote', { p_caption: captionId });
export const nextMatchup = (roomId: string) => call<void>('next_matchup', { p_room: roomId });
export const getGameState = (roomId: string) =>
  call<GameState>('get_game_state', { p_room: roomId });

const EXTENSIONS: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'image/heif': 'heif',
};

// Uploads the picked photo into the room's storage folder, then submits it.
export async function submitPhoto(
  roomId: string,
  photo: { base64: string; mimeType?: string | null }
) {
  await ensureSignedIn();
  const contentType = photo.mimeType ?? 'image/jpeg';
  const file = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  const path = `${roomId}/${file}.${EXTENSIONS[contentType] ?? 'jpg'}`;

  const { error } = await supabase.storage
    .from('photos')
    .upload(path, decode(photo.base64), { contentType });
  if (error) throw new Error(error.message);

  await call<void>('submit_photo', { p_room: roomId, p_path: path });
}

// Photos live in a private bucket, so they're shown through short-lived
// signed URLs. Cached so re-renders don't re-request them.
const signedUrls = new Map<string, Promise<string>>();

export function photoUrl(path: string): Promise<string> {
  let url = signedUrls.get(path);
  if (!url) {
    url = supabase.storage
      .from('photos')
      .createSignedUrl(path, 60 * 60)
      .then(({ data, error }) => {
        if (error || !data) {
          signedUrls.delete(path);
          throw new Error(error?.message ?? 'Could not load photo');
        }
        return data.signedUrl;
      });
    signedUrls.set(path, url);
  }
  return url;
}

// The QR code encodes a deep link. In Expo Go this is an exp://…/--/join/<id>
// URL, in a built app randomt://join/<id>; expo-router opens join/[roomId].
export const joinLink = (roomId: string) => Linking.createURL(`join/${roomId}`);

const ROOM_IN_LINK = /join\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;

export function roomIdFromLink(link: string): string | null {
  return link.match(ROOM_IN_LINK)?.[1] ?? null;
}

const NAME_KEY = 'caption-it.name';

export const loadName = async () => (await AsyncStorage.getItem(NAME_KEY)) ?? '';
export const saveName = (name: string) => AsyncStorage.setItem(NAME_KEY, name.trim());
