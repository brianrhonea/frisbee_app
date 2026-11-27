"use client";
import { useVoice } from "../../voice/VoiceProvider";
import { useTeamHub } from "../TeamContext";
import { PeopleList } from "./CallTiles";
import "./meetings.css";
import { ErrorNote } from "@/components/StatusViews";

/**
 * A voice channel (VoiceChannelView): always open, like Discord's. Members
 * who can read the room listen; those who can write in it talk too, and
 * only they are asked for the microphone. The call itself lives in the
 * site-wide VoiceProvider, so it stays up while the user moves around the
 * site, and the voice bar shows it on every page.
 */
export function VoiceRoom({ teamId, roomId, name, canSpeak }: { teamId: string; roomId: string; name: string; canSpeak: boolean }) {
  const voice = useVoice();
  const hub = useTeamHub();
  const here = voice.isIn(teamId, roomId);
  const call = here ? voice.call : null;
  const state = voice.state;
  const elsewhere = here ? null : voice.channel;
  const speak = here ? voice.canSpeak : canSpeak;

  return (
    <div className="card voice-room">
      <header className="thread-head">
        <h2>🔊 {name}</h2>
        {call && state.connected && <span className="meeting-badge live">Connected</span>}
      </header>
      {!call ? (
        <>
          <p className="muted">{canSpeak ? "Drop in to talk with whoever's here." : "You can listen in this channel but not talk."}</p>
          {!voice.channel && voice.notice && <p>{voice.notice}</p>}
          <div className="home-actions">
            <button
              type="button"
              className="btn btn-primary"
              disabled={here && voice.connecting}
              onClick={() => void voice.join({ teamId, roomId, name, teamName: hub.name })}
            >
              {here && voice.connecting ? "Joining…" : "Join voice"}
            </button>
          </div>
          {elsewhere && !voice.connecting && (
            <p className="muted small">
              This leaves {elsewhere.name}
              {elsewhere.teamName ? ` in ${elsewhere.teamName}` : ""}.
            </p>
          )}
        </>
      ) : (
        <>
          {state.audioBlocked && (
            <button type="button" className="btn btn-small btn-primary" onClick={() => void call.startAudio()}>
              Click to hear everyone
            </button>
          )}
          <PeopleList call={call} people={state.people} volumes={voice.volumes} onVolume={voice.setVolume} />
          {state.notice && (
            <ErrorNote>
              {state.notice}
            </ErrorNote>
          )}
          <div className="home-actions">
            {speak ? (
              <button type="button" className="btn btn-small" aria-pressed={!state.micOn} onClick={() => void voice.setMic(!state.micOn)}>
                {state.micOn ? "Mute" : "Unmute"}
              </button>
            ) : (
              <span className="muted small">You can only listen here</span>
            )}
            <button type="button" className="btn btn-small" onClick={() => void voice.leave()}>
              Disconnect
            </button>
          </div>
        </>
      )}
      {voice.error && !voice.channel && (
        <ErrorNote>
          {voice.error}
        </ErrorNote>
      )}
    </div>
  );
}
