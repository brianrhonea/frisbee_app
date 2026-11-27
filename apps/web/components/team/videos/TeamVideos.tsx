"use client";
import { formatVideoBytes, videoFileFormat, videoLimits, youtubeThumbnailUrl } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { LocalTime } from "../../LocalTime";
import { useAuth } from "../../AuthProvider";
import { callApi } from "@/lib/client";
import { limit } from "firebase/firestore";
import { useLiveQuery } from "@/lib/live";
import { useTeamHub } from "../TeamContext";
import { VideoEditor } from "./VideoEditor";
import {
  byName,
  bytesUsed,
  type Folder,
  folderOf,
  foldersApi,
  matches,
  newestFirst,
  removeMessage,
  type Video,
  type VideoFilter,
  videoHref,
  videosApi,
} from "./model";
import "./videos.css";
import { useConfirm } from "@/components/ui/ConfirmDialog";

const videosCap = 1000;
const foldersCap = 200;

const same = (a: VideoFilter, b: VideoFilter) => a.kind === b.kind && (a.kind !== "folder" || (b.kind === "folder" && a.id === b.id));

/**
 * A team's Videos section (the app's VideosTab): YouTube links and
 * uploads, filed in folders. Members watch; members who manage the team
 * add, edit, file and remove videos and manage folders.
 */
export function TeamVideos() {
  const askConfirm = useConfirm();
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const editor = viewer.state === "member" && viewer.can("manageTeam");
  // Bounded well past a real team's library: the counts and storage used add up every video read.
  const videosLive = useLiveQuery<Video>(`teams/${teamId}/videos`, [limit(videosCap)], "videos");
  const foldersLive = useLiveQuery<Folder>(`teams/${teamId}/videoFolders`, [limit(foldersCap)], "videoFolders");
  const videos = useMemo(() => (videosLive.data ?? []).slice().sort(newestFirst), [videosLive.data]);
  const folders = useMemo(() => (foldersLive.data ?? []).slice().sort(byName), [foldersLive.data]);
  const [filter, setFilter] = useState<VideoFilter>({ kind: "all" });
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [moving, setMoving] = useState<string | null>(null);
  const [folderForm, setFolderForm] = useState<{ id: string | null; name: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // The folder being viewed was deleted.
  useEffect(() => {
    if (filter.kind === "folder" && foldersLive.data && !foldersLive.data.some((f) => f.id === filter.id)) setFilter({ kind: "all" });
  }, [filter, foldersLive.data]);

  if (videosLive.error) return <p className="form-error">{videosLive.error}</p>;
  // Folders load before the editor opens, so editing never unfiles a video.
  if (foldersLive.error) return <p className="form-error">{foldersLive.error}</p>;
  if (!videosLive.data || !foldersLive.data) return <p className="muted" aria-busy="true">Loading…</p>;

  const current = filter.kind === "folder" ? folders.find((f) => f.id === filter.id) : undefined;
  const countIn = (f: VideoFilter) => videos.filter((v) => matches(v, f, folders)).length;
  const visible = videos.filter((v) => matches(v, filter, folders));
  const unsorted = countIn({ kind: "unsorted" });

  async function run(path: string, method: string, body?: object): Promise<boolean> {
    if (!user) return false;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, path, { method, body });
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function saveFolder(e: React.FormEvent) {
    e.preventDefault();
    if (!user || !folderForm) return;
    const name = folderForm.name.trim();
    if (!name) return;
    setBusy(true);
    setError(null);
    try {
      if (folderForm.id) {
        await callApi(user, `${foldersApi(teamId)}/${encodeURIComponent(folderForm.id)}`, { method: "PATCH", body: { name } });
      } else {
        // Opens the new folder, as the app does.
        const r = await callApi<{ id: string }>(user, foldersApi(teamId), { method: "POST", body: { name } });
        setFilter({ kind: "folder", id: r.id });
      }
      setFolderForm(null);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function deleteFolder(f: Folder) {
    const n = countIn({ kind: "folder", id: f.id });
    const message = n === 0 ? "It has no videos." : `Its ${n === 1 ? "video moves" : `${n} videos move`} to Unsorted; no videos are deleted.`;
    if (!(await askConfirm({ message: `Delete the "${f.name}" folder?\n\n${message}`, confirmLabel: "Delete", destructive: true }))) return;
    void run(`${foldersApi(teamId)}/${encodeURIComponent(f.id)}`, "DELETE").then((ok) => ok && setFilter({ kind: "all" }));
  }

  async function remove(v: Video) {
    if (!(await askConfirm({ message: `Remove "${v.title}"?\n\n${removeMessage(v)}`, confirmLabel: "Remove", destructive: true }))) return;
    void run(`${videosApi(teamId)}/${encodeURIComponent(v.id)}`, "DELETE");
  }

  const chip = (f: VideoFilter, label: string) => (
    <button type="button" className={same(filter, f) ? "on" : ""} aria-pressed={same(filter, f)} onClick={() => setFilter(f)}>
      {label} ({countIn(f)})
    </button>
  );
  const used = bytesUsed(videos);
  const editingVideo = editing ? videos.find((v) => v.id === editing) : undefined;

  return (
    <div className="stack videos">
      {editor && !adding && !editingVideo && (
        <div className="home-actions videos-actions">
          <button type="button" className="btn btn-primary btn-small" onClick={() => setAdding(true)}>
            Add video
          </button>
        </div>
      )}
      {editor && (adding || editingVideo) && (
        <VideoEditor
          key={editingVideo?.id ?? "new"}
          teamId={teamId}
          video={editingVideo ?? null}
          folders={folders}
          initialFolderId={current?.id}
          usedBytes={used}
          onDone={() => {
            setAdding(false);
            setEditing(null);
          }}
        />
      )}
      {editor && videos.length > 0 && (
        <div className="video-usage">
          <span className="muted small">
            Uploads: {formatVideoBytes(used)} of {formatVideoBytes(videoLimits.teamQuotaBytes)} used
          </span>
          <meter min={0} max={videoLimits.teamQuotaBytes} high={videoLimits.teamQuotaBytes * 0.9} value={used} aria-label="Upload space used" />
        </div>
      )}
      {(editor || folders.length > 0) && (
        <div className="video-folders">
          <div className="segmented" role="group" aria-label="Folders">
            {chip({ kind: "all" }, "All")}
            {folders.map((f) => (
              <span key={f.id} className="video-chip-wrap">
                {chip({ kind: "folder", id: f.id }, f.name || "Folder")}
              </span>
            ))}
            {folders.length > 0 && (unsorted > 0 || filter.kind === "unsorted") && chip({ kind: "unsorted" }, "Unsorted")}
          </div>
          {editor && (
            <span className="video-folder-tools">
              <button type="button" className="text-btn" disabled={busy} onClick={() => setFolderForm({ id: null, name: "" })}>
                New folder
              </button>
              {current && (
                <>
                  <button type="button" className="text-btn" disabled={busy} onClick={() => setFolderForm({ id: current.id, name: current.name ?? "" })}>
                    Rename &quot;{current.name}&quot;
                  </button>
                  <button type="button" className="text-btn" disabled={busy} onClick={() => deleteFolder(current)}>
                    Delete &quot;{current.name}&quot;
                  </button>
                </>
              )}
            </span>
          )}
        </div>
      )}
      {folderForm && (
        <form className="card settings-form video-folder-form" onSubmit={(e) => void saveFolder(e)}>
          <label>
            {folderForm.id ? "Rename folder" : "New folder"}
            <input
              value={folderForm.name}
              maxLength={videoLimits.folderName}
              placeholder="Film review, Game film, Highlights…"
              autoFocus
              onChange={(e) => setFolderForm({ ...folderForm, name: e.target.value })}
            />
          </label>
          <div className="home-actions">
            <button className="btn btn-primary btn-small" disabled={busy || !folderForm.name.trim()}>
              {folderForm.id ? "Rename" : "Create"}
            </button>
            <button type="button" className="btn btn-small" onClick={() => setFolderForm(null)}>
              Cancel
            </button>
          </div>
        </form>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {visible.length === 0 ? (
        videos.length === 0 ? (
          <p className="empty">
            {editor
              ? "No videos yet. Add a YouTube link (unlisted works), or upload a video file in the app."
              : "No videos yet. Meeting recordings and film your coaches share will show up here."}
          </p>
        ) : (
          <p className="empty">
            {filter.kind === "unsorted" ? "Every video is in a folder." : `Nothing in ${current?.name ?? "this folder"} yet.`}{" "}
            {editor ? "Add a video here, or use Move to folder on any video." : "Videos your coaches file here will show up."}
          </p>
        )
      ) : (
        <div className="card video-list">
          {visible.map((v) => (
            <VideoCard
              key={v.id}
              teamId={teamId}
              video={v}
              folderName={filter.kind === "all" ? folderOf(v, folders)?.name : undefined}
              folders={folders}
              editor={editor}
              busy={busy}
              moving={moving === v.id}
              onEdit={() => {
                setAdding(false);
                setEditing(v.id);
                window.scrollTo({ top: 0, behavior: "smooth" });
              }}
              onMove={() => setMoving(v.id)}
              onMoved={(folderId) => {
                setMoving(null);
                if (folderId !== null && folderId !== (folderOf(v, folders) ? v.folderId : "")) {
                  void run(`${videosApi(teamId)}/${encodeURIComponent(v.id)}`, "PATCH", { folderId });
                }
              }}
              onRemove={() => remove(v)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function VideoCard({
  teamId,
  video: v,
  folderName,
  folders,
  editor,
  busy,
  moving,
  onEdit,
  onMove,
  onMoved,
  onRemove,
}: {
  teamId: string;
  video: Video;
  folderName?: string;
  folders: Folder[];
  editor: boolean;
  busy: boolean;
  moving: boolean;
  onEdit: () => void;
  onMove: () => void;
  /** The folder picked ("" for none), or null to cancel. */
  onMoved: (folderId: string | null) => void;
  onRemove: () => void;
}) {
  const [target, setTarget] = useState(folderOf(v, folders) ? (v.folderId ?? "") : "");
  const close = (e: React.MouseEvent) => {
    (e.currentTarget.closest("details") as HTMLDetailsElement | null)?.removeAttribute("open");
  };
  return (
    <article className="video-card video-row">
      <Link href={videoHref(teamId, v.id)} className="video-thumb" aria-label={`Watch ${v.title || "video"}`}>
        {v.file ? (
          <span className="video-thumb-file">
            <span className="video-badge">
              {videoFileFormat(v.file.name ?? "")} · {formatVideoBytes(v.file.size ?? 0)}
            </span>
          </span>
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={youtubeThumbnailUrl(v.youtubeId ?? "")} alt="" loading="lazy" />
        )}
        <span className="video-play" aria-hidden="true" />
      </Link>
      <div className="video-card-body">
        <div className="video-card-text">
          <h3>
            <Link href={videoHref(teamId, v.id)}>{v.title || "Video"}</Link>
          </h3>
          {v.description && <p className="small video-card-desc">{v.description}</p>}
          <p className="muted small">
            {[folderName, v.authorName].filter(Boolean).join(" · ")}
            {(folderName || v.authorName) && v.createdAt ? " · " : ""}
            <LocalTime iso={v.createdAt} style="date" />
          </p>
        </div>
        {editor && (
          <details className="post-menu">
            <summary aria-label="Video options">⋯</summary>
            <div className="menu-list">
              <button type="button" onClick={(e) => { close(e); onEdit(); }}>
                Edit
              </button>
              {folders.length > 0 && (
                <button type="button" onClick={(e) => { close(e); onMove(); }}>
                  Move to folder
                </button>
              )}
              <button type="button" onClick={(e) => { close(e); onRemove(); }}>
                Remove
              </button>
            </div>
          </details>
        )}
      </div>
      {moving && (
        <div className="settings-form video-move">
          <label>
            Move &quot;{v.title}&quot; to
            <select value={target} onChange={(e) => setTarget(e.target.value)} autoFocus>
              <option value="">No folder</option>
              {folders.map((f) => (
                <option key={f.id} value={f.id}>
                  {f.name}
                </option>
              ))}
            </select>
          </label>
          <div className="home-actions">
            <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={() => onMoved(target)}>
              Move
            </button>
            <button type="button" className="btn btn-small" onClick={() => onMoved(null)}>
              Cancel
            </button>
          </div>
        </div>
      )}
    </article>
  );
}
