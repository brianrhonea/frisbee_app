"use client";
// The user's voice connection, like Discord's and the app's VoiceRepository:
// one channel at a time, kept up across pages until they disconnect. It
// lives in the root layout, so moving around the site doesn't drop it.
// Leaving the team, losing access to the room, the room being deleted or
// signing out disconnects.
import type { VoiceTokenResult } from "@stall10/shared";
import { doc, getDocFromServer, onSnapshot } from "firebase/firestore";
import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { firestoreDb } from "@/lib/firebase";
import { useAuth } from "../AuthProvider";
import { type CallEnd, CallSession, type CallState, useCall } from "../team/meetings/call";
import { canPickSpeaker, loadSettings, saveSettings } from "../team/meetings/settings";

/** The voice channel the user is in (VoiceChannel). */
export interface VoiceChannel {
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
export const lostAccessNotice = "You no longer have access to this channel.";

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
  const [channel, setChannel] = useState<VoiceChannel | null>(null);
  const [call, setCall] = useState<CallSession | null>(null);
  const state = useCall(call);
  const [connecting, setConnecting] = useState(false);
  const [canSpeak, setCanSpeak] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [volumes, setVolumes] = useState<Record<string, number>>({});
  const callRef = useRef<CallSession | null>(null);
  const channelRef = useRef<VoiceChannel | null>(null);
  // Bumped on every join and leave, so a slow join that's been replaced hangs up instead of taking over.
  const attempt = useRef(0);

  const hangUp = useCallback(async () => {
    const c = callRef.current;
    callRef.current = null;
    setCall(null);
    setCanSpeak(false);
    await c?.leave();
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
      try {
        const access = await callApi<VoiceTokenResult>(
          user,
          `/v1/teams/${encodeURIComponent(next.teamId)}/voice-rooms/${encodeURIComponent(next.roomId)}/token`,
          { method: "POST" },
        );
        if (mine !== attempt.current) return;
        const settings = loadSettings();
        setVolumes(settings.participantVolumes);
        // Listeners join muted and are never asked for the mic.
        const c = await CallSession.connect({
          url: access.url,
          token: access.token,
          micOn: access.canSpeak,
          cameraOn: false,
          audioInputId: settings.audioInputId,
          audioOutputId: canPickSpeaker() ? settings.audioOutputId : null,
          volumes: { output: settings.outputVolume, people: settings.participantVolumes },
        });
        if (mine !== attempt.current) {
          await c.leave();
          return;
        }
        callRef.current = c;
        setCall(c);
        setCanSpeak(access.canSpeak);
      } catch (e) {
        if (mine !== attempt.current) return;
        channelRef.current = null;
        setChannel(null);
        setError(e instanceof ApiError ? e.message : "Couldn't connect to the channel. Check your connection and try again.");
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
  const uid = user?.uid ?? null;
  const lastUid = useRef(uid);
  useEffect(() => {
    if (lastUid.current !== uid && channelRef.current) void drop(null);
    lastUid.current = uid;
  }, [uid, drop]);

  // While in a channel, watch its room and its team. Whether the room can
  // be read depends on the team (membership, roles), so: leaving the team
  // or the team going drops the call, and any other change to the team
  // re-checks the room with the server. A deleted room closes the channel.
  // A passing network error doesn't disconnect; LiveKit reconnects.
  const teamId = channel?.teamId;
  const roomId = channel?.roomId;
  useEffect(() => {
    const db = firestoreDb();
    if (!db || !teamId || !roomId || !uid) return;
    const roomRef = doc(db, `teams/${teamId}/chats/${roomId}`);
    const denied = (e: unknown) => (e as { code?: string })?.code === "permission-denied";
    const stopRoom = onSnapshot(
      roomRef,
      (snap) => {
        if (!snap.exists() && !snap.metadata.fromCache) void drop(dropNotices.meetingEnded);
      },
      (e) => {
        if (denied(e)) void drop(lostAccessNotice);
      },
    );
    let first = true;
    const stopTeam = onSnapshot(
      doc(db, `teams/${teamId}`),
      (snap) => {
        if (snap.metadata.fromCache) return;
        const memberIds = (snap.data()?.memberIds as string[] | undefined) ?? [];
        if (!snap.exists() || !memberIds.includes(uid)) {
          void drop(lostAccessNotice);
          return;
        }
        if (first) {
          first = false;
          return;
        }
        // Roles or room access may have changed.
        getDocFromServer(roomRef).then(
          (r) => {
            if (!r.exists()) void drop(dropNotices.meetingEnded);
          },
          (e) => {
            if (denied(e)) void drop(lostAccessNotice);
          },
        );
      },
      (e) => {
        if (denied(e)) void drop(lostAccessNotice);
      },
    );
    return () => {
      stopRoom();
      stopTeam();
    };
  }, [teamId, roomId, uid, drop]);

  // Closing the tab hangs up.
  useEffect(
    () => () => {
      attempt.current += 1;
      void callRef.current?.leave();
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
    (uid: string, v: number) => {
      call?.setVolume(uid, v);
      setVolumes((cur) => {
        const next = { ...cur, [uid]: v };
        const s = loadSettings();
        saveSettings({ ...s, participantVolumes: { ...s.participantVolumes, [uid]: v } });
        return next;
      });
    },
    [call],
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
