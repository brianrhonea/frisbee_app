"use client";
import {
  postBodyMax,
  postImagesMax,
  postLinksMax,
  type PublicImage,
  type SavePostResult,
  type WorkoutActivity,
  type WorkoutInput,
  workoutActivities,
  workoutActivityLabels,
  workoutExercisesMax,
} from "@stall10/shared";
import { type ClipboardEvent, type DragEvent, type FormEvent, useEffect, useRef, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { newId, photoProblem, uploadPhoto } from "@/lib/upload";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { MemberImage } from "./MemberImage";
import { NavIcon } from "./NavIcons";

/** A photo on the post: already saved, or chosen now (uploading, then ready). */
type Photo =
  | { kind: "saved"; image: PublicImage }
  | { kind: "new"; key: string; preview: string; uploadId?: string; error?: string };

/** A workout as typed: numbers stay strings until it's posted. */
interface WorkoutDraft {
  activity: WorkoutActivity;
  minutes: string;
  distance: string;
  unit: "km" | "mi";
  effort: string;
  exercises: { name: string; sets: string; reps: string; weight: string }[];
}
const blankWorkout = (): WorkoutDraft => ({ activity: "run", minutes: "", distance: "", unit: "km", effort: "", exercises: [] });
const kmPerMile = 1.609344;

/** The workout to send, or what's wrong with it (validWorkout's limits). */
function workoutOf(d: WorkoutDraft): WorkoutInput | string {
  const minutes = Number(d.minutes);
  if (!d.minutes.trim() || !Number.isInteger(minutes) || minutes < 1 || minutes > 1440) {
    return "Give the workout's length in whole minutes (up to 24 hours).";
  }
  const exercises: NonNullable<WorkoutInput["exercises"]> = [];
  const out: WorkoutInput = { activity: d.activity, durationMinutes: minutes, exercises };
  if (d.distance.trim()) {
    const km = Number(d.distance) * (d.unit === "mi" ? kmPerMile : 1);
    if (!Number.isFinite(km) || km <= 0 || km > 1000) return "Distances go up to 1,000 km.";
    out.distanceKm = Math.round(km * 100) / 100;
  }
  if (d.effort) out.effort = Number(d.effort);
  const whole = (v: string, max: number) => {
    if (!v.trim()) return undefined;
    const n = Number(v);
    return Number.isInteger(n) && n >= 1 && n <= max ? n : NaN;
  };
  for (const x of d.exercises) {
    if (!x.name.trim() && !x.sets.trim() && !x.reps.trim() && !x.weight.trim()) continue;
    if (!x.name.trim()) return "Name each exercise.";
    const sets = whole(x.sets, 100);
    const reps = whole(x.reps, 1000);
    if (Number.isNaN(sets)) return "Sets go from 1 to 100.";
    if (Number.isNaN(reps)) return "Reps go from 1 to 1,000.";
    exercises.push({
      name: x.name.trim().slice(0, 60),
      ...(sets !== undefined && { sets }),
      ...(reps !== undefined && { reps }),
      ...(x.weight.trim() && { weight: x.weight.trim().slice(0, 20) }),
    });
  }
  return out;
}

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
 * paste them; they upload while you type) and up to 5 links. A new post
 * can be a workout, typed in (GPS recordings are made in the app).
 * Ctrl+Enter (⌘+Enter) posts.
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
  const [workout, setWorkout] = useState<WorkoutDraft | null>(null);
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
  const mayBeEmpty = (!!editing?.kind && editing.kind !== "text") || workout !== null;
  const canPost = !busy && !uploading && !failedPhoto && !tooLong && (mayBeEmpty || !empty);

  async function submit(e?: FormEvent) {
    e?.preventDefault();
    if (!canPost) return;
    const w = workout ? workoutOf(workout) : undefined;
    if (typeof w === "string") return setError(w);
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
        : await callApi<SavePostResult>(me, "/v1/posts", {
            method: "POST",
            body: { ...payload, id: postId, ...(w && { workout: w }) },
          });
      if (!editing) {
        photos.forEach((p) => p.kind === "new" && URL.revokeObjectURL(p.preview));
        setBody("");
        setLinks([]);
        setPhotos([]);
        setWorkout(null);
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
          placeholder={repost ? "Add a note" : workout ? "How did it go? (optional)" : "What's happening on the field?"}
          onChange={(e) => setBody(e.target.value)}
          onPaste={onPaste}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) void submit();
            if (e.key === "Escape" && onCancel) onCancel();
          }}
        />

        {workout && <WorkoutFields draft={workout} onChange={setWorkout} onRemove={() => setWorkout(null)} />}

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
                className="composer-tool"
                title="Add photos (or drop or paste them)"
                disabled={photos.length >= postImagesMax}
                onClick={() => files.current?.click()}
              >
                <PhotoIcon />
                <span>Photo</span>
              </button>
              <button
                type="button"
                className="composer-tool"
                title="Add a link"
                disabled={links.length >= postLinksMax}
                onClick={() => setAddingLink(true)}
              >
                <LinkIcon />
                <span>Link</span>
              </button>
              {!editing && (
                <button
                  type="button"
                  className={`composer-tool${workout ? " on" : ""}`}
                  title={workout ? "Remove the workout" : "Add a workout"}
                  aria-pressed={workout !== null}
                  onClick={() => setWorkout(workout ? null : blankWorkout())}
                >
                  <WorkoutIcon />
                  <span>Workout</span>
                </button>
              )}
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
            {!busy && !editing && <NavIcon name="arrow" size={16} />}
          </button>
        </div>
      </div>
    </form>
  );
}

/** The workout's details: activity, length, distance, effort and exercises. */
function WorkoutFields({
  draft,
  onChange,
  onRemove,
}: {
  draft: WorkoutDraft;
  onChange: (d: WorkoutDraft) => void;
  onRemove: () => void;
}) {
  const set = (patch: Partial<WorkoutDraft>) => onChange({ ...draft, ...patch });
  const setExercise = (i: number, patch: Partial<WorkoutDraft["exercises"][number]>) =>
    set({ exercises: draft.exercises.map((x, j) => (j === i ? { ...x, ...patch } : x)) });
  const digits = (v: string, n: number) => v.replace(/\D/g, "").slice(0, n);
  return (
    <fieldset className="workout-fields">
      <legend>Workout</legend>
      <div className="workout-row">
        <label>
          Activity
          <select value={draft.activity} onChange={(e) => set({ activity: e.target.value as WorkoutActivity })}>
            {workoutActivities.map((a) => (
              <option key={a} value={a}>
                {workoutActivityLabels[a]}
              </option>
            ))}
          </select>
        </label>
        <label>
          Minutes
          <input inputMode="numeric" value={draft.minutes} placeholder="45" onChange={(e) => set({ minutes: digits(e.target.value, 4) })} />
        </label>
        <label>
          Distance
          <span className="workout-distance">
            <input
              inputMode="decimal"
              value={draft.distance}
              placeholder="Optional"
              onChange={(e) => set({ distance: e.target.value.replace(/[^\d.]/g, "").slice(0, 7) })}
            />
            <select aria-label="Unit" value={draft.unit} onChange={(e) => set({ unit: e.target.value as "km" | "mi" })}>
              <option value="km">km</option>
              <option value="mi">mi</option>
            </select>
          </span>
        </label>
        <label>
          Effort
          <select value={draft.effort} onChange={(e) => set({ effort: e.target.value })}>
            <option value="">–</option>
            {Array.from({ length: 10 }, (_, i) => (
              <option key={i + 1} value={String(i + 1)}>
                {i + 1}/10
              </option>
            ))}
          </select>
        </label>
      </div>
      {draft.exercises.length > 0 && (
        <ul className="workout-exercises">
          {draft.exercises.map((x, i) => (
            <li key={i}>
              <input aria-label="Exercise" placeholder="Exercise" value={x.name} maxLength={60} onChange={(e) => setExercise(i, { name: e.target.value })} />
              <input aria-label="Sets" placeholder="Sets" inputMode="numeric" value={x.sets} onChange={(e) => setExercise(i, { sets: digits(e.target.value, 3) })} />
              <input aria-label="Reps" placeholder="Reps" inputMode="numeric" value={x.reps} onChange={(e) => setExercise(i, { reps: digits(e.target.value, 4) })} />
              <input aria-label="Weight" placeholder="Weight" value={x.weight} maxLength={20} onChange={(e) => setExercise(i, { weight: e.target.value })} />
              <button
                type="button"
                className="exercise-remove"
                aria-label="Remove exercise"
                onClick={() => set({ exercises: draft.exercises.filter((_, j) => j !== i) })}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
      <div className="workout-actions">
        {draft.exercises.length < workoutExercisesMax && (
          <button
            type="button"
            className="btn btn-small"
            onClick={() => set({ exercises: [...draft.exercises, { name: "", sets: "", reps: "", weight: "" }] })}
          >
            Add an exercise
          </button>
        )}
        <button type="button" className="btn btn-small" onClick={onRemove}>
          Remove workout
        </button>
      </div>
    </fieldset>
  );
}

function WorkoutIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" aria-hidden="true">
      <path d="M6 7v10M18 7v10M3 10v4M21 10v4M6 12h12" />
    </svg>
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
