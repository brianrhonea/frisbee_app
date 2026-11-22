"use client";
import type { VideoFileDoc } from "@stall10/shared";
import { getDownloadURL, ref } from "firebase/storage";
import { useEffect, useRef, useState } from "react";
import { firebaseStorage } from "@/lib/firebase";
import type { Video } from "./model";
import { loadYouTube, type YTPlayer } from "./youtube";

/** What a video's page asks of its player (the app's SyncedVideoController): its notes seek it (F4). */
export interface VideoSeeker {
  /** Where it is now, in ms; null until it's ready. */
  positionMs(): number | null;
  /** Plays from [ms]. */
  playFrom(ms: number): void;
}

/**
 * Plays a team video: YouTube's privacy-enhanced player for links, or the
 * uploaded file from Storage, which gives members a link because
 * storage.rules lets them read teams/{id}/videos (as the app's fileUrl).
 * [onReady] gets a [VideoSeeker] once it can seek, and null when it goes;
 * pass a stable function.
 */
export function VideoPlayer({ video, onReady }: { video: Video; onReady?: (s: VideoSeeker | null) => void }) {
  if (video.file) return <FilePlayer key={video.file.path} file={video.file} title={video.title || "Video"} onReady={onReady} />;
  return <YouTubePlayer key={video.youtubeId} youtubeId={video.youtubeId ?? ""} title={video.title || "Video"} onReady={onReady} />;
}

/** Through the IFrame API (so notes can seek it), with its own controls; a plain embed if the API won't load. */
function YouTubePlayer({ youtubeId, title, onReady }: { youtubeId: string; title: string; onReady?: (s: VideoSeeker | null) => void }) {
  const host = useRef<HTMLDivElement>(null);
  const [plain, setPlain] = useState(false);
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
          playerVars: { rel: 0, playsinline: 1, modestbranding: 1 },
          events: {
            onReady: () => {
              if (!live || !player) return;
              const p = player;
              onReady?.({
                positionMs: () => Math.round(p.getCurrentTime() * 1000),
                playFrom: (ms) => {
                  p.seekTo(ms / 1000, true);
                  p.playVideo();
                },
              });
            },
          },
        });
      },
      () => live && setPlain(true),
    );
    return () => {
      live = false;
      onReady?.(null);
      player?.destroy();
      mount.remove();
    };
  }, [youtubeId, onReady]);
  if (plain) {
    return (
      <iframe
        className="video-frame"
        src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(youtubeId)}`}
        title={title}
        allow="encrypted-media; picture-in-picture; fullscreen"
        allowFullScreen
      />
    );
  }
  return <div ref={host} className="video-frame watch-youtube" aria-label={title} />;
}

function FilePlayer({ file, title, onReady }: { file: VideoFileDoc; title: string; onReady?: (s: VideoSeeker | null) => void }) {
  const el = useRef<HTMLVideoElement>(null);
  const [url, setUrl] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  useEffect(() => {
    const storage = firebaseStorage();
    if (!storage || !file.path) {
      setProblem("Couldn't load this video.");
      return;
    }
    let live = true;
    getDownloadURL(ref(storage, file.path)).then(
      (u) => live && setUrl(u),
      () => live && setProblem("Couldn't load this video."),
    );
    return () => {
      live = false;
    };
  }, [file.path]);

  useEffect(() => {
    const v = el.current;
    if (!url || !v || !onReady) return;
    onReady({
      positionMs: () => (v.readyState >= 1 ? Math.round(v.currentTime * 1000) : null),
      playFrom: (ms) => {
        v.currentTime = ms / 1000;
        void v.play().catch(() => {});
      },
    });
    return () => onReady(null);
  }, [url, onReady]);

  if (problem) return <div className="video-frame video-frame-note">{problem}</div>;
  if (!url) return <div className="video-frame video-frame-note" aria-busy="true">Loading…</div>;
  return (
    // Browsers play MP4, MOV (H.264) and WebM; MKV, AVI and WMV may need the app.
    <video
      ref={el}
      className="video-frame"
      src={url}
      controls
      preload="metadata"
      aria-label={title}
      onError={() => setProblem("This browser can't play this file. Watch it in the Stall 10 app.")}
    />
  );
}
