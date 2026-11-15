"use client";
import type { MeetingTokenResult } from "@stall10/shared";
import type { LocalVideoTrack } from "livekit-client";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useLiveDoc, useLiveQuery } from "@/lib/live";
import { useAuth } from "../../AuthProvider";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { CallSession, deviceProblem, endNotices, useCall } from "./call";
import { CallStage, PeopleList, VideoView } from "./CallTiles";
import { type DeviceKind, DeviceSettings, selectedDevice, useDevices, withDevice } from "./DeviceSettings";
import { MeetingChat } from "./MeetingChat";
import { canSee, type JoinRequestData, type MeetingData, meetingApi, meetingHref, needsApproval } from "./model";
import { defaultSettings, loadSettings, type MeetingSettings, saveSettings } from "./settings";
import { WatchTogether } from "./WatchTogether";
import "./meetings.css";
import "./devices.css";

/** What the lobby offers right now (LobbyState). */
type Lobby = "loading" | "unavailable" | "ended" | "canStart" | "waitingToStart" | "canAsk" | "waitingForApproval" | "canJoin";
type Stage = "lobby" | "joining" | "inCall" | "left";

/**
 * The meeting room (MeetingRoomScreen): the lobby, then the call with its
 * chat, people and watch together. Admins start and end the meeting and
 * let people in. The browser asks for the mic and camera on joining,
 * never before.
 */
export function MeetingRoom({ meetingId }: { meetingId: string }) {
  const { user } = useAuth();
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const meeting = useLiveDoc<MeetingData>(member ? `teams/${teamId}/meetings/${meetingId}` : null);
  const m = meeting.data ?? null;
  const admin = member?.can("manageEvents") ?? false;
  const gated = !!m && !!member && needsApproval(m, admin);
  // Admins watch everyone's requests; invitees who need approval, their own.
  const myRequest = useLiveDoc<JoinRequestData>(member && gated ? `teams/${teamId}/meetings/${meetingId}/requests/${member.uid}` : null);
  const requests = useLiveQuery<JoinRequestData>(member && admin && m?.requireApproval ? `teams/${teamId}/meetings/${meetingId}/requests` : null, [], "requests");

  const [stage, setStage] = useState<Stage>("lobby");
  const [call, setCall] = useState<CallSession | null>(null);
  const state = useCall(call);
  // Remembered on this browser (MeetingSettings): start-up mic and camera, devices and volumes.
  const [settings, setSettings] = useState<MeetingSettings>(defaultSettings);
  useEffect(() => setSettings(loadSettings()), []);
  const update = useCallback((fn: (s: MeetingSettings) => MeetingSettings) => {
    setSettings((cur) => {
      const next = fn(cur);
      saveSettings(next);
      return next;
    });
  }, []);
  const { devices, reload: reloadDevices, speaker } = useDevices();
  const [preview, setPreview] = useState<LocalVideoTrack | null>(null);
  const previewRef = useRef<LocalVideoTrack | null>(null);
  const [mediaNotice, setMediaNotice] = useState<string | null>(null);
  const [wantsIn, setWantsIn] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [panel, setPanel] = useState<"people" | "chat" | "watch" | "settings">("people");
  const callRef = useRef<CallSession | null>(null);
  // Bumped on hang-up and unmount: a connect that finishes after either is dropped.
  const generation = useRef(0);

  let lobby: Lobby;
  if (!member || meeting.data === undefined) lobby = meeting.error ? "unavailable" : "loading";
  else if (!m || !canSee(m, member)) lobby = "unavailable";
  else if (m.status === "ended") lobby = "ended";
  else if (m.status !== "live") lobby = admin ? "canStart" : "waitingToStart";
  else if (!gated) lobby = "canJoin";
  else lobby = myRequest.data?.status === "admitted" ? "canJoin" : myRequest.data?.status === "pending" ? "waitingForApproval" : "canAsk";

  const hangUp = useCallback(async (why: string | null) => {
    generation.current += 1;
    const c = callRef.current;
    callRef.current = null;
    setCall(null);
    setStage("left");
    setNotice(why);
    await c?.leave();
  }, []);

  // Leaving the page leaves the call; the camera and mic stop.
  useEffect(
    () => () => {
      generation.current += 1;
      void callRef.current?.leave();
    },
    [],
  );

  const stopPreview = useCallback(() => {
    previewRef.current?.stop();
    previewRef.current = null;
    setPreview(null);
  }, []);
  // The lobby's camera preview while the camera is on (CameraPreview): the
  // browser asks for the camera here. It stops on joining, turning the
  // camera off, picking another camera and leaving the page.
  const previewCamera = selectedDevice(settings, devices, "videoinput");
  const wantsPreview = !!member && stage === "lobby" && settings.cameraOn;
  useEffect(() => {
    if (!wantsPreview) return;
    let live = true;
    CallSession.previewCamera(previewCamera).then(
      (track) => {
        if (!live) {
          track.stop();
          return;
        }
        previewRef.current = track;
        setPreview(track);
        setMediaNotice(null);
        reloadDevices(); // Names show once the browser allows the camera.
      },
      (e) => {
        if (!live) return;
        setMediaNotice(`${deviceProblem(e, "camera")} Or pick another camera.`);
        update((s) => ({ ...s, cameraOn: false }));
      },
    );
    return () => {
      live = false;
      stopPreview();
    };
  }, [wantsPreview, previewCamera, reloadDevices, stopPreview, update]);

  // The meeting ended or was deleted, or the server closed the room.
  useEffect(() => {
    if ((stage === "inCall" || stage === "joining") && meeting.data !== undefined && (!m || m.status === "ended")) void hangUp(endNotices.meetingEnded);
  }, [m, meeting.data, stage, hangUp]);
  useEffect(() => {
    if (state.ended && stage === "inCall") void hangUp(endNotices[state.ended]);
  }, [state.ended, stage, hangUp]);

  const join = useCallback(async () => {
    if (!user || stage !== "lobby") return;
    setStage("joining");
    setError(null);
    setNotice(null);
    const mine = ++generation.current;
    try {
      const access = await callApi<MeetingTokenResult>(user, `${meetingApi(teamId, meetingId)}/token`, { method: "POST" });
      if (mine !== generation.current) return;
      // The call opens the camera itself; release the preview's first.
      stopPreview();
      const c = await CallSession.connect({
        url: access.url,
        token: access.token,
        micOn: settings.micOn,
        cameraOn: settings.cameraOn,
        audioInputId: selectedDevice(settings, devices, "audioinput"),
        videoInputId: selectedDevice(settings, devices, "videoinput"),
        audioOutputId: speaker ? selectedDevice(settings, devices, "audiooutput") : null,
        volumes: { output: settings.outputVolume, people: settings.participantVolumes },
      });
      if (mine !== generation.current) {
        await c.leave();
        return;
      }
      callRef.current = c;
      setCall(c);
      setWantsIn(false);
      setStage("inCall");
    } catch (e) {
      if (mine !== generation.current) return;
      setError(e instanceof ApiError ? e.message : "Couldn't connect to the call. Check your connection and try again.");
      setStage("lobby");
    }
  }, [user, stage, teamId, meetingId, settings, devices, speaker, stopPreview]);

  /** A device picked in the lobby or the call (useDevice); null is the system default. */
  function pickDevice(kind: DeviceKind, id: string | null) {
    update((s) => withDevice(s, kind, id));
    if (call) {
      const target = id ?? (kind === "videoinput" ? devices.videoinput[0]?.deviceId : "default");
      if (target) void call.useDevice(kind, target);
    }
  }
  function setOutputVolume(v: number) {
    update((s) => ({ ...s, outputVolume: v }));
    call?.setOutputVolume(v);
  }
  function setPersonVolume(uid: string, v: number) {
    update((s) => ({ ...s, participantVolumes: { ...s.participantVolumes, [uid]: v } }));
    call?.setVolume(uid, v);
  }
  const deviceSettings = <DeviceSettings settings={settings} devices={devices} speaker={speaker} onDevice={pickDevice} onOutputVolume={setOutputVolume} />;
  const watchVolume = state.audioMuted ? 0 : settings.outputVolume;

  // Asked to join before it opened, or while waiting to be let in: straight in once they can.
  useEffect(() => {
    if (wantsIn && stage === "lobby" && lobby === "canJoin") void join();
  }, [wantsIn, stage, lobby, join]);

  async function run(fn: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const api = (path: string, method: string, body?: unknown) => callApi(user!, `${meetingApi(teamId, meetingId)}${path}`, { method, body });

  const start = () =>
    run(async () => {
      try {
        await api("/start", "POST");
      } catch (e) {
        // Another admin got there first: just join.
        if (!(e instanceof ApiError && e.status === 412 && /already started/.test(e.message))) throw e;
      }
      setWantsIn(true);
    });
  const ask = () =>
    run(async () => {
      await api(`/requests/${encodeURIComponent(member!.uid)}`, "PUT");
      setWantsIn(true);
    });
  const cancelAsk = () =>
    run(async () => {
      await api(`/requests/${encodeURIComponent(member!.uid)}`, "DELETE");
      setWantsIn(false);
    });
  const end = () => {
    if (!window.confirm("End the meeting for everyone?")) return;
    void run(async () => {
      await api("/end", "POST");
      await hangUp("You ended the meeting.");
    });
  };
  const decide = (uid: string, admit: boolean) => run(() => api(`/requests/${encodeURIComponent(uid)}/decision`, "PUT", { admit }));

  const back = (
    <Link href={meetingHref(teamId, meetingId)} className="text-btn">
      ← Meeting details
    </Link>
  );
  if (viewer.state === "loading") return <p className="muted" aria-busy="true">Loading…</p>;
  if (!member) return <MembersOnlySection what="meetings" />;

  const pending = (requests.data ?? []).filter((r) => r.status === "pending").sort((a, b) => (a.requestedAt ?? "").localeCompare(b.requestedAt ?? ""));

  if (stage === "inCall" && call) {
    return (
      <div className="meeting-call">
        <header className="call-head">
          <h2 className="card-title">{m?.title || "Meeting"}</h2>
          {state.audioBlocked && (
            <button type="button" className="btn btn-small btn-primary" onClick={() => void call.startAudio()}>
              Click to hear everyone
            </button>
          )}
        </header>
        {admin && pending.length > 0 && <Requests pending={pending} busy={busy} onDecide={decide} />}
        <div className="call-body">
          <div className="call-stage-wrap">
            <WatchTogether teamId={teamId} meetingId={meetingId} canControl={admin} stage volume={watchVolume} />
            <CallStage people={state.people} />
          </div>
          <aside className="card call-side">
            <div className="segmented" role="tablist" aria-label="Panel">
              {(
                [
                  ["people", `People (${state.people.length})`],
                  ["chat", "Chat"],
                  ["watch", "Watch together"],
                  ["settings", "Settings"],
                ] as const
              ).map(([k, label]) => (
                <button key={k} type="button" role="tab" className={panel === k ? "on" : ""} aria-selected={panel === k} onClick={() => setPanel(k)}>
                  {label}
                </button>
              ))}
            </div>
            {panel === "people" && <PeopleList people={state.people} volumes={settings.participantVolumes} onVolume={setPersonVolume} />}
            {panel === "chat" && <MeetingChat teamId={teamId} meetingId={meetingId} canModerate={admin} />}
            {panel === "watch" && <WatchTogether teamId={teamId} meetingId={meetingId} canControl={admin} stage={false} volume={watchVolume} />}
            {panel === "settings" && deviceSettings}
          </aside>
        </div>
        {state.notice && (
          <p className="form-error" role="alert">
            {state.notice}
          </p>
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <div className="call-controls" role="toolbar" aria-label="Call controls">
          <button type="button" className={`btn btn-small${state.micOn ? "" : " off"}`} aria-pressed={state.micOn} onClick={() => void call.setMic(!state.micOn)}>
            {state.micOn ? "Mute" : "Unmute"}
          </button>
          <button type="button" className={`btn btn-small${state.cameraOn ? "" : " off"}`} aria-pressed={state.cameraOn} onClick={() => void call.setCamera(!state.cameraOn)}>
            {state.cameraOn ? "Stop camera" : "Start camera"}
          </button>
          <button type="button" className={`btn btn-small${state.audioMuted ? " off" : ""}`} aria-pressed={state.audioMuted} onClick={() => call.setAudioMuted(!state.audioMuted)}>
            {state.audioMuted ? "Unmute audio" : "Mute audio"}
          </button>
          {typeof navigator !== "undefined" && !!navigator.mediaDevices?.getDisplayMedia && (
            <button type="button" className="btn btn-small" aria-pressed={state.screenSharing} onClick={() => void call.setScreen(!state.screenSharing)}>
              {state.screenSharing ? "Stop sharing" : "Share screen"}
            </button>
          )}
          <button type="button" className="btn btn-small" onClick={() => void hangUp(null)}>
            Leave
          </button>
          {admin && (
            <button type="button" className="btn btn-small btn-danger" disabled={busy} onClick={end}>
              End for everyone
            </button>
          )}
        </div>
      </div>
    );
  }

  const early = !!m?.startsAt && Date.parse(m.startsAt) > Date.now();
  return (
    <div className="stack meeting-lobby">
      {back}
      <section className="card settings-form">
        <h2>{m?.title || "Meeting room"}</h2>
        {stage === "left" && (
          <>
            <p>{notice ?? "You left the meeting."}</p>
            {m?.status === "live" && (
              <div className="home-actions">
                <button type="button" className="btn btn-primary" onClick={() => setStage("lobby")}>
                  Rejoin
                </button>
              </div>
            )}
          </>
        )}
        {stage !== "left" && (
          <>
            {lobby === "loading" && <p className="muted" aria-busy="true">Loading…</p>}
            {lobby === "unavailable" && <p className="empty">This meeting isn&apos;t available. It may have been deleted, or you weren&apos;t invited.</p>}
            {lobby === "ended" && <p className="empty">This meeting has ended.</p>}
            {!["loading", "unavailable", "ended"].includes(lobby) && (
              <>
                <div className="lobby-preview" aria-label="Camera preview">
                  {preview ? <VideoView track={preview} mirror /> : <span className="lobby-preview-off">Camera is off</span>}
                </div>
                {mediaNotice && (
                  <p className="form-error" role="alert">
                    {mediaNotice}
                  </p>
                )}
                <fieldset>
                  <legend>Join with</legend>
                  <label className="switch-row">
                    <input type="checkbox" checked={settings.micOn} onChange={(e) => update((s) => ({ ...s, micOn: e.target.checked }))} /> Microphone on
                  </label>
                  <label className="switch-row">
                    <input
                      type="checkbox"
                      checked={settings.cameraOn}
                      onChange={(e) => {
                        const on = e.target.checked;
                        if (on) setMediaNotice(null);
                        update((s) => ({ ...s, cameraOn: on }));
                      }}
                    />{" "}
                    Camera on
                  </label>
                  <p className="muted small">
                    Your browser asks for the camera for the preview, and for the microphone when you join. You can turn them on or off in the call.
                  </p>
                </fieldset>
                {deviceSettings}
                <div className="home-actions">
                  {lobby === "canStart" && (
                    <>
                      <button type="button" className="btn btn-primary" disabled={busy || stage === "joining"} onClick={() => void start()}>
                        {stage === "joining" ? "Joining…" : "Start meeting"}
                      </button>
                      {early && <p className="muted small">It&apos;s scheduled for later; starting now opens it early.</p>}
                    </>
                  )}
                  {lobby === "waitingToStart" && (
                    <>
                      <p className="muted">Waiting for an admin to start the meeting.</p>
                      <label className="switch-row">
                        <input type="checkbox" checked={wantsIn} onChange={(e) => setWantsIn(e.target.checked)} /> Join as soon as it starts
                      </label>
                    </>
                  )}
                  {lobby === "canAsk" && (
                    <>
                      {myRequest.data?.status === "denied" && <p className="muted">An admin didn&apos;t let you in. You can ask again.</p>}
                      <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void ask()}>
                        Ask to join
                      </button>
                    </>
                  )}
                  {lobby === "waitingForApproval" && (
                    <>
                      <p className="muted">Waiting for an admin to let you in. You&apos;ll join as soon as they do.</p>
                      <button type="button" className="btn" disabled={busy} onClick={() => void cancelAsk()}>
                        Cancel request
                      </button>
                    </>
                  )}
                  {lobby === "canJoin" && (
                    <button type="button" className="btn btn-primary" disabled={stage === "joining"} onClick={() => void join()}>
                      {stage === "joining" ? "Joining…" : "Join"}
                    </button>
                  )}
                </div>
              </>
            )}
          </>
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
      </section>
    </div>
  );
}

function Requests({ pending, busy, onDecide }: { pending: Array<JoinRequestData & { id: string }>; busy: boolean; onDecide: (uid: string, admit: boolean) => void }) {
  return (
    <section className="card call-requests" aria-label="Waiting to join">
      <h3 className="card-title">Waiting to join ({pending.length})</h3>
      <ul>
        {pending.map((r) => (
          <li key={r.id}>
            <span>{r.name || "Member"}</span>
            <span className="home-actions">
              <button type="button" className="btn btn-small btn-primary" disabled={busy} onClick={() => onDecide(r.id, true)}>
                Let in
              </button>
              <button type="button" className="btn btn-small" disabled={busy} onClick={() => onDecide(r.id, false)}>
                Turn away
              </button>
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}
