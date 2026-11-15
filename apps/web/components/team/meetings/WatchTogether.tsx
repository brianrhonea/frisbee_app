"use client";
import { type MeetingPlaybackDoc, type MeetingPlaybackRequest, playbackPositionAt, type TeamVideoDoc, watchTogether } from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import { getDownloadURL, ref } from "firebase/storage";
import { useCallback, useEffect, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { firebaseStorage } from "@/lib/firebase";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { useAuth } from "../../AuthProvider";
import { meetingApi } from "./model";

/** How many of the newest team videos the picker lists. */
const pickerCap = 100;

/** What a player reports when asked (PlayerStatus). */
interface PlayerStatus {
  positionMs: number;
  durationMs: number | null;
  playing: boolean;
}

/** A player something else drives (SyncedVideoController): no controls of its own. */
interface SyncedPlayer {
  play(): Promise<void>;
  pause(): Promise<void>;
  seekTo(ms: number): Promise<void>;
  status(): PlayerStatus | null;
  /** 0–1: the meeting volume, or 0 with audio muted (MeetingRoomViewModel._applyVolumes). */
  setVolume(volume: number): void;
}

type Video = Doc<TeamVideoDoc>;

/**
 * Watch together (WatchTogetherViewModel): an admin, the presenter, plays
 * a team video and everyone's player follows: which video, play, pause and
 * seeks. Each person plays it on their own device, at full quality. The
 * shared state is `playback/current`, the same doc the app reads and
 * writes, so app and web viewers stay in step.
 *
 * Once a second a viewer's player is nudged to match: play or pause, and
 * a seek when it's more than 1.5 s off. While it plays, the presenter
 * rewrites the state every 10 s so viewers correct for buffering.
 */
export function WatchTogether({ teamId, meetingId, canControl, stage, volume = 1 }: { teamId: string; meetingId: string; canControl: boolean; stage: boolean; volume?: number }) {
  const { user } = useAuth();
  const playback = useLiveDoc<MeetingPlaybackDoc>(`teams/${teamId}/meetings/${meetingId}/playback/current`);
  const p = playback.data ?? null;
  // The one playing, by id; the picker lists the newest (only presenters pick, with nothing playing).
  const current = useLiveDoc<TeamVideoDoc>(p?.videoId ? `teams/${teamId}/videos/${p.videoId}` : null);
  const videos = useLiveQuery<TeamVideoDoc>(canControl && !p && !stage ? `teams/${teamId}/videos` : null, [orderBy("createdAt", "desc"), limit(pickerCap)], "watch-videos");
  const video = p ? (current.data ?? undefined) : undefined;
  const controlling = canControl && !!p && p.presenterId === user?.uid;
  const player = useRef<SyncedPlayer | null>(null);
  const lastWrite = useRef(0);
  const stalled = useRef(0);
  const ticking = useRef(false);
  const latest = useRef(p);
  latest.current = p;
  const [status, setStatus] = useState<PlayerStatus | null>(null);
  const [needsTap, setNeedsTap] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scrub, setScrub] = useState<number | null>(null);

  const write = useCallback(
    async (body: MeetingPlaybackRequest) => {
      if (!user) return;
      lastWrite.current = Date.now();
      try {
        await callApi(user, `${meetingApi(teamId, meetingId)}/playback`, { method: "PUT", body: { ...body, positionMs: Math.max(0, Math.round(body.positionMs)) } });
        setError(null);
      } catch (e) {
        setError((e as Error).message);
      }
    },
    [user, teamId, meetingId],
  );

  const tick = useCallback(async () => {
    const c = player.current;
    const cur = latest.current;
    if (!c || !cur || ticking.current) return;
    ticking.current = true;
    try {
      const s = c.status();
      if (!s) return;
      setStatus(s);
      if (canControl && cur.presenterId === user?.uid) {
        // The presenter's player is the source of truth.
        if (!cur.playing) return;
        const ended = s.durationMs && s.durationMs > 0 ? !s.playing && s.positionMs >= s.durationMs - 1000 : false;
        if (ended) await write({ videoId: cur.videoId ?? "", playing: false, positionMs: s.positionMs });
        else if (s.playing && Date.now() - lastWrite.current >= watchTogether.heartbeatMs) {
          await write({ videoId: cur.videoId ?? "", playing: true, positionMs: s.positionMs });
        }
        return;
      }
      let target = playbackPositionAt(cur, Date.now());
      if (s.durationMs && s.durationMs > 0 && target > s.durationMs) target = s.durationMs;
      if (cur.playing && !s.playing) {
        await c.play().catch(() => undefined);
        // Still not playing after a few tries: the browser wants a click.
        stalled.current += 1;
        setNeedsTap(stalled.current >= 3);
      } else {
        stalled.current = 0;
        setNeedsTap(false);
        if (!cur.playing && s.playing) await c.pause();
      }
      if (Math.abs(s.positionMs - target) > watchTogether.toleranceMs) await c.seekTo(target);
    } finally {
      ticking.current = false;
    }
  }, [canControl, user?.uid, write]);

  // Ticks only while there's something to watch; changes apply straight away.
  useEffect(() => {
    if (!p) return;
    const id = window.setInterval(() => void tick(), watchTogether.tickMs);
    return () => window.clearInterval(id);
  }, [p?.videoId, tick]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    void tick();
  }, [p?.playing, p?.positionMs, p?.updatedAt, tick]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    stalled.current = 0;
    setNeedsTap(false);
    setStatus(null);
  }, [p?.videoId]);

  const volumeRef = useRef(volume);
  volumeRef.current = volume;
  useEffect(() => player.current?.setVolume(volume), [volume]);

  const attach = useCallback(
    (c: SyncedPlayer | null) => {
      player.current = c;
      if (c) {
        c.setVolume(volumeRef.current);
        void tick();
      }
    },
    [tick],
  );

  /** Play, pause or seek, from the presenter's own player (_transport). */
  async function transport(a: { playing?: boolean; positionMs?: number }) {
    if (!p) return;
    const c = player.current;
    const at = a.positionMs ?? c?.status()?.positionMs ?? playbackPositionAt(p, Date.now());
    if (c) {
      if (a.positionMs !== undefined) await c.seekTo(a.positionMs);
      if (a.playing === true) await c.play().catch(() => undefined);
      if (a.playing === false) await c.pause();
    }
    await write({ videoId: p.videoId ?? "", playing: a.playing ?? p.playing === true, positionMs: at });
  }

  async function stop() {
    if (!user) return;
    try {
      await callApi(user, `${meetingApi(teamId, meetingId)}/playback`, { method: "DELETE" });
    } catch (e) {
      setError((e as Error).message);
    }
  }

  // On the stage (always mounted in the call, so everyone follows and the
  // presenter's heartbeat keeps going): the player while something plays.
  // In the side panel: the admins' picker, or a pointer to the stage.
  if (stage && (!p || playback.error)) return null;
  if (playback.error) return <p className="muted small">Watch together isn&apos;t available until you&apos;re in the call.</p>;
  if (!stage) {
    if (p) return <p className="muted small">{video?.title || "A team video"} is playing for everyone above.</p>;
    if (!canControl) return <p className="muted small">When an admin plays a team video, it plays here for everyone.</p>;
    return <VideoPicker videos={videos.data ?? []} onPick={(id) => void write({ videoId: id, playing: false, positionMs: 0 })} error={error} />;
  }
  if (!p) return null;

  const duration = status?.durationMs ?? null;
  const position = scrub ?? status?.positionMs ?? playbackPositionAt(p, Date.now());
  return (
    <div className="watch">
      <div className="watch-head">
        <b>{video?.title || "Team video"}</b>
        <span className="muted small">{controlling ? "You're presenting" : `${p.presenterName || "An admin"} is presenting`}</span>
      </div>
      {!video ? (
        <p className="muted small">This video was removed.</p>
      ) : video.file?.path ? (
        <FileSyncedPlayer key={video.id} path={video.file.path} title={video.title || "Video"} onReady={attach} />
      ) : video.youtubeId ? (
        <YouTubeSyncedPlayer key={video.id} youtubeId={video.youtubeId} onReady={attach} />
      ) : (
        <p className="muted small">This video can&apos;t play here.</p>
      )}
      {needsTap && !controlling && (
        <button type="button" className="btn btn-primary btn-small" onClick={() => void player.current?.play().then(() => tick())}>
          Click to play along
        </button>
      )}
      {controlling ? (
        <div className="watch-controls">
          <button type="button" className="btn btn-small" onClick={() => void transport({ playing: !(p.playing === true) })}>
            {p.playing ? "Pause" : "Play"}
          </button>
          <input
            type="range"
            aria-label="Position"
            min={0}
            max={duration ?? Math.max(position, 1)}
            step={1000}
            value={Math.min(position, duration ?? position)}
            onChange={(e) => setScrub(Number(e.target.value))}
            // Seeks are written once let go, not on every move.
            onPointerUp={() => {
              if (scrub !== null) void transport({ positionMs: scrub }).then(() => setScrub(null));
            }}
            onKeyUp={() => {
              if (scrub !== null) void transport({ positionMs: scrub }).then(() => setScrub(null));
            }}
          />
          <span className="muted small">
            {clock(position)}
            {duration ? ` / ${clock(duration)}` : ""}
          </span>
          <button type="button" className="text-btn" onClick={() => void stop()}>
            Back to the call
          </button>
        </div>
      ) : (
        canControl && (
          <div className="watch-controls">
            <button
              type="button"
              className="btn btn-small"
              onClick={() => void write({ videoId: p.videoId ?? "", playing: p.playing === true, positionMs: status?.positionMs ?? playbackPositionAt(p, Date.now()) })}
            >
              Take control
            </button>
            <button type="button" className="text-btn" onClick={() => void stop()}>
              Back to the call
            </button>
          </div>
        )
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

const clock = (ms: number) => {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
};

function VideoPicker({ videos, onPick, error }: { videos: Video[]; onPick: (id: string) => void; error: string | null }) {
  const sorted = videos.slice().sort((a, b) => (b.createdAt ?? "").localeCompare(a.createdAt ?? ""));
  return (
    <div className="watch">
      <p className="muted small">Play a team video for everyone in the call. It starts paused at the beginning.</p>
      {sorted.length === 0 ? (
        <p className="empty">No team videos yet. Add some under Videos.</p>
      ) : (
        <ul className="watch-picker">
          {sorted.map((v) => (
            <li key={v.id}>
              <span>{v.title || "Video"}</span>
              <button type="button" className="btn btn-small" onClick={() => onPick(v.id)}>
                Show
              </button>
            </li>
          ))}
        </ul>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

/** An upload from Storage in a plain <video>, driven from outside. */
function FileSyncedPlayer({ path, title, onReady }: { path: string; title: string; onReady: (c: SyncedPlayer | null) => void }) {
  const el = useRef<HTMLVideoElement>(null);
  const [url, setUrl] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  useEffect(() => {
    const storage = firebaseStorage();
    if (!storage) return setProblem("Couldn't load this video.");
    let live = true;
    getDownloadURL(ref(storage, path)).then(
      (u) => live && setUrl(u),
      () => live && setProblem("Couldn't load this video."),
    );
    return () => {
      live = false;
    };
  }, [path]);
  useEffect(() => {
    const v = el.current;
    if (!url || !v) return;
    onReady({
      play: () => v.play(),
      pause: async () => v.pause(),
      seekTo: async (ms) => {
        v.currentTime = ms / 1000;
      },
      status: () =>
        v.readyState >= 1 ? { positionMs: v.currentTime * 1000, durationMs: Number.isFinite(v.duration) ? v.duration * 1000 : null, playing: !v.paused && !v.ended } : null,
      setVolume: (volume) => {
        v.volume = Math.min(1, Math.max(0, volume));
      },
    });
    return () => onReady(null);
  }, [url, onReady]);
  if (problem) return <div className="video-frame video-frame-note">{problem}</div>;
  if (!url) return <div className="video-frame video-frame-note" aria-busy="true">Loading…</div>;
  return <video ref={el} className="video-frame" src={url} preload="auto" playsInline aria-label={title} onError={() => setProblem("This browser can't play this file.")} />;
}

// YouTube's IFrame API, loaded once on first use.
interface YTPlayer {
  playVideo(): void;
  pauseVideo(): void;
  seekTo(seconds: number, allowSeekAhead: boolean): void;
  getCurrentTime(): number;
  getDuration(): number;
  getPlayerState(): number;
  setVolume(volume: number): void;
  destroy(): void;
}
type YTNamespace = { Player: new (el: HTMLElement, opts: object) => YTPlayer };
let ytApi: Promise<YTNamespace> | null = null;
function loadYouTube(): Promise<YTNamespace> {
  const w = window as unknown as { YT?: YTNamespace & { loaded?: number }; onYouTubeIframeAPIReady?: () => void };
  if (w.YT?.Player) return Promise.resolve(w.YT);
  ytApi ??= new Promise((resolve, reject) => {
    const prev = w.onYouTubeIframeAPIReady;
    w.onYouTubeIframeAPIReady = () => {
      prev?.();
      resolve(w.YT!);
    };
    const s = document.createElement("script");
    s.src = "https://www.youtube.com/iframe_api";
    s.async = true;
    s.onerror = () => {
      ytApi = null;
      reject(new Error("YouTube didn't load."));
    };
    document.head.appendChild(s);
  });
  return ytApi;
}

/** A YouTube link, through the IFrame API with its controls hidden. */
function YouTubeSyncedPlayer({ youtubeId, onReady }: { youtubeId: string; onReady: (c: SyncedPlayer | null) => void }) {
  const host = useRef<HTMLDivElement>(null);
  const [problem, setProblem] = useState<string | null>(null);
  useEffect(() => {
    let player: YTPlayer | null = null;
    let live = true;
    const mount = document.createElement("div");
    host.current?.appendChild(mount);
    loadYouTube().then(
      (YT) => {
        if (!live) return;
        player = new YT.Player(mount, {
          videoId: youtubeId,
          host: "https://www.youtube-nocookie.com",
          playerVars: { controls: 0, disablekb: 1, rel: 0, playsinline: 1, modestbranding: 1 },
          events: {
            onReady: () => {
              if (!live || !player) return;
              const p = player;
              onReady({
                play: async () => p.playVideo(),
                pause: async () => p.pauseVideo(),
                seekTo: async (ms) => p.seekTo(ms / 1000, true),
                status: () => ({ positionMs: p.getCurrentTime() * 1000, durationMs: p.getDuration() > 0 ? p.getDuration() * 1000 : null, playing: p.getPlayerState() === 1 }),
                setVolume: (volume) => p.setVolume(Math.round(Math.min(1, Math.max(0, volume)) * 100)),
              });
            },
            onError: () => live && setProblem("This YouTube video can't play here."),
          },
        });
      },
      () => live && setProblem("YouTube didn't load."),
    );
    return () => {
      live = false;
      onReady(null);
      player?.destroy();
      mount.remove();
    };
  }, [youtubeId, onReady]);
  if (problem) return <div className="video-frame video-frame-note">{problem}</div>;
  return <div ref={host} className="video-frame watch-youtube" />;
}
