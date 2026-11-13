"use client";
import {
  postBodyMax,
  postImagesMax,
  postLinksMax,
  type PublicImage,
  type SavePostResult,
} from "@stall10/shared";
import { type ClipboardEvent, type DragEvent, type FormEvent, useEffect, useRef, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { newId, photoProblem, uploadPhoto } from "@/lib/upload";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { MemberImage } from "./MemberImage";

/** A photo on the post: already saved, or chosen now (uploading, then ready). */
type Photo =
  | { kind: "saved"; image: PublicImage }
  | { kind: "new"; key: string; preview: string; uploadId?: string; error?: string };

const problem = (e: unknown) => (e instanceof ApiError ? e.message : "Something went wrong. Try again.");

/** The post being edited, when not writing a new one. */
export interface EditingPost {
  id: string;
  body: string;
  links: string[];
  images: PublicImage[];
  /** A repost only has a note; workout and event posts keep their details. */
  kind?: string;
}

/**
 * Writing a post, or editing one: words, up to 4 photos (choose, drop or
 * paste them; they upload while you type) and up to 5 links. Ctrl+Enter
 * (⌘+Enter) posts.
 */
export function Composer({
  editing,
  onSaved,
  onCancel,
  autoFocus = false,
}: {
  editing?: EditingPost;
  /** With what was saved: the words and links as sent. */
  onSaved?: (result: SavePostResult, saved: { body: string; links: string[] }) => void;
  onCancel?: () => void;
  autoFocus?: boolean;
}) {
  const { user } = useAuth();
  const [postId, setPostId] = useState(() => editing?.id ?? newId());
  const [body, setBody] = useState(editing?.body ?? "");
  const [links, setLinks] = useState<string[]>(editing?.links ?? []);
  const [linkText, setLinkText] = useState("");
  const [addingLink, setAddingLink] = useState(false);
  const [photos, setPhotos] = useState<Photo[]>(
    () => editing?.images.map((image) => ({ kind: "saved" as const, image })) ?? [],
  );
  const [dragging, setDragging] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const text = useRef<HTMLTextAreaElement>(null);
  const files = useRef<HTMLInputElement>(null);
  const repost = editing?.kind === "repost";

  // Grow the box with what's written.
  useEffect(() => {
    const el = text.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  }, [body]);

  useEffect(() => {
    if (autoFocus) text.current?.focus();
  }, [autoFocus]);

  // Previews are object URLs; free them when they go.
  useEffect(
    () => () => photos.forEach((p) => p.kind === "new" && URL.revokeObjectURL(p.preview)),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only on unmount
    [],
  );

  if (!user) return null;
  const me = user;

  function addFiles(list: FileList | File[]) {
    setError(null);
    const room = postImagesMax - photos.length;
    const chosen = Array.from(list).slice(0, Math.max(room, 0));
    if (list.length > room) setError(`Add at most ${postImagesMax} photos.`);
    for (const file of chosen) {
      const bad = photoProblem(file);
      if (bad) {
        setError(bad);
        continue;
      }
      const key = newId();
      setPhotos((ps) => [...ps, { kind: "new", key, preview: URL.createObjectURL(file) }]);
      uploadPhoto(me, file, { itemId: postId }).then(
        (done) => setPhotos((ps) => ps.map((p) => (p.kind === "new" && p.key === key ? { ...p, uploadId: done.id } : p))),
        (e) => setPhotos((ps) => ps.map((p) => (p.kind === "new" && p.key === key ? { ...p, error: problem(e) } : p))),
      );
    }
  }

  function removePhoto(i: number) {
    setPhotos((ps) => {
      const p = ps[i];
      if (p?.kind === "new") URL.revokeObjectURL(p.preview);
      return ps.filter((_, j) => j !== i);
    });
  }

  function addLink() {
    const raw = linkText.trim();
    if (!raw) return setAddingLink(false);
    const url = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
    try {
      new URL(url);
    } catch {
      return setError("That doesn't look like a link.");
    }
    if (links.length >= postLinksMax) return setError(`Add at most ${postLinksMax} links.`);
    if (!links.includes(url)) setLinks([...links, url]);
    setLinkText("");
    setAddingLink(false);
    setError(null);
  }

  const uploading = photos.some((p) => p.kind === "new" && !p.uploadId && !p.error);
  const failedPhoto = photos.some((p) => p.kind === "new" && p.error);
  const empty = !body.trim() && photos.length === 0;
  const tooLong = body.length > postBodyMax;
  // Workout, event and repost posts have more than their words.
  const mayBeEmpty = !!editing?.kind && editing.kind !== "text";
  const canPost = !busy && !uploading && !failedPhoto && !tooLong && (mayBeEmpty || !empty);

  async function submit(e?: FormEvent) {
    e?.preventDefault();
    if (!canPost) return;
    setBusy(true);
    setError(null);
    const payload = {
      body,
      links: repost ? [] : links,
      uploadIds: photos.flatMap((p) => (p.kind === "new" && p.uploadId ? [p.uploadId] : [])),
      ...(editing && { keepImages: photos.flatMap((p) => (p.kind === "saved" ? [p.image.path] : [])) }),
    };
    try {
      const result = editing
        ? await callApi<SavePostResult>(me, `/v1/posts/${encodeURIComponent(editing.id)}`, {
            method: "PATCH",
            body: payload,
          })
        : await callApi<SavePostResult>(me, "/v1/posts", { method: "POST", body: { ...payload, id: postId } });
      if (!editing) {
        photos.forEach((p) => p.kind === "new" && URL.revokeObjectURL(p.preview));
        setBody("");
        setLinks([]);
        setPhotos([]);
        setPostId(newId());
      }
      onSaved?.(result, { body: body.trim(), links: payload.links });
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(false);
    }
  }

  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setDragging(false);
    if (!repost && e.dataTransfer.files.length) addFiles(e.dataTransfer.files);
  };
  const onPaste = (e: ClipboardEvent) => {
    const pasted = Array.from(e.clipboardData.files);
    if (!repost && pasted.length) {
      e.preventDefault();
      addFiles(pasted);
    }
  };

  const left = postBodyMax - body.length;
  return (
    <form
      className={`composer${dragging ? " dragging" : ""}`}
      onSubmit={(e) => void submit(e)}
      onDragOver={(e) => {
        if (repost) return;
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={onDrop}
    >
      {!editing && <Avatar name={me.displayName ?? "You"} url={me.photoURL ?? undefined} />}
      <div className="composer-main">
        <label className="sr-only" htmlFor={`composer-${postId}`}>
          {repost ? "Your note" : "Write a post"}
        </label>
        <textarea
          id={`composer-${postId}`}
          ref={text}
          value={body}
          rows={editing ? 3 : 2}
          placeholder={repost ? "Add a note" : "What's happening on the field?"}
          onChange={(e) => setBody(e.target.value)}
          onPaste={onPaste}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) void submit();
            if (e.key === "Escape" && onCancel) onCancel();
          }}
        />

        {photos.length > 0 && (
          <ul className={`composer-photos n${photos.length}`}>
            {photos.map((p, i) => (
              <li key={p.kind === "saved" ? p.image.path : p.key} className={p.kind === "new" && p.error ? "failed" : ""}>
                {p.kind === "saved" ? (
                  <MemberImage path={p.image.path} url={p.image.url} alt="" />
                ) : (
                  <img src={p.preview} alt="" />
                )}
                {p.kind === "new" && !p.uploadId && !p.error && <span className="photo-status">Uploading…</span>}
                {p.kind === "new" && p.error && <span className="photo-status">{p.error}</span>}
                <button type="button" className="photo-remove" aria-label="Remove photo" onClick={() => removePhoto(i)}>
                  ×
                </button>
              </li>
            ))}
          </ul>
        )}

        {links.length > 0 && (
          <ul className="composer-links">
            {links.map((l) => (
              <li key={l}>
                <span>{l.replace(/^https?:\/\//, "")}</span>
                <button type="button" aria-label={`Remove ${l}`} onClick={() => setLinks(links.filter((x) => x !== l))}>
                  ×
                </button>
              </li>
            ))}
          </ul>
        )}
        {addingLink && (
          <div className="composer-link-row">
            <input
              type="url"
              value={linkText}
              placeholder="https://"
              autoFocus
              onChange={(e) => setLinkText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  addLink();
                }
                if (e.key === "Escape") setAddingLink(false);
              }}
            />
            <button type="button" className="btn btn-small" onClick={addLink}>
              Add
            </button>
          </div>
        )}

        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}

        <div className="composer-bar">
          {!repost && (
            <>
              <input
                ref={files}
                type="file"
                accept="image/*,.heic,.heif"
                multiple
                hidden
                onChange={(e) => {
                  if (e.target.files) addFiles(e.target.files);
                  e.target.value = "";
                }}
              />
              <button
                type="button"
                className="icon-btn"
                title="Add photos (or drop or paste them)"
                disabled={photos.length >= postImagesMax}
                onClick={() => files.current?.click()}
              >
                <PhotoIcon />
                <span className="sr-only">Add photos</span>
              </button>
              <button
                type="button"
                className="icon-btn"
                title="Add a link"
                disabled={links.length >= postLinksMax}
                onClick={() => setAddingLink(true)}
              >
                <LinkIcon />
                <span className="sr-only">Add a link</span>
              </button>
            </>
          )}
          <span className="composer-spacer" />
          {left < 300 && <span className={`composer-count${left < 0 ? " over" : ""}`}>{left}</span>}
          {onCancel && (
            <button type="button" className="btn btn-small" onClick={onCancel}>
              Cancel
            </button>
          )}
          <button className="btn btn-primary btn-small" type="submit" disabled={!canPost} title="Ctrl+Enter">
            {busy ? (editing ? "Saving…" : "Posting…") : editing ? "Save" : "Post"}
          </button>
        </div>
      </div>
    </form>
  );
}

function PhotoIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" aria-hidden="true">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <circle cx="9" cy="10" r="1.6" />
      <path d="m21 16-5-5-8 8" />
    </svg>
  );
}

function LinkIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" aria-hidden="true">
      <path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1" />
      <path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" />
    </svg>
  );
}
