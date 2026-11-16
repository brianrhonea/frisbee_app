"use client";
import type { VideoTrack } from "livekit-client";
import { useEffect, useRef } from "react";
import { Avatar } from "../../Avatar";
import type { CallPerson, CallSession } from "./call";
import { maxPersonVolume } from "./settings";
import "./devices.css";

/** A camera or screen, attached while shown. [mirror] flips the user's own camera. */
export function VideoView({ track, mirror = false, contain = false }: { track: VideoTrack; mirror?: boolean; contain?: boolean }) {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    track.attach(el);
    return () => {
      track.detach(el);
    };
  }, [track]);
  return <video ref={ref} className={`call-video${mirror ? " mirror" : ""}${contain ? " contain" : ""}`} autoPlay playsInline muted />;
}

/** One person: their camera, or their photo and name; a ring while they talk. */
function PersonTile({ person }: { person: CallPerson }) {
  return (
    <div className={`call-tile${person.speaking ? " speaking" : ""}`}>
      {person.camera ? (
        <VideoView track={person.camera} mirror={person.isLocal} />
      ) : (
        <div className="call-tile-face">
          <Avatar name={person.name} url={person.photoUrl ?? undefined} size={64} />
        </div>
      )}
      <span className="call-tile-name">
        {person.isLocal ? `${person.name} (you)` : person.name}
        {!person.micOn && <span aria-label="muted"> · muted</span>}
      </span>
    </div>
  );
}

/** Everyone in the call; the first shared screen shown large (screenShare). */
export function CallStage({ people }: { people: CallPerson[] }) {
  const sharer = people.find((p) => p.screen);
  return (
    <div className={`call-stage${sharer ? " sharing" : ""}`}>
      {sharer?.screen && (
        <div className="call-screen">
          <VideoView track={sharer.screen} contain />
          <span className="call-tile-name">{sharer.isLocal ? "You're sharing your screen" : `${sharer.name}'s screen`}</span>
        </div>
      )}
      <div className="call-grid">
        {people.map((p) => (
          <PersonTile key={p.uid + (p.isLocal ? ":me" : "")} person={p} />
        ))}
      </div>
    </div>
  );
}

/**
 * The list of who's in, with a volume for each other person
 * (participantVolumes): 0 to 200%, relative to the call's volume.
 * [onVolume] applies it to the call and remembers it.
 */
export function PeopleList({ people, volumes, onVolume }: { call?: CallSession; people: CallPerson[]; volumes: Record<string, number>; onVolume: (uid: string, v: number) => void }) {
  return (
    <ul className="call-people">
      {people.map((p) => {
        const v = volumes[p.uid] ?? 1;
        return (
          <li key={p.uid + (p.isLocal ? ":me" : "")}>
            <span className={p.speaking ? "speaking" : ""}>
              {p.name}
              {p.isLocal ? " (you)" : ""}
              {!p.micOn ? " · muted" : ""}
            </span>
            {!p.isLocal && (
              <label className="call-volume">
                <span className="visually-hidden">Volume for {p.name}</span>
                <input type="range" min={0} max={maxPersonVolume} step={0.05} value={v} onChange={(e) => onVolume(p.uid, Number(e.target.value))} />
                <small className="muted">{Math.round(v * 100)}%</small>
              </label>
            )}
          </li>
        );
      })}
    </ul>
  );
}
