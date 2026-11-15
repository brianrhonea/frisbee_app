"use client";
import { useCallback, useEffect, useState } from "react";
import { CallSession } from "./call";
import { canPickSpeaker, type MeetingSettings, present } from "./settings";

export type DeviceKind = "audioinput" | "videoinput" | "audiooutput";
type DeviceLists = Record<DeviceKind, MediaDeviceInfo[]>;
const none: DeviceLists = { audioinput: [], videoinput: [], audiooutput: [] };

const idKey = { audioinput: "audioInputId", videoinput: "videoInputId", audiooutput: "audioOutputId" } as const;

/** The saved device for [kind] if it's still plugged in, else null (the system default). */
export function selectedDevice(settings: MeetingSettings, devices: DeviceLists, kind: DeviceKind): string | null {
  return present(settings[idKey[kind]], devices[kind]);
}

/** Settings with [kind]'s device set to [id] ("" or null for the system default). */
export function withDevice(settings: MeetingSettings, kind: DeviceKind, id: string | null): MeetingSettings {
  return { ...settings, [idKey[kind]]: id || null };
}

/**
 * The browser's mics, cameras and speakers, kept up to date as devices
 * come and go. [reload] after the browser allows a device, when names
 * appear.
 */
export function useDevices(): { devices: DeviceLists; reload: () => void; speaker: boolean } {
  const [devices, setDevices] = useState<DeviceLists>(none);
  const [speaker, setSpeaker] = useState(false);
  const reload = useCallback(() => {
    void Promise.all([CallSession.devices("audioinput"), CallSession.devices("videoinput"), CallSession.devices("audiooutput")]).then(
      ([audioinput, videoinput, audiooutput]) => setDevices({ audioinput, videoinput, audiooutput }),
      () => undefined,
    );
  }, []);
  useEffect(() => {
    setSpeaker(canPickSpeaker());
    reload();
    const md = typeof navigator !== "undefined" ? navigator.mediaDevices : undefined;
    md?.addEventListener?.("devicechange", reload);
    return () => md?.removeEventListener?.("devicechange", reload);
  }, [reload]);
  return { devices, reload, speaker };
}

const labels: Record<DeviceKind, string> = { audioinput: "Microphone", videoinput: "Camera", audiooutput: "Speaker" };

/**
 * Mic, camera and speaker pickers plus the meeting volume (DeviceSettings),
 * in the lobby and from the call. The speaker picker shows only where the
 * browser can switch the output.
 */
export function DeviceSettings({
  settings,
  devices,
  speaker,
  onDevice,
  onOutputVolume,
}: {
  settings: MeetingSettings;
  devices: DeviceLists;
  speaker: boolean;
  onDevice: (kind: DeviceKind, id: string | null) => void;
  onOutputVolume: (v: number) => void;
}) {
  const kinds: DeviceKind[] = speaker ? ["audioinput", "videoinput", "audiooutput"] : ["audioinput", "videoinput"];
  return (
    <div className="device-settings">
      {kinds.map((kind) => {
        const list = devices[kind];
        return (
          <label key={kind} className="device-pick">
            <span>{labels[kind]}</span>
            <select value={selectedDevice(settings, devices, kind) ?? ""} onChange={(e) => onDevice(kind, e.target.value || null)}>
              <option value="">System default</option>
              {list.map((d, i) => (
                <option key={d.deviceId} value={d.deviceId}>
                  {d.label || `${labels[kind]} ${i + 1}`}
                </option>
              ))}
            </select>
          </label>
        );
      })}
      <label className="device-pick">
        <span>Meeting volume</span>
        <span className="device-volume">
          <input type="range" min={0} max={1} step={0.05} value={settings.outputVolume} onChange={(e) => onOutputVolume(Number(e.target.value))} />
          <small className="muted">{Math.round(settings.outputVolume * 100)}%</small>
        </span>
      </label>
      <p className="muted small">Only changes what you hear. Set how loud each person is for you in People.</p>
    </div>
  );
}
