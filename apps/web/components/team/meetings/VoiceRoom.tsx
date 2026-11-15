"use client";
import type { VoiceTokenResult } from "@stall10/shared";
import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../../AuthProvider";
import { CallSession, endNotices, useCall } from "./call";
import { PeopleList } from "./CallTiles";
import "./meetings.css";

/**
 * A voice channel (VoiceChannelView): always open, like Discord's. Members
 * who can read the room listen; those who can write in it talk too, and
 * only they are asked for the microphone. On the website the call lasts
 * while this room is open (the app keeps it up across the app).
 */
export function VoiceRoom({ teamId, roomId, name, canSpeak }: { teamId: string; roomId: string; name: string; canSpeak: boolean }) {
  const { user } = useAuth();
  const [call, setCall] = useState<CallSession | null>(null);
  const state = useCall(call);
  const [joining, setJoining] = useState(false);
  const [speak, setSpeak] = useState(canSpeak);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [volumes, setVolumes] = useState<Record<string, number>>({});
  const ref = useRef<CallSession | null>(null);
  // Bumped on leaving, a room switch and unmount: a connect that finishes after is dropped.
  const generation = useRef(0);

  const leave = useCallback(async (why: string | null) => {
    generation.current += 1;
    const c = ref.current;
    ref.current = null;
    setCall(null);
    setNotice(why);
    await c?.leave();
  }, []);

  // Another room, or another page: this call ends.
  useEffect(
    () => () => {
      generation.current += 1;
      void ref.current?.leave();
    },
    [],
  );
  useEffect(() => {
    void leave(null);
    setNotice(null);
    setError(null);
  }, [teamId, roomId, leave]);
  useEffect(() => {
    if (state.ended) void leave(state.ended === "meetingEnded" ? "The channel closed." : endNotices[state.ended]);
  }, [state.ended, leave]);

  async function join() {
    if (!user) return;
    setJoining(true);
    setError(null);
    setNotice(null);
    const mine = ++generation.current;
    try {
      const access = await callApi<VoiceTokenResult>(user, `/v1/teams/${encodeURIComponent(teamId)}/voice-rooms/${encodeURIComponent(roomId)}/token`, { method: "POST" });
      if (mine !== generation.current) return;
      setSpeak(access.canSpeak);
      // Listeners join muted and are never asked for the mic.
      const c = await CallSession.connect({ url: access.url, token: access.token, micOn: access.canSpeak, cameraOn: false });
      if (mine !== generation.current) {
        await c.leave();
        return;
      }
      ref.current = c;
      setCall(c);
    } catch (e) {
      if (mine !== generation.current) return;
      setError(e instanceof ApiError ? e.message : "Couldn't connect to the channel. Check your connection and try again.");
    } finally {
      setJoining(false);
    }
  }

  return (
    <div className="card voice-room">
      <header className="thread-head">
        <h2>🔊 {name}</h2>
        {call && state.connected && <span className="meeting-badge live">Connected</span>}
      </header>
      {!call ? (
        <>
          <p className="muted">{canSpeak ? "Drop in to talk with whoever's here." : "You can listen in this channel but not talk."}</p>
          {notice && <p>{notice}</p>}
          <div className="home-actions">
            <button type="button" className="btn btn-primary" disabled={joining} onClick={() => void join()}>
              {joining ? "Joining…" : "Join voice"}
            </button>
          </div>
        </>
      ) : (
        <>
          {state.audioBlocked && (
            <button type="button" className="btn btn-small btn-primary" onClick={() => void call.startAudio()}>
              Click to hear everyone
            </button>
          )}
          <PeopleList call={call} people={state.people} volumes={volumes} onVolume={(uid, v) => setVolumes({ ...volumes, [uid]: v })} />
          {state.notice && (
            <p className="form-error" role="alert">
              {state.notice}
            </p>
          )}
          <div className="home-actions">
            {speak ? (
              <button type="button" className="btn btn-small" aria-pressed={state.micOn} onClick={() => void call.setMic(!state.micOn)}>
                {state.micOn ? "Mute" : "Unmute"}
              </button>
            ) : (
              <span className="muted small">Listening only</span>
            )}
            <button type="button" className="btn btn-small" onClick={() => void leave(null)}>
              Disconnect
            </button>
          </div>
        </>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
