"use client";
// One LiveKit call (a meeting's or a voice channel's), as the app's
// MeetingCallLivekit: who's in it, the local mic, camera and screen, and
// why it ended. livekit-client is large, so it's imported only when
// someone joins. React reads it through subscribe/snapshot (useCall).
import type { Participant, RemoteTrack, Room, Track, VideoTrack } from "livekit-client";
import { useSyncExternalStore } from "react";

/** One person in the call, as last seen (CallParticipant). */
export interface CallPerson {
  uid: string;
  name: string;
  photoUrl: string | null;
  isLocal: boolean;
  speaking: boolean;
  micOn: boolean;
  camera: VideoTrack | null;
  screen: VideoTrack | null;
}

/** Why the call ended without the user leaving (CallEndReason). */
export type CallEnd = "meetingEnded" | "removed" | "connectionLost";

export const endNotices: Record<CallEnd, string> = {
  meetingEnded: "The meeting has ended.",
  removed: "You were removed from the meeting.",
  connectionLost: "You lost your connection.",
};

export interface CallState {
  connected: boolean;
  people: CallPerson[];
  micOn: boolean;
  cameraOn: boolean;
  screenSharing: boolean;
  /** The browser won't play sound until the user clicks (autoplay rules). */
  audioBlocked: boolean;
  /** A plain note about the mic, camera or screen, e.g. permission refused. */
  notice: string | null;
  ended: CallEnd | null;
}

const idle: CallState = {
  connected: false,
  people: [],
  micOn: false,
  cameraOn: false,
  screenSharing: false,
  audioBlocked: false,
  notice: null,
  ended: null,
};

/** What a refused getUserMedia / getDisplayMedia means, in plain words. */
export function deviceProblem(e: unknown, device: "microphone" | "camera" | "screen"): string {
  const name = (e as { name?: string })?.name;
  if (name === "NotAllowedError" || name === "SecurityError") {
    return device === "screen"
      ? "Screen sharing was cancelled or blocked."
      : `Your browser blocked the ${device}. Allow it for this site (the icon by the address bar), then turn it on again.`;
  }
  if (name === "NotFoundError" || name === "OverconstrainedError") return `No ${device} found.`;
  if (name === "NotReadableError") return `Your ${device} is in use by another app.`;
  return `Couldn't turn on the ${device}.`;
}

function photoOf(metadata: string | undefined): string | null {
  if (!metadata) return null;
  try {
    const m = JSON.parse(metadata) as { photoUrl?: unknown };
    return typeof m.photoUrl === "string" ? m.photoUrl : null;
  } catch {
    return null;
  }
}

type LK = typeof import("livekit-client");

export class CallSession {
  private state: CallState = idle;
  private listeners = new Set<() => void>();
  private audio = new Map<string, HTMLMediaElement[]>();
  private left = false;

  private constructor(
    private readonly lk: LK,
    readonly room: Room,
  ) {}

  /**
   * Connects with [token], then turns on the mic and camera asked for.
   * The browser asks for them here, on joining, never before; a refusal
   * leaves that device off with a note, not a failed join.
   */
  static async connect(a: { url: string; token: string; micOn: boolean; cameraOn: boolean; audioInputId?: string; videoInputId?: string }) {
    const lk = await import("livekit-client");
    const room = new lk.Room({
      adaptiveStream: true,
      dynacast: true,
      audioCaptureDefaults: a.audioInputId ? { deviceId: a.audioInputId } : undefined,
      videoCaptureDefaults: a.videoInputId ? { deviceId: a.videoInputId } : undefined,
    });
    const call = new CallSession(lk, room);
    call.listen();
    await room.connect(a.url, a.token);
    call.refresh();
    if (a.micOn) await call.setMic(true);
    if (a.cameraOn) await call.setCamera(true);
    return call;
  }

  private listen() {
    const { RoomEvent, DisconnectReason, Track } = this.lk;
    const r = this.room;
    const update = () => this.refresh();
    for (const ev of [
      RoomEvent.ParticipantConnected,
      RoomEvent.ParticipantDisconnected,
      RoomEvent.TrackPublished,
      RoomEvent.TrackUnpublished,
      RoomEvent.TrackMuted,
      RoomEvent.TrackUnmuted,
      RoomEvent.LocalTrackPublished,
      RoomEvent.LocalTrackUnpublished,
      RoomEvent.ActiveSpeakersChanged,
      RoomEvent.ParticipantMetadataChanged,
      RoomEvent.ParticipantNameChanged,
      RoomEvent.Reconnected,
    ]) {
      r.on(ev, update);
    }
    r.on(RoomEvent.TrackSubscribed, (track: RemoteTrack, _pub, p: Participant) => {
      if (track.kind === Track.Kind.Audio) {
        const el = track.attach();
        el.hidden = true;
        document.body.appendChild(el);
        const key = `${p.identity}:${track.sid}`;
        this.audio.set(key, [...(this.audio.get(key) ?? []), el]);
      }
      update();
    });
    r.on(RoomEvent.TrackUnsubscribed, (track: RemoteTrack, _pub, p: Participant) => {
      if (track.kind === Track.Kind.Audio) {
        track.detach().forEach((el) => el.remove());
        this.audio.delete(`${p.identity}:${track.sid}`);
      }
      update();
    });
    r.on(RoomEvent.AudioPlaybackStatusChanged, update);
    r.on(RoomEvent.Disconnected, (reason?: number) => {
      if (this.left) return;
      const ended: CallEnd =
        reason === DisconnectReason.ROOM_DELETED || reason === DisconnectReason.SERVER_SHUTDOWN
          ? "meetingEnded"
          : reason === DisconnectReason.PARTICIPANT_REMOVED || reason === DisconnectReason.DUPLICATE_IDENTITY
            ? "removed"
            : "connectionLost";
      this.dropAudio();
      this.set({ ...this.state, connected: false, ended });
    });
  }

  private person(p: Participant, isLocal: boolean): CallPerson {
    const { Track } = this.lk;
    const video = (source: Track.Source) => {
      const pub = p.getTrackPublication(source);
      return pub && !pub.isMuted && pub.track ? (pub.track as VideoTrack) : null;
    };
    return {
      uid: p.identity,
      name: p.name || "Member",
      photoUrl: photoOf(p.metadata),
      isLocal,
      speaking: p.isSpeaking,
      micOn: p.isMicrophoneEnabled,
      camera: video(Track.Source.Camera),
      screen: video(Track.Source.ScreenShare),
    };
  }

  private refresh() {
    const r = this.room;
    const lp = r.localParticipant;
    this.set({
      ...this.state,
      connected: r.state === this.lk.ConnectionState.Connected || r.state === this.lk.ConnectionState.Reconnecting,
      // The user first, then everyone else in join order.
      people: [this.person(lp, true), ...[...r.remoteParticipants.values()].map((p) => this.person(p, false))],
      micOn: lp.isMicrophoneEnabled,
      cameraOn: lp.isCameraEnabled,
      screenSharing: lp.isScreenShareEnabled,
      audioBlocked: !r.canPlaybackAudio,
    });
  }

  private set(s: CallState) {
    this.state = s;
    for (const l of this.listeners) l();
  }

  subscribe = (l: () => void) => {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  };
  snapshot = () => this.state;

  private async device(kind: "microphone" | "camera" | "screen", fn: () => Promise<unknown>) {
    try {
      await fn();
      this.set({ ...this.state, notice: null });
    } catch (e) {
      this.set({ ...this.state, notice: deviceProblem(e, kind) });
    }
    this.refresh();
  }

  setMic(on: boolean) {
    return this.device("microphone", () => this.room.localParticipant.setMicrophoneEnabled(on));
  }
  setCamera(on: boolean) {
    return this.device("camera", () => this.room.localParticipant.setCameraEnabled(on));
  }
  setScreen(on: boolean) {
    return this.device("screen", () => this.room.localParticipant.setScreenShareEnabled(on, { audio: true }));
  }

  /** How loud [uid] plays here: 0 silent, 1 as sent (the app goes to 2). */
  setVolume(uid: string, volume: number) {
    this.room.remoteParticipants.get(uid)?.setVolume(volume);
  }

  /** After a click, when the browser held sound back. */
  async startAudio() {
    await this.room.startAudio().catch(() => undefined);
    this.refresh();
  }

  async devices(kind: MediaDeviceKind) {
    return this.lk.Room.getLocalDevices(kind, false).catch(() => [] as MediaDeviceInfo[]);
  }

  async useDevice(kind: MediaDeviceKind, id: string) {
    await this.room.switchActiveDevice(kind, id).catch(() => undefined);
  }

  private dropAudio() {
    for (const els of this.audio.values()) els.forEach((el) => el.remove());
    this.audio.clear();
  }

  /** Leaves; stops the mic, camera and screen. Safe to call twice. */
  async leave() {
    if (this.left) return;
    this.left = true;
    this.dropAudio();
    await this.room.disconnect(true).catch(() => undefined);
    this.set({ ...this.state, connected: false });
  }
}

const noSubscribe = () => () => undefined;
const idleSnapshot = () => idle;

/** The call's state for rendering; idle with no call. */
export function useCall(call: CallSession | null): CallState {
  return useSyncExternalStore(call?.subscribe ?? noSubscribe, call?.snapshot ?? idleSnapshot, idleSnapshot);
}
