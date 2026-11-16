"use client";
// The user's voice connection, like Discord's and the app's VoiceRepository:
// one channel at a time, kept up across pages until they disconnect. It
// lives in the root layout, so moving around the site doesn't drop it.
// Leaving the team, losing access to the room, the room being deleted or
// signing out disconnects; losing the right to talk there mutes the mic.
import { voiceDecision, type VoiceRoomDoc, type VoiceTeam, type VoiceTokenResult } from "@stall10/shared";
import { type DocumentReference, type DocumentSnapshot, doc, onSnapshot } from "firebase/firestore";
import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { firestoreDb } from "@/lib/firebase";
import { useAuth } from "../AuthProvider";
import { type CallEnd, CallCancelled, CallSession, type CallState, useCall } from "../team/meetings/call";
import { canPickSpeaker, loadSettings, present, updateSettings, withPersonVolume } from "../team/meetings/settings";

/** The voice channel the user is in (VoiceChannel). */
interface VoiceChannel {
  teamId: string;
  roomId: string;
  name: string;
  teamName: string;
}

/** Why the call dropped on its own (VoiceRepositoryLiveKit._onCall). */
const dropNotices: Record<CallEnd, string> = {
  removed: "You joined this channel somewhere else.",
  connectionLost: "Lost the connection to voice.",
  meetingEnded: "The voice channel closed.",
};
const lostAccessNotice = "You no longer have access to this channel.";

const denied = (e: unknown) => (e as { code?: string })?.code === "permission-denied";

/**
 * onSnapshot that keeps watching: permission-denied goes to [onDenied];
 * any other error (offline, a backend hiccup) resubscribes after a
 * backoff of 1 s doubling to 30 s, reset by the next snapshot.
 */
function watchDoc(ref: DocumentReference, onData: (snap: DocumentSnapshot) => void, onDenied: () => void): () => void {
  let stop: (() => void) | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let failures = 0;
  let closed = false;
  const start = () => {
    timer = null;
    if (closed) return;
    // Metadata changes too, so a cached doc still reports once the server confirms it.
    stop = onSnapshot(
      ref,
      { includeMetadataChanges: true },
      (snap) => {
        failures = 0;
        onData(snap);
      },
      (e) => {
        stop = null;
        if (closed) return;
        if (denied(e)) {
          onDenied();
          return;
        }
        timer = setTimeout(start, Math.min(30_000, 1000 * 2 ** failures++));
      },
    );
  };
  start();
  return () => {
    closed = true;
    if (timer) clearTimeout(timer);
    stop?.();
  };
}

export interface Voice {
  /** The channel joined or being joined; null when disconnected. */
  channel: VoiceChannel | null;
  call: CallSession | null;
  state: CallState;
  connecting: boolean;
  connected: boolean;
  /** False when the user can only listen in [channel]. */
  canSpeak: boolean;
  micOn: boolean;
  /** Why the call dropped on its own, until the next join. */
  notice: string | null;
  /** Why the last join failed. */
  error: string | null;
  /** How loud each person plays here, 0–2. */
  volumes: Record<string, number>;
  isIn: (teamId: string, roomId: string) => boolean;
  /** Joins [channel], leaving any other first; nothing if already in it. */
  join: (channel: VoiceChannel) => Promise<void>;
  leave: () => Promise<void>;
  setMic: (on: boolean) => Promise<void>;
  setVolume: (uid: string, volume: number) => void;
}

const VoiceContext = createContext<Voice | null>(null);

export function useVoice(): Voice {
  const v = useContext(VoiceContext);
  if (!v) throw new Error("useVoice outside VoiceProvider");
  return v;
}

export function VoiceProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const uid = user?.uid ?? null;
  const [channel, setChannel] = useState<VoiceChannel | null>(null);
  const [call, setCall] = useState<CallSession | null>(null);
  const state = useCall(call);
  const [connecting, setConnecting] = useState(false);
  // What the token allows (fixed for the call), and what the team and room allow now.
  const [tokenCanSpeak, setTokenCanSpeak] = useState(false);
  const [allowedToSpeak, setAllowedToSpeak] = useState(true);
  const allowedRef = useRef(true);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [volumes, setVolumes] = useState<Record<string, number>>({});
  const callRef = useRef<CallSession | null>(null);
  // The call being joined, from the moment it exists, so dropping mid-join
  // (or while the browser asks for the mic) still disconnects it.
  const joiningRef = useRef<CallSession | null>(null);
  const channelRef = useRef<VoiceChannel | null>(null);
  // Bumped on every join and leave, so a slow join that's been replaced hangs up instead of taking over.
  const attempt = useRef(0);

  const hangUp = useCallback(async () => {
    const c = callRef.current;
    const joining = joiningRef.current;
    callRef.current = null;
    joiningRef.current = null;
    setCall(null);
    setTokenCanSpeak(false);
    await Promise.all([c?.leave(), joining?.leave()]);
  }, []);

  const drop = useCallback(
    async (why: string | null) => {
      attempt.current += 1;
      channelRef.current = null;
      setChannel(null);
      setConnecting(false);
      setNotice(why);
      await hangUp();
    },
    [hangUp],
  );

  const join = useCallback(
    async (next: VoiceChannel) => {
      if (!user) return;
      const cur = channelRef.current;
      if (cur && cur.teamId === next.teamId && cur.roomId === next.roomId) return;
      // Bumped before hanging up, so a join still in flight can't take over meanwhile.
      const mine = ++attempt.current;
      await hangUp();
      if (mine !== attempt.current) return;
      channelRef.current = next;
      setChannel(next);
      setConnecting(true);
      setNotice(null);
      setError(null);
      allowedRef.current = true;
      setAllowedToSpeak(true);
      let session: CallSession | null = null;
      try {
        const access = await callApi<VoiceTokenResult>(
          user,
          `/v1/teams/${encodeURIComponent(next.teamId)}/voice-rooms/${encodeURIComponent(next.roomId)}/token`,
          { method: "POST" },
        );
        if (mine !== attempt.current) return;
        const settings = loadSettings(user.uid);
        setVolumes(settings.participantVolumes);
        // Saved devices only while they're still plugged in; otherwise the system default.
        const speakerOk = canPickSpeaker();
        const [mics, speakers] = await Promise.all([
          CallSession.devices("audioinput"),
          speakerOk ? CallSession.devices("audiooutput") : Promise.resolve([] as MediaDeviceInfo[]),
        ]);
        if (mine !== attempt.current) return;
        // Listeners join muted and are never asked for the mic.
        const c = await CallSession.connect({
          url: access.url,
          token: access.token,
          micOn: access.canSpeak && allowedRef.current,
          cameraOn: false,
          audioInputId: present(settings.audioInputId, mics),
          audioOutputId: speakerOk ? present(settings.audioOutputId, speakers) : null,
          volumes: { output: settings.outputVolume, people: settings.participantVolumes },
          onSession: (s) => {
            session = s;
            if (mine === attempt.current) joiningRef.current = s;
            else void s.leave();
          },
        });
        if (joiningRef.current === c) joiningRef.current = null;
        if (mine !== attempt.current) {
          await c.leave();
          return;
        }
        callRef.current = c;
        setCall(c);
        setTokenCanSpeak(access.canSpeak);
      } catch (e) {
        if (joiningRef.current === session) joiningRef.current = null;
        void (session as CallSession | null)?.leave();
        if (mine !== attempt.current || e instanceof CallCancelled) return;
        channelRef.current = null;
        setChannel(null);
        setError(problem(e, "Couldn't connect to the channel. Check your connection and try again."));
      } finally {
        if (mine === attempt.current) setConnecting(false);
      }
    },
    [user, hangUp],
  );

  const leave = useCallback(() => drop(null), [drop]);

  // The call dropped on its own.
  useEffect(() => {
    if (state.ended) void drop(dropNotices[state.ended]);
  }, [state.ended, drop]);

  // Signing out, or another account signing in, disconnects.
  const lastUid = useRef(uid);
  useEffect(() => {
    if (lastUid.current !== uid && channelRef.current) void drop(null);
    lastUid.current = uid;
  }, [uid, drop]);

  // While in a channel, watch its room and its team, and decide as the API
  // does when it hands out the token (voiceDecision): leaving the team, the
  // team going or losing read access drops the call; a deleted room closes
  // it; losing write access mutes the mic and keeps the user listening.
  // Cached snapshots don't count. A passing network error doesn't
  // disconnect (LiveKit reconnects) and the watch resubscribes.
  const teamId = channel?.teamId;
  const roomId = channel?.roomId;
  useEffect(() => {
    const db = firestoreDb();
    if (!db || !teamId || !roomId || !uid) return;
    let team: VoiceTeam | null | undefined;
    let room: VoiceRoomDoc | null | undefined;
    const check = () => {
      if (team === undefined || room === undefined) return;
      const d = voiceDecision(team ?? undefined, room ?? undefined, uid);
      if (!d.ok) {
        void drop(d.code === "not-found" ? dropNotices.meetingEnded : lostAccessNotice);
        return;
      }
      allowedRef.current = d.canSpeak;
      setAllowedToSpeak(d.canSpeak);
    };
    const lost = () => void drop(lostAccessNotice);
    const stopRoom = watchDoc(
      doc(db, `teams/${teamId}/chats/${roomId}`),
      (snap) => {
        if (snap.metadata.fromCache) return;
        room = snap.exists() ? (snap.data() as VoiceRoomDoc) : null;
        check();
      },
      lost,
    );
    const stopTeam = watchDoc(
      doc(db, `teams/${teamId}`),
      (snap) => {
        if (snap.metadata.fromCache) return;
        team = snap.exists() ? (snap.data() as VoiceTeam) : null;
        check();
      },
      lost,
    );
    return () => {
      stopRoom();
      stopTeam();
    };
  }, [teamId, roomId, uid, drop]);

  // A listener token can't be upgraded mid-call, so talking needs both.
  const canSpeak = !!call && tokenCanSpeak && allowedToSpeak;
  // Lost the right to talk mid-call (or before the mic came on): stop sending it.
  useEffect(() => {
    if (call && !canSpeak && state.micOn) void call.setMic(false);
  }, [call, canSpeak, state.micOn]);

  // Closing the tab hangs up.
  useEffect(
    () => () => {
      attempt.current += 1;
      void callRef.current?.leave();
      void joiningRef.current?.leave();
    },
    [],
  );

  const setMic = useCallback(
    async (on: boolean) => {
      if (!call || (on && !canSpeak)) return;
      await call.setMic(on);
    },
    [call, canSpeak],
  );

  const setVolume = useCallback(
    (who: string, v: number) => {
      call?.setVolume(who, v);
      // Read-merge-write on the saved copy, outside a state updater (which may run twice).
      setVolumes(updateSettings(uid, (s) => withPersonVolume(s, who, v)).participantVolumes);
    },
    [call, uid],
  );

  const value = useMemo<Voice>(
    () => ({
      channel,
      call,
      state,
      connecting,
      connected: !!call && state.connected,
      canSpeak,
      micOn: !!call && state.micOn,
      notice,
      error,
      volumes,
      isIn: (t, r) => channel?.teamId === t && channel?.roomId === r,
      join,
      leave,
      setMic,
      setVolume,
    }),
    [channel, call, state, connecting, canSpeak, notice, error, volumes, join, leave, setMic, setVolume],
  );

  return <VoiceContext.Provider value={value}>{children}</VoiceContext.Provider>;
}
