"use client";
import { formatVideoBytes, type TeamVideoDoc, type VideoFolderDoc, youtubeWatchUrl } from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { LocalTime } from "../../LocalTime";
import { useAuth } from "../../AuthProvider";
import { callApi } from "@/lib/client";
import { useLiveDoc, useLiveQuery } from "@/lib/live";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { VideoEditor } from "./VideoEditor";
import { byName, bytesUsed, type Folder, removeMessage, type Video, videosApi, videosHref } from "./model";
import { VideoPlayer } from "./VideoPlayer";
import "./videos.css";

/** One video (/teams/:id/videos/:videoId; the app's VideoScreen): the player, who shared it, and for admins edit and remove. */
export function VideoPage({ videoId }: { videoId: string }) {
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const router = useRouter();
  const member = viewer.state === "member";
  const editor = member && viewer.can("manageTeam");
  const live = useLiveDoc<TeamVideoDoc>(member ? `teams/${teamId}/videos/${videoId}` : null);
  const foldersLive = useLiveQuery<VideoFolderDoc>(member ? `teams/${teamId}/videoFolders` : null, [], "videoFolders");
  const allVideos = useLiveQuery<TeamVideoDoc>(editor ? `teams/${teamId}/videos` : null, [], "videos");
  const folders = useMemo(() => ((foldersLive.data ?? []) as Folder[]).slice().sort(byName), [foldersLive.data]);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const back = (
    <Link href={videosHref(teamId)} className="text-btn">
      ← Videos
    </Link>
  );

  if (!member) return <MembersOnlySection what="videos" />;
  if (live.error) return <p className="form-error">{live.error}</p>;
  if (foldersLive.error) return <p className="form-error">{foldersLive.error}</p>;
  if (live.data === undefined || foldersLive.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  if (live.data === null) return <p className="empty">Video not available. It may have been removed. {back}</p>;
  const video = live.data as Video;

  async function remove() {
    if (!user || !window.confirm(`Remove this video?\n\n${removeMessage(video)}`)) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `${videosApi(teamId)}/${encodeURIComponent(video.id)}`, { method: "DELETE" });
      router.push(videosHref(teamId));
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  const byline = [
    video.authorName ? `Shared by ${video.authorName}` : null,
    video.file ? formatVideoBytes(video.file.size ?? 0) : null,
  ].filter(Boolean);

  return (
    <div className="stack video-page">
      {back}
      <VideoPlayer video={video} />
      {editing ? (
        <VideoEditor
          teamId={teamId}
          video={video}
          folders={folders}
          usedBytes={bytesUsed((allVideos.data ?? []) as Video[])}
          onDone={() => setEditing(false)}
        />
      ) : (
        <div className="card">
          <h1 className="video-title">{video.title || "Video"}</h1>
          <p className="muted small">
            {byline.join(" · ")}
            {byline.length > 0 && video.createdAt ? " · " : ""}
            <LocalTime iso={video.createdAt} style="date" />
          </p>
          {video.description && <p className="video-description">{video.description}</p>}
          <div className="home-actions">
            {!video.file && video.youtubeId && (
              <a className="btn btn-small" href={youtubeWatchUrl(video.youtubeId)} target="_blank" rel="noopener noreferrer">
                Open on YouTube
              </a>
            )}
            {editor && (
              <>
                <button type="button" className="btn btn-small" disabled={busy} onClick={() => setEditing(true)}>
                  Edit
                </button>
                <button type="button" className="btn btn-small btn-danger" disabled={busy} onClick={() => void remove()}>
                  Remove
                </button>
              </>
            )}
          </div>
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
