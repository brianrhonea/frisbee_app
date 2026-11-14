"use client";
import type { VideoFileDoc } from "@stall10/shared";
import { getDownloadURL, ref } from "firebase/storage";
import { useEffect, useState } from "react";
import { firebaseStorage } from "@/lib/firebase";
import type { Video } from "./model";

/**
 * Plays a team video: YouTube's privacy-enhanced embed for links, or the
 * uploaded file from Storage, which gives members a link because
 * storage.rules lets them read teams/{id}/videos (as the app's fileUrl).
 */
export function VideoPlayer({ video }: { video: Video }) {
  if (video.file) return <FilePlayer key={video.file.path} file={video.file} title={video.title || "Video"} />;
  return (
    <iframe
      key={video.youtubeId}
      className="video-frame"
      src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(video.youtubeId ?? "")}`}
      title={video.title || "Video"}
      allow="encrypted-media; picture-in-picture; fullscreen"
      allowFullScreen
    />
  );
}

function FilePlayer({ file, title }: { file: VideoFileDoc; title: string }) {
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

  if (problem) return <div className="video-frame video-frame-note">{problem}</div>;
  if (!url) return <div className="video-frame video-frame-note" aria-busy="true">Loading…</div>;
  return (
    // Browsers play MP4, MOV (H.264) and WebM; MKV, AVI and WMV may need the app.
    <video
      className="video-frame"
      src={url}
      controls
      preload="metadata"
      aria-label={title}
      onError={() => setProblem("This browser can't play this file. Watch it in the Stall 10 app.")}
    />
  );
}
