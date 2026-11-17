"use client";
import { type SaveTeamPostRequest, teamPostImagesMax } from "@stall10/shared";
import { type ClipboardEvent, type DragEvent, type FormEvent, useEffect, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { submitOutbox } from "@/lib/outbox";
import { newId, photoProblem, uploadPhoto } from "@/lib/upload";
import { useAuth } from "../AuthProvider";
import { ComposerPhotos } from "../ComposerPhotos";
import type { TeamPostView } from "./TeamPostCard";

type Photo =
  | { kind: "saved"; path: string; name?: string }
  | { kind: "new"; key: string; file: File; preview: string; uploadId?: string; error?: string };

/**
 * Writes or edits a team post (admins with manageTeam): a title, words,
 * a place, up to four photos and whether outsiders see it. Web addresses
 * in the words show as links; an older post's separate links are kept.
 * Photos upload as they're added (`teamImage` uploads for this post id).
 */
export function TeamPostComposer({
  teamId,
  post,
  onDone,
}: {
  teamId: string;
  post?: TeamPostView & { id: string };
  onDone?: () => void;
}) {
  const { user } = useAuth();
  const [postId, setPostId] = useState(() => post?.id ?? newId());
  const [title, setTitle] = useState(post?.title ?? "");
  const [body, setBody] = useState(post?.body ?? "");
  const [location, setLocation] = useState(post?.location ?? "");
  const [links, setLinks] = useState<string[]>(post?.links ?? []);
  const [isPublic, setPublic] = useState(post?.public === true);
  const [photos, setPhotos] = useState<Photo[]>(() => (post?.images ?? []).map((i) => ({ kind: "saved", path: i.path, name: i.name })));
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState(Boolean(post));
  const fileInput = useRef<HTMLInputElement>(null);
  const previews = useRef<string[]>([]);
  useEffect(() => () => previews.current.forEach((u) => URL.revokeObjectURL(u)), []);

  function reset() {
    setPostId(newId());
    setTitle("");
    setBody("");
    setLocation("");
    setLinks([]);
    setPublic(false);
    setPhotos([]);
    setError(null);
    setOpen(false);
  }

  function addFiles(files: File[]) {
    if (!user) return;
    const room = teamPostImagesMax - photos.length;
    if (room <= 0) return setError(`Add at most ${teamPostImagesMax} photos.`);
    for (const file of files.slice(0, room)) {
      const problem = photoProblem(file, "teamImage");
      if (problem) {
        setError(problem);
        continue;
      }
      const key = newId();
      const preview = URL.createObjectURL(file);
      previews.current.push(preview);
      setPhotos((ps) => [...ps, { kind: "new", key, file, preview }]);
      uploadPhoto(user, file, { purpose: "teamImage", targetId: teamId, itemId: postId }).then(
        (done) => setPhotos((ps) => ps.map((p) => (p.kind === "new" && p.key === key ? { ...p, uploadId: done.id } : p))),
        (e: Error) => setPhotos((ps) => ps.map((p) => (p.kind === "new" && p.key === key ? { ...p, error: e.message } : p))),
      );
    }
  }

  const uploading = photos.some((p) => p.kind === "new" && !p.uploadId && !p.error);
  const canPost = !busy && !uploading && (body.trim().length > 0 || photos.some((p) => p.kind === "saved" || p.uploadId));

  async function submit(e?: FormEvent) {
    e?.preventDefault();
    if (!user || !canPost) return;
    setBusy(true);
    setError(null);
    const req: SaveTeamPostRequest = {
      title: title.trim(),
      body,
      location: location.trim(),
      links,
      public: isPublic,
      uploadIds: photos.flatMap((p) => (p.kind === "new" && p.uploadId ? [p.uploadId] : [])),
      ...(post && { keepImages: photos.flatMap((p) => (p.kind === "saved" ? [p.path] : [])) }),
    };
    try {
      if (post) {
        await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/posts/${encodeURIComponent(post.id)}`, { method: "PATCH", body: req });
        onDone?.();
      } else {
        // Offline, it waits in the queue (the banner says so) and goes out by itself.
        await submitOutbox(user, {
          kind: "teamPost",
          id: postId,
          target: teamId,
          label: "Team post",
          path: `/v1/teams/${encodeURIComponent(teamId)}/posts`,
          body: { ...req },
          preview: req.title || body.trim(),
          files: req.uploadIds?.length ?? 0,
        });
        reset();
        onDone?.();
      }
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  if (!open) {
    return (
      <button type="button" className="card composer-card team-compose-open" onClick={() => setOpen(true)}>
        Post an update to the team…
      </button>
    );
  }

  return (
    <form
      className="card composer team-composer"
      onSubmit={(e) => void submit(e)}
      onDragOver={(e: DragEvent) => e.preventDefault()}
      onDrop={(e: DragEvent) => {
        e.preventDefault();
        addFiles([...e.dataTransfer.files]);
      }}
      onPaste={(e: ClipboardEvent) => {
        const files = [...e.clipboardData.files];
        if (files.length) addFiles(files);
      }}
    >
      <div className="composer-main">
        <input aria-label="Title" placeholder="Title (optional)" value={title} maxLength={100} onChange={(e) => setTitle(e.target.value)} />
        <textarea
          aria-label="Post"
          placeholder="What's the news?"
          value={body}
          rows={3}
          maxLength={5000}
          autoFocus={!post}
          onChange={(e) => setBody(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) void submit();
            if (e.key === "Escape" && !post) setOpen(false);
          }}
        />
        <input aria-label="Where" placeholder="Where (optional)" value={location} maxLength={200} onChange={(e) => setLocation(e.target.value)} />
        <ComposerPhotos
          photos={photos.map((p) =>
            p.kind === "saved"
              ? { kind: "saved", key: p.path, path: p.path, url: "", alt: p.name ?? "" }
              : { kind: "new", key: p.key, preview: p.preview, uploading: !p.uploadId && !p.error, error: p.error },
          )}
          onRemove={(i) => setPhotos(photos.filter((_, j) => j !== i))}
        />
        {links.length > 0 && (
          <ul className="composer-links">
            {links.map((l) => (
              <li key={l}>
                {l}{" "}
                <button type="button" className="text-btn" onClick={() => setLinks(links.filter((x) => x !== l))}>
                  Remove
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
        <div className="composer-bar">
          <input ref={fileInput} type="file" accept="image/*" multiple hidden onChange={(e) => addFiles([...(e.target.files ?? [])])} />
          <button type="button" className="composer-tool" onClick={() => fileInput.current?.click()} disabled={photos.length >= teamPostImagesMax}>
            Photo
          </button>
          <label className="switch-row">
            <input type="checkbox" checked={isPublic} onChange={(e) => setPublic(e.target.checked)} /> Public (shows on the team page)
          </label>
          <span className="composer-spacer" />
          <button type="button" className="btn btn-small" onClick={() => (post ? onDone?.() : reset())}>
            Cancel
          </button>
          <button className="btn btn-primary btn-small" type="submit" disabled={!canPost} title="Ctrl+Enter">
            {busy ? "Saving…" : post ? "Save" : "Post"}
          </button>
        </div>
      </div>
    </form>
  );
}
