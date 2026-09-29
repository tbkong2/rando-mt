import { Image } from 'expo-image';
import * as ImagePicker from 'expo-image-picker';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';

import { COLORS, ErrorNote, PixelButton, PixelFrame, PixelPanel, PixelText } from '@/components/pixel';
import { PlayerList } from '@/components/player-list';
import { RemotePhoto } from '@/components/remote-photo';
import { useGameState } from '@/hooks/use-game-state';
import {
  castVote,
  MAX_CAPTION,
  nextMatchup,
  submitCaption,
  submitPhoto,
  type GameState,
  type MatchupCaption,
  type Round,
} from '@/lib/game';

const ROUND_TITLE: Record<Round, string> = {
  lobby: 'Lobby',
  upload: 'Round 1 · Upload',
  caption: 'Round 2 · Caption',
  vote: 'Round 3 · Vote',
  results: 'Round 4 · Results',
};

type RoundProps = { state: GameState; roomId: string; refresh: () => Promise<void> };

export default function CaptionIt() {
  const { roomId } = useLocalSearchParams<{ roomId: string }>();
  const { state, error, refresh } = useGameState(roomId);
  const round = state?.room.round;

  useEffect(() => {
    if (round === 'lobby') {
      router.replace({ pathname: '/lobby/[roomId]', params: { roomId } });
    }
  }, [round, roomId]);

  if (!state) {
    return (
      <PixelFrame title="Caption It">
        <View style={styles.center}>
          {error ? (
            <PixelPanel style={styles.gap}>
              <ErrorNote message={error} />
              <PixelButton label="Home" variant="secondary" onPress={() => router.replace('/')} />
            </PixelPanel>
          ) : (
            <ActivityIndicator color={COLORS.accent} size="large" />
          )}
        </View>
      </PixelFrame>
    );
  }

  const props = { state, roomId, refresh };
  return (
    <PixelFrame title={`Caption It · ${ROUND_TITLE[state.room.round]}`}>
      <ScrollView
        contentContainerStyle={styles.scroll}
        keyboardShouldPersistTaps="handled"
        automaticallyAdjustKeyboardInsets
      >
        {state.room.round === 'upload' && <UploadRound {...props} />}
        {state.room.round === 'caption' && <CaptionRound {...props} />}
        {state.room.round === 'vote' && <VoteRound {...props} />}
        {state.room.round === 'results' && <Results {...props} />}
      </ScrollView>
    </PixelFrame>
  );
}

function Waiting({ title, note, state }: { title: string; note: string; state: GameState }) {
  return (
    <PixelPanel style={styles.gap}>
      <PixelText kind="heading">{title}</PixelText>
      <PixelText kind="dim">{note}</PixelText>
      <PlayerList players={state.players} showDone />
    </PixelPanel>
  );
}

// ---------------------------------------------------------------------------
// Round 1: every player submits one photo
// ---------------------------------------------------------------------------
function UploadRound({ state, roomId, refresh }: RoundProps) {
  const [picked, setPicked] = useState<ImagePicker.ImagePickerAsset | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (state.my_photo) {
    return (
      <View style={styles.gap}>
        <RemotePhoto path={state.my_photo} style={styles.smallPhoto} />
        <Waiting title="Photo in!" note="Waiting for everyone else's photo…" state={state} />
      </View>
    );
  }

  async function pick() {
    setError(null);
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.6,
      base64: true,
    });
    if (!result.canceled) setPicked(result.assets[0]);
  }

  async function submit() {
    if (!picked?.base64) {
      setError('Could not read that photo, try another one.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await submitPhoto(roomId, { base64: picked.base64, mimeType: picked.mimeType });
      await refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={styles.gap}>
      <PixelText kind="heading">Pick a photo</PixelText>
      <PixelText kind="dim">
        One photo from your camera roll. Two other players will write captions for it.
      </PixelText>
      <Pressable onPress={pick} style={styles.photoSlot}>
        {picked ? (
          <Image source={{ uri: picked.uri }} style={StyleSheet.absoluteFill} contentFit="cover" />
        ) : (
          <PixelText kind="label">Tap to choose</PixelText>
        )}
      </Pressable>
      {picked ? (
        <>
          <PixelButton label="Submit photo" onPress={submit} busy={busy} />
          <PixelButton label="Choose another" variant="secondary" onPress={pick} disabled={busy} />
        </>
      ) : (
        <PixelButton label="Choose photo" onPress={pick} />
      )}
      <ErrorNote message={error} />
    </View>
  );
}

// ---------------------------------------------------------------------------
// Round 2: caption the two photos assigned to you, one at a time
// ---------------------------------------------------------------------------
function CaptionRound({ state, refresh }: RoundProps) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const assignments = state.assignments ?? [];
  const current = assignments.find((a) => !a.my_caption);

  if (!current) {
    return (
      <Waiting
        title="Captions in!"
        note="Waiting for everyone to finish writing…"
        state={state}
      />
    );
  }

  async function submit() {
    if (!current) return;
    setBusy(true);
    setError(null);
    try {
      await submitCaption(current.photo_id, text.trim());
      setText('');
      await refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const index = assignments.indexOf(current) + 1;
  return (
    <View style={styles.gap}>
      <PixelText kind="label">
        Caption {index} of {assignments.length}
      </PixelText>
      <RemotePhoto key={current.photo_id} path={current.path} style={styles.mediumPhoto} />
      <TextInput
        value={text}
        onChangeText={setText}
        placeholder="Write something funny…"
        placeholderTextColor={COLORS.textDim}
        maxLength={MAX_CAPTION}
        multiline
        style={styles.captionInput}
      />
      <PixelText kind="dim" style={styles.counter}>
        {text.length}/{MAX_CAPTION} · another player is captioning this photo too
      </PixelText>
      <PixelButton label="Submit caption" onPress={submit} disabled={!text.trim()} busy={busy} />
      <ErrorNote message={error} />
    </View>
  );
}

// ---------------------------------------------------------------------------
// Round 3: one photo at a time, pick the better caption, then the reveal
// ---------------------------------------------------------------------------
function VoteRound({ state, roomId, refresh }: RoundProps) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const m = state.matchup;
  if (!m) return null;

  const revealed = m.phase === 'reveal';
  const [a, b] = m.captions;
  const isLast = m.number === m.total;

  async function vote(caption: MatchupCaption) {
    setBusy(true);
    setError(null);
    try {
      await castVote(caption.id);
      await refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function next() {
    setBusy(true);
    setError(null);
    try {
      await nextMatchup(roomId);
      await refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  function outcome(caption: MatchupCaption, other: MatchupCaption) {
    if (!revealed) return null;
    if (caption.votes === other.votes) return 'TIE';
    return (caption.votes ?? 0) > (other.votes ?? 0) ? 'WINNER' : null;
  }

  return (
    <View style={styles.gap}>
      <PixelText kind="label">
        Photo {m.number} of {m.total}
        {revealed && m.owner ? ` · by ${m.owner}` : ''}
      </PixelText>
      <RemotePhoto key={m.photo_id} path={m.path} style={styles.mediumPhoto} />

      {[a, b].map((caption, i) => {
        const other = i === 0 ? b : a;
        const chosen = m.my_vote === caption.id;
        const badge = outcome(caption, other);
        return (
          <Pressable
            key={caption.id}
            onPress={() => vote(caption)}
            disabled={revealed || !!m.my_vote || busy}
            style={[
              styles.captionCard,
              chosen && styles.captionChosen,
              !revealed && m.my_vote && !chosen && styles.captionFaded,
              badge === 'WINNER' && styles.captionWinner,
            ]}
          >
            <PixelText style={styles.captionText}>“{caption.text}”</PixelText>
            {revealed ? (
              <View style={styles.captionMeta}>
                <PixelText kind="label">
                  {caption.author} · {caption.votes} vote{caption.votes === 1 ? '' : 's'}
                </PixelText>
                <PixelText style={styles.points}>
                  +{formatPoints(caption.points ?? 0)}
                  {badge ? `  ${badge}` : ''}
                </PixelText>
              </View>
            ) : (
              <PixelText kind="label">
                {[chosen ? 'your vote' : m.my_vote ? null : 'tap to vote', caption.is_mine ? 'your caption' : null]
                  .filter(Boolean)
                  .join(' · ')}
              </PixelText>
            )}
          </Pressable>
        );
      })}

      {!revealed && m.my_vote && (
        <PixelText kind="dim" style={styles.centerText}>
          Waiting for votes… {m.votes_in}/{state.players.length}
        </PixelText>
      )}
      {revealed &&
        (state.me.is_host ? (
          <PixelButton label={isLast ? 'See results' : 'Next photo'} onPress={next} busy={busy} />
        ) : (
          <PixelText kind="dim" style={styles.centerText}>
            Waiting for the host…
          </PixelText>
        ))}
      <ErrorNote message={error} />
    </View>
  );
}

// ---------------------------------------------------------------------------
// Round 4: final ranking; equal totals share a place
// ---------------------------------------------------------------------------
function Results({ state }: RoundProps) {
  const results = state.results ?? [];
  return (
    <View style={styles.gap}>
      <PixelText kind="heading">Final scores</PixelText>
      <PixelPanel style={styles.resultList}>
        {results.map((r) => (
          <View key={r.id} style={[styles.resultRow, r.is_me && styles.resultMe]}>
            <PixelText style={[styles.place, r.place === 1 && styles.firstPlace]}>
              {ordinal(r.place)}
            </PixelText>
            <PixelText style={styles.resultName} numberOfLines={1}>
              {r.name}
            </PixelText>
            <PixelText style={styles.resultScore}>{formatPoints(r.score)}</PixelText>
          </View>
        ))}
      </PixelPanel>
      <PixelButton label="Home" variant="secondary" onPress={() => router.replace('/')} />
    </View>
  );
}

function formatPoints(n: number) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function ordinal(n: number) {
  const tens = n % 100;
  if (tens >= 11 && tens <= 13) return `${n}th`;
  return `${n}${['th', 'st', 'nd', 'rd'][n % 10] ?? 'th'}`;
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    justifyContent: 'center',
  },
  scroll: {
    flexGrow: 1,
    justifyContent: 'center',
    paddingVertical: 8,
  },
  gap: {
    gap: 12,
  },
  centerText: {
    textAlign: 'center',
  },
  smallPhoto: {
    width: '55%',
    alignSelf: 'center',
  },
  mediumPhoto: {
    width: '78%',
    alignSelf: 'center',
  },
  photoSlot: {
    aspectRatio: 1,
    width: '85%',
    alignSelf: 'center',
    borderRadius: 6,
    borderWidth: 2,
    borderStyle: 'dashed',
    borderColor: 'rgba(255,255,255,0.4)',
    backgroundColor: COLORS.panelSoft,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  captionInput: {
    minHeight: 64,
    color: COLORS.text,
    fontSize: 16,
    padding: 12,
    borderRadius: 6,
    borderWidth: 1.5,
    borderColor: COLORS.border,
    backgroundColor: COLORS.panel,
    textAlignVertical: 'top',
  },
  counter: {
    fontSize: 12,
  },
  captionCard: {
    padding: 12,
    gap: 6,
    borderRadius: 6,
    borderWidth: 2,
    borderColor: COLORS.border,
    backgroundColor: COLORS.panel,
  },
  captionChosen: {
    borderColor: COLORS.accent,
  },
  captionFaded: {
    opacity: 0.55,
  },
  captionWinner: {
    borderColor: COLORS.accent,
    backgroundColor: 'rgba(255,214,10,0.14)',
  },
  captionText: {
    color: COLORS.cream,
    fontSize: 17,
    fontWeight: '600',
  },
  captionMeta: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  points: {
    color: COLORS.accent,
    fontWeight: '800',
  },
  resultList: {
    gap: 4,
  },
  resultRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    paddingHorizontal: 6,
    borderRadius: 4,
  },
  resultMe: {
    backgroundColor: 'rgba(255,214,10,0.12)',
  },
  place: {
    width: 44,
    fontWeight: '800',
    color: COLORS.textDim,
  },
  firstPlace: {
    color: COLORS.accent,
  },
  resultName: {
    flex: 1,
    fontWeight: '700',
  },
  resultScore: {
    fontWeight: '800',
    color: COLORS.cream,
  },
});
