"use client";
import Link from "next/link";
import { useVoice } from "./VoiceProvider";
import "./voice.css";

/**
 * The voice channel the user is in, on every page (the app's voice bar
 * under the room list): its status, the channel and team, mute and
 * disconnect. The name opens the channel.
 */
export function VoiceBar() {
  const v = useVoice();
  const channel = v.channel;
  if (!channel) return null;
  const href = `/teams/${encodeURIComponent(channel.teamId)}/chat?room=${encodeURIComponent(channel.roomId)}`;
  const where = [channel.name, channel.teamName].filter(Boolean).join(" / ");
  return (
    <section className={`voice-bar${v.connected ? " on" : ""}`} aria-label="Voice">
      <span className="voice-bar-signal" aria-hidden="true" />
      <Link href={href} className="voice-bar-where">
        <b role="status">{v.connected ? "Voice Connected" : "Connecting…"}</b>
        <small>{where}</small>
      </Link>
      {v.state.audioBlocked && v.call && (
        <button type="button" className="btn btn-small btn-primary" onClick={() => void v.call?.startAudio()}>
          Click to hear everyone
        </button>
      )}
      <button
        type="button"
        className={`btn btn-small voice-bar-mic${v.micOn ? "" : " off"}`}
        aria-pressed={v.connected && v.canSpeak ? !v.micOn : undefined}
        disabled={!v.connected || !v.canSpeak}
        title={!v.canSpeak ? "You can only listen here" : v.micOn ? "Mute" : "Unmute"}
        onClick={() => void v.setMic(!v.micOn)}
      >
        {!v.canSpeak && v.connected ? "Listening" : v.micOn ? "Mute" : "Unmute"}
      </button>
      <button type="button" className="btn btn-small btn-danger" onClick={() => void v.leave()}>
        Disconnect
      </button>
    </section>
  );
}
