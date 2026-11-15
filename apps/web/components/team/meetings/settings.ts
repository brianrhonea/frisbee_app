"use client";
// The user's meeting and voice settings on this browser (MeetingSettings in
// the app): whether the mic and camera start on, the mic, camera and
// speaker picked, how loud the call plays and how loud each person plays.
// Saved in localStorage under the lobby's old key, which held only
// micOn / cameraOn, so old saves still load.

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

const key = "stall10.meetingPrefs";
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

export function loadSettings(): MeetingSettings {
  try {
    return parseSettings(localStorage.getItem(key));
  } catch {
    return { ...defaultSettings };
  }
}

/** Best effort: a failure only means it isn't remembered. */
export function saveSettings(s: MeetingSettings) {
  try {
    localStorage.setItem(key, JSON.stringify(s));
  } catch {
    // Not remembered.
  }
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
