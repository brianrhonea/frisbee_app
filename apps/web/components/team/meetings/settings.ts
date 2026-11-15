"use client";
// The user's meeting and voice settings on this browser (MeetingSettings in
// the app): whether the mic and camera start on, the mic, camera and
// speaker picked, how loud the call plays and how loud each person plays.
// Saved in localStorage per account ("stall10.meetingPrefs.<uid>"), so
// signing out or switching accounts doesn't carry them over. The lobby's
// old shared key is moved to the first account that loads it, without its
// per-person volumes, and removed.

export interface MeetingSettings {
  micOn: boolean;
  cameraOn: boolean;
  audioInputId: string | null;
  audioOutputId: string | null;
  videoInputId: string | null;
  /** How loud everyone plays, 0–1. */
  outputVolume: number;
  /** uid → how loud that person plays relative to [outputVolume], 0–2. */
  participantVolumes: Record<string, number>;
}

export const defaultSettings: MeetingSettings = {
  micOn: true,
  cameraOn: false,
  audioInputId: null,
  audioOutputId: null,
  videoInputId: null,
  outputVolume: 1,
  participantVolumes: {},
};

/** The most a person can be turned up, as in the app. */
export const maxPersonVolume = 2;

/** The most per-person volumes remembered; the oldest set are dropped first. */
export const maxPersonVolumes = 200;

const legacyKey = "stall10.meetingPrefs";
const keyFor = (uid: string) => `${legacyKey}.${uid}`;
const clamp = (v: unknown, max: number, fallback: number) => (typeof v === "number" && Number.isFinite(v) ? Math.min(max, Math.max(0, v)) : fallback);
const id = (v: unknown) => (typeof v === "string" && v ? v : null);

export function parseSettings(raw: string | null): MeetingSettings {
  try {
    const p = JSON.parse(raw ?? "{}") as Record<string, unknown>;
    const volumes: Record<string, number> = {};
    if (p.participantVolumes && typeof p.participantVolumes === "object") {
      for (const [uid, v] of Object.entries(p.participantVolumes as Record<string, unknown>)) {
        if (typeof v === "number" && Number.isFinite(v)) volumes[uid] = clamp(v, maxPersonVolume, 1);
      }
    }
    return {
      micOn: p.micOn !== false,
      cameraOn: p.cameraOn === true,
      audioInputId: id(p.audioInputId),
      audioOutputId: id(p.audioOutputId),
      videoInputId: id(p.videoInputId),
      outputVolume: clamp(p.outputVolume, 1, 1),
      participantVolumes: volumes,
    };
  } catch {
    return { ...defaultSettings };
  }
}

/** Keeps the newest [maxPersonVolumes] entries (insertion order is oldest first). */
function capVolumes(volumes: Record<string, number>): Record<string, number> {
  const entries = Object.entries(volumes);
  return entries.length <= maxPersonVolumes ? volumes : Object.fromEntries(entries.slice(entries.length - maxPersonVolumes));
}

/** [uid]'s settings on this browser; the defaults when signed out. */
export function loadSettings(uid: string | null | undefined): MeetingSettings {
  if (!uid) return { ...defaultSettings };
  try {
    const raw = localStorage.getItem(keyFor(uid));
    if (raw !== null) return parseSettings(raw);
    const old = localStorage.getItem(legacyKey);
    if (old === null) return { ...defaultSettings };
    // The old shared save: keep its toggles and devices, not whose volume was changed.
    const migrated = { ...parseSettings(old), participantVolumes: {} };
    localStorage.removeItem(legacyKey);
    saveSettings(uid, migrated);
    return migrated;
  } catch {
    return { ...defaultSettings };
  }
}

/** Best effort: a failure only means it isn't remembered. */
export function saveSettings(uid: string | null | undefined, s: MeetingSettings) {
  if (!uid) return;
  try {
    localStorage.setItem(keyFor(uid), JSON.stringify({ ...s, participantVolumes: capVolumes(s.participantVolumes) }));
  } catch {
    // Not remembered.
  }
}

/**
 * Reads [uid]'s saved settings, applies [fn] and saves the result, which
 * it returns: one read-merge-write, so the meeting room and the voice
 * channel (or two tabs) don't overwrite each other's changes. Call it
 * outside React state updaters, which may run twice.
 */
export function updateSettings(uid: string | null | undefined, fn: (s: MeetingSettings) => MeetingSettings): MeetingSettings {
  const next = fn(loadSettings(uid));
  const capped = { ...next, participantVolumes: capVolumes(next.participantVolumes) };
  saveSettings(uid, capped);
  return capped;
}

/** Settings with [uid] played at [volume], moved to the newest end so the cap drops others first. */
export function withPersonVolume(s: MeetingSettings, uid: string, volume: number): MeetingSettings {
  const rest = { ...s.participantVolumes };
  delete rest[uid];
  return { ...s, participantVolumes: { ...rest, [uid]: Math.min(maxPersonVolume, Math.max(0, volume)) } };
}

/**
 * Whether this browser can pick the speaker. Calls mix sound through Web
 * Audio (so a person can go above 100%), and LiveKit then switches the
 * output on the AudioContext, so both it and media elements need
 * setSinkId. Safari has neither; Firefox lacks the AudioContext one.
 */
export function canPickSpeaker(): boolean {
  if (typeof window === "undefined") return false;
  const ua = navigator.userAgent;
  const safari = /safari/i.test(ua) && !/chrome|chromium|crios|edg|firefox|fxios/i.test(ua);
  return (
    !safari &&
    typeof HTMLMediaElement !== "undefined" &&
    "setSinkId" in HTMLMediaElement.prototype &&
    typeof AudioContext !== "undefined" &&
    "setSinkId" in AudioContext.prototype
  );
}

/** A saved device id, if that device is still plugged in; otherwise null (the system default). */
export function present(id: string | null, devices: MediaDeviceInfo[]): string | null {
  return id && devices.some((d) => d.deviceId === id) ? id : null;
}
