"use client";
import { formatVideoBytes, videoLimits, youtubeIdFrom } from "@stall10/shared";
import { useEffect, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../../AuthProvider";
import { type Folder, type Video, videosApi } from "./model";

/** Whether a pasted link points at a video the team can watch (LinkCheck). */
type LinkCheck =
  | { state: "empty" }
  | { state: "invalid" }
  | { state: "checking"; id: string }
  | { state: "embeddable"; id: string; title: string; channel: string }
  | { state: "notEmbeddable"; id: string }
  | { state: "unknown"; id: string };

/**
 * Asks YouTube's public oEmbed endpoint (no key; it allows browser calls)
 * whether the video can be embedded, and its title, as the app's
 * YouTubeInfoService does.
 */
async function lookUp(id: string): Promise<LinkCheck> {
  try {
    const url = `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(`https://www.youtube.com/watch?v=${id}`)}`;
    const res = await fetch(url);
    if (!res.ok) return { state: "notEmbeddable", id };
    const body = (await res.json()) as { title?: unknown; author_name?: unknown };
    return { state: "embeddable", id, title: String(body.title ?? ""), channel: String(body.author_name ?? "") };
  } catch {
    return { state: "unknown", id };
  }
}

const clip = (s: string) => (s.length > videoLimits.title ? s.substring(0, videoLimits.title) : s);

function LinkStatus({ check }: { check: LinkCheck }) {
  switch (check.state) {
    case "empty":
      return <small className="muted">Upload to YouTube as Unlisted (or Public), then paste the link.</small>;
    case "invalid":
      return <small className="video-status bad">That isn&apos;t a YouTube video link.</small>;
    case "checking":
      return <small className="muted">Checking with YouTube…</small>;
    case "embeddable":
      return <small className="video-status ok">Ready to play{check.channel ? ` · ${check.channel}` : ""}</small>;
    case "notEmbeddable":
      return (
        <small className="video-status bad">
          YouTube won&apos;t play this one here. Make sure it&apos;s Unlisted or Public (not Private) and that &quot;Allow embedding&quot; is on.
        </small>
      );
    case "unknown":
      return <small className="muted">Couldn&apos;t reach YouTube to check this link. You can still add it.</small>;
  }
}

/**
 * Adds a YouTube video, or edits one (VideoEditorScreen). Uploading a file
 * stays in the app until the API's video processing runs.
 */
export function VideoEditor({
  teamId,
  video,
  folders,
  initialFolderId,
  usedBytes,
  onDone,
}: {
  teamId: string;
  /** Null to add one. */
  video: Video | null;
  folders: Folder[];
  initialFolderId?: string;
  usedBytes: number;
  onDone: (id: string | null) => void;
}) {
  const { user } = useAuth();
  const editingFile = !!video?.file;
  const [link, setLink] = useState(video?.youtubeId ?? "");
  const [title, setTitle] = useState(video?.title ?? "");
  const [description, setDescription] = useState(video?.description ?? "");
  // A folder that no longer exists counts as none.
  const start = video ? video.folderId : initialFolderId;
  const [folderId, setFolderId] = useState(folders.some((f) => f.id === start) ? start! : "");
  const [check, setCheck] = useState<LinkCheck>({ state: "empty" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // The title YouTube gave, while the field still shows it unchanged.
  const autoTitle = useRef<string | null>(null);
  const titleRef = useRef(title);
  titleRef.current = title;

  useEffect(() => {
    if (editingFile) return;
    const id = youtubeIdFrom(link);
    if (!id) {
      setCheck({ state: link.trim() ? "invalid" : "empty" });
      return;
    }
    let live = true;
    const timer = setTimeout(() => {
      setCheck({ state: "checking", id });
      void lookUp(id).then((c) => {
        if (!live) return;
        setCheck(c);
        if (c.state === "embeddable" && c.title) {
          const current = titleRef.current.trim();
          if (!current || current === autoTitle.current) {
            const fill = clip(c.title);
            autoTitle.current = fill;
            setTitle(fill);
          }
        }
      });
    }, 400);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [link, editingFile]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!user) return;
    const youtubeId = editingFile ? "" : youtubeIdFrom(link);
    if (youtubeId === null) return setError("Paste a YouTube link.");
    const fallback = check.state === "embeddable" ? check.title : "";
    const name = clip(title.trim() || fallback.trim());
    if (!name) return setError("Give the video a title.");
    setBusy(true);
    setError(null);
    try {
      const body = { ...(editingFile ? {} : { youtubeId }), folderId, title: name, description: description.trim() };
      if (video) {
        await callApi(user, `${videosApi(teamId)}/${encodeURIComponent(video.id)}`, { method: "PATCH", body });
        onDone(video.id);
      } else {
        const r = await callApi<{ id: string }>(user, videosApi(teamId), { method: "POST", body });
        onDone(r.id);
      }
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  const canSave = !busy && (editingFile || youtubeIdFrom(link) !== null);
  return (
    <form className="card settings-form video-editor" onSubmit={(e) => void save(e)}>
      <h2 className="card-title">{video ? "Edit video" : "Add video"}</h2>
      {editingFile ? (
        <p className="video-file-row">
          <strong>{video!.file!.name}</strong>
          <span className="muted small"> · {formatVideoBytes(video!.file!.size ?? 0)}</span>
        </p>
      ) : (
        <label>
          YouTube link
          <input type="text" inputMode="url" value={link} placeholder="https://youtu.be/…" autoFocus={!video} onChange={(e) => setLink(e.target.value)} />
          <LinkStatus check={check} />
        </label>
      )}
      {!video && (
        <p className="muted small">
          To upload a video file (up to {formatVideoBytes(videoLimits.fileBytes)}; the team has used {formatVideoBytes(usedBytes)} of{" "}
          {formatVideoBytes(videoLimits.teamQuotaBytes)}), use the Stall 10 app.
        </p>
      )}
      <label>
        Title
        <input value={title} maxLength={videoLimits.title} onChange={(e) => setTitle(e.target.value)} />
        {!editingFile && <small className="muted">Filled in from YouTube; change it if you like.</small>}
      </label>
      <label>
        Description (optional)
        <textarea rows={4} value={description} maxLength={videoLimits.description} placeholder="What it covers, timestamps, who should watch…" onChange={(e) => setDescription(e.target.value)} />
      </label>
      {folders.length > 0 && (
        <label>
          Folder
          <select value={folderId} onChange={(e) => setFolderId(e.target.value)}>
            <option value="">No folder</option>
            {folders.map((f) => (
              <option key={f.id} value={f.id}>
                {f.name}
              </option>
            ))}
          </select>
        </label>
      )}
      <div className="home-actions">
        <button className="btn btn-primary btn-small" disabled={!canSave}>
          {busy ? "Saving…" : video ? "Save" : "Add video"}
        </button>
        <button type="button" className="btn btn-small" disabled={busy} onClick={() => onDone(null)}>
          Cancel
        </button>
      </div>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </form>
  );
}
