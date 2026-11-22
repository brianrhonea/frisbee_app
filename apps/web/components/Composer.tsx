"use client";
import {
  postBodyMax,
  postImagesMax,
  type PublicImage,
  type SavePostResult,
  type SaveTeamPostRequest,
  type TagTournament,
  type TagTournaments,
  teamPostImagesMax,
  type WorkoutActivity,
  type WorkoutInput,
  workoutActivities,
  workoutActivityLabels,
  workoutExercisesMax,
} from "@stall10/shared";
import { type ClipboardEvent, type DragEvent, type FormEvent, useEffect, useRef, useState } from "react";
import { where } from "firebase/firestore";
import Link from "next/link";
import { callApi, problem } from "@/lib/client";
import { queuedNotice, submitOutbox } from "@/lib/outbox";
import { useLiveQuery } from "@/lib/live";
import { newId, photoProblem, uploadPhoto } from "@/lib/upload";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { ComposerPhotos } from "./ComposerPhotos";
import { NavIcon } from "./NavIcons";
import "./composer_tag.css";

/**
 * A photo on the post: already saved, or chosen now (uploading, then
 * ready). [target] is who it was uploaded for ("" for the member's own
 * post, else the team's id): changing the audience uploads it again.
 */
type Photo =
  | { kind: "saved"; image: PublicImage }
  | { kind: "new"; key: string; file: File; target: string; preview: string; uploadId?: string; error?: string };

/** A team or group the member can post on from Home (manageTeam). */
export interface Audience {
  id: string;
  name: string;
  /** A group that approves who joins: its posts stay inside (no Public). */
  privateGroup: boolean;
}

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


/** The post being edited, when not writing a new one. */
interface EditingPost {
  id: string;
  body: string;
  links: string[];
  images: PublicImage[];
  /** A repost only has a note; workout and event posts keep their details. */
  kind?: string;
  /** Its "At a tournament" tag, if any. */
  tournament?: { key: string; name: string } | null;
}

/**
 * Writing a post, or editing one: words, up to 4 photos (choose, drop or
 * paste them; they upload while you type). There's no link tool: web
 * addresses in the words show as links. A new post
 * can be a workout, typed in (GPS recordings are made in the app).
 * Ctrl+Enter (⌘+Enter) posts.
 *
 * With [audiences] (Home), a "To" chip posts to Everyone (the member's own
 * post) or to one of those teams: a team post as the team page's composer
 * (and the app's Team post) writes it, with a title, a place and whether
 * outsiders see it, on the team's feed.
 */
export function Composer({
  editing,
  onSaved,
  onTeamPosted,
  onCancel,
  autoFocus = false,
  audiences = [],
}: {
  editing?: EditingPost;
  /** A team post was saved, on [teamId]. */
  onTeamPosted?: (teamId: string) => void;
  /** Teams the member may post to from here; none, just their own posts. */
  audiences?: Audience[];
  /** With what was saved: the words and links as sent. */
  onSaved?: (result: SavePostResult, saved: { body: string; links: string[]; tournament?: { key: string; name: string } | null }) => void;
  onCancel?: () => void;
  autoFocus?: boolean;
}) {
  const { user } = useAuth();
  const [postId, setPostId] = useState(() => editing?.id ?? newId());
  const [body, setBody] = useState(editing?.body ?? "");
  // Links from before the link tool went (editing an older post): kept, and
  // can be removed. New ones go in the text, which shows them as links.
  const [links, setLinks] = useState<string[]>(editing?.links ?? []);
  const [photos, setPhotos] = useState<Photo[]>(
    () => editing?.images.map((image) => ({ kind: "saved" as const, image })) ?? [],
  );
  const [workout, setWorkout] = useState<WorkoutDraft | null>(null);
  const [dragging, setDragging] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // The team posted to (null: Everyone), and a team post's own fields.
  const [teamId, setTeamId] = useState<string | null>(null);
  const team = editing ? undefined : audiences.find((a) => a.id === teamId);
  const [title, setTitle] = useState("");
  const [place, setPlace] = useState("");
  const [isPublic, setPublic] = useState(false);
  const [posted, setPosted] = useState<Audience | null>(null);
  const [queued, setQueued] = useState<string | null>(null);
  const text = useRef<HTMLTextAreaElement>(null);
  const files = useRef<HTMLInputElement>(null);
  const repost = editing?.kind === "repost";
  // "At a tournament": followed tournaments from a week before they start to
  // their last day (GET /v1/me/tag-tournaments, as in the app), asked again
  // when the follows change. An edited post keeps its own tag on offer.
  const [tag, setTag] = useState<{ key: string; name: string } | null>(editing?.tournament ?? null);
  const followed = useLiveQuery<{ key?: string; name?: string; type?: string }>(
    user && !repost ? `users/${user.uid}/follows` : null,
    [where("type", "==", "tournament")],
    `${user?.uid ?? ""}-tournaments`,
  );
  const followKeys = (followed.data ?? []).map((f) => f.key ?? f.id).sort().join(",");
  const [taggable, setTaggable] = useState<TagTournament[]>([]);
  useEffect(() => {
    if (!user || repost) return;
    let live = true;
    callApi<TagTournaments>(user, "/v1/me/tag-tournaments")
      .then((r) => live && setTaggable(r.tournaments))
      .catch(() => live && setTaggable([]));
    return () => {
      live = false;
    };
  }, [user, repost, followKeys]);
  const tagOptions = taggable.map((t) => ({ key: t.key, name: t.name.slice(0, 100) }));
  if (tag && !tagOptions.some((o) => o.key === tag.key)) tagOptions.push(tag);

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

  // Previews are object URLs; free them when they go (the ref sees the
  // photos at unmount, not the first render's).
  const photosRef = useRef(photos);
  photosRef.current = photos;
  useEffect(() => () => photosRef.current.forEach((p) => p.kind === "new" && URL.revokeObjectURL(p.preview)), []);

  if (!user) return null;
  const me = user;
  const imagesMax = team ? teamPostImagesMax : postImagesMax;

  /** Uploads [file] for a post to [target] ("" for Everyone); a result for an older target is dropped. */
  function upload(key: string, file: File, target: string) {
    const opts = target ? { purpose: "teamImage" as const, targetId: target, itemId: postId } : { itemId: postId };
    const settle = (patch: { uploadId?: string; error?: string }) =>
      setPhotos((ps) => ps.map((p) => (p.kind === "new" && p.key === key && p.target === target ? { ...p, ...patch } : p)));
    uploadPhoto(me, file, opts).then(
      (done) => settle({ uploadId: done.id }),
      (e) => settle({ error: problem(e) }),
    );
  }

  function addFiles(list: FileList | File[]) {
    setError(null);
    const room = imagesMax - photos.length;
    const chosen = Array.from(list).slice(0, Math.max(room, 0));
    if (list.length > room) setError(`Add at most ${imagesMax} photos.`);
    const target = team?.id ?? "";
    for (const file of chosen) {
      const bad = photoProblem(file, target ? "teamImage" : "post");
      if (bad) {
        setError(bad);
        continue;
      }
      const key = newId();
      setPhotos((ps) => [...ps, { kind: "new", key, file, target, preview: URL.createObjectURL(file) }]);
      upload(key, file, target);
    }
  }

  /** Changes who the post is for: a team post has no workout or tournament tag, and photos upload again for it. */
  function pickAudience(id: string | null) {
    if (id === teamId) return;
    setTeamId(id);
    setError(null);
    setPosted(null);
    const target = id ?? "";
    if (id) {
      setWorkout(null);
      setTag(null);
    }
    for (const p of photos) if (p.kind === "new") upload(p.key, p.file, target);
    setPhotos((ps) => ps.map((p) => (p.kind === "new" ? { ...p, target, uploadId: undefined, error: undefined } : p)));
  }

  function removePhoto(i: number) {
    setPhotos((ps) => {
      const p = ps[i];
      if (p?.kind === "new") URL.revokeObjectURL(p.preview);
      return ps.filter((_, j) => j !== i);
    });
  }

  const uploading = photos.some((p) => p.kind === "new" && !p.uploadId && !p.error);
  const failedPhoto = photos.some((p) => p.kind === "new" && p.error);
  const empty = !body.trim() && photos.length === 0;
  const tooLong = body.length > postBodyMax;
  // Workout, event and repost posts have more than their words.
  const mayBeEmpty = (!!editing?.kind && editing.kind !== "text") || workout !== null;
  const canPost = !busy && !uploading && !failedPhoto && !tooLong && (mayBeEmpty || !empty);

  function reset() {
    photos.forEach((p) => p.kind === "new" && URL.revokeObjectURL(p.preview));
    setBody("");
    setLinks([]);
    setPhotos([]);
    setWorkout(null);
    setTag(null);
    setTitle("");
    setPlace("");
    setPublic(false);
    setPostId(newId());
  }

  /** A team post, as TeamPostComposer saves it (POST /v1/teams/{id}/posts). */
  async function submitTeam(to: Audience, links: string[]) {
    setBusy(true);
    setError(null);
    setQueued(null);
    const req: SaveTeamPostRequest = {
      title: title.trim(),
      body,
      location: place.trim(),
      links,
      public: !to.privateGroup && isPublic,
      uploadIds: photos.flatMap((p) => (p.kind === "new" && p.uploadId ? [p.uploadId] : [])),
    };
    try {
      const done = await submitOutbox(me, {
        kind: "teamPost",
        id: postId,
        target: to.id,
        label: "Team post",
        path: `/v1/teams/${encodeURIComponent(to.id)}/posts`,
        body: { ...req },
        preview: req.title || body.trim(),
        files: req.uploadIds?.length ?? 0,
      });
      reset();
      if (done === "queued") setQueued(queuedNotice("Team post"));
      else setPosted(to);
      onTeamPosted?.(to.id);
    } catch (err) {
      setError(problem(err));
    } finally {
      setBusy(false);
    }
  }

  async function submit(e?: FormEvent) {
    e?.preventDefault();
    if (!canPost) return;
    // The team picked left the list (no longer managed, or left): never fall
    // back to Everyone, so a members-only post isn't made public.
    if (teamId && !team && !editing) {
      return setError("You can no longer post on that team. Choose who to post to.");
    }
    if (team) return submitTeam(team, links);
    const w = workout ? workoutOf(workout) : undefined;
    if (typeof w === "string") return setError(w);
    setBusy(true);
    setError(null);
    setQueued(null);
    const payload = {
      body,
      links: repost ? [] : links,
      uploadIds: photos.flatMap((p) => (p.kind === "new" && p.uploadId ? [p.uploadId] : [])),
      ...(editing && { keepImages: photos.flatMap((p) => (p.kind === "saved" ? [p.image.path] : [])) }),
      // An edit sends the tag either way (null removes it); a new post only when tagged.
      ...(!repost && (editing || tag) && { tournament: tag }),
    };
    try {
      // Only new posts wait offline; an edit needs the post as it stands.
      let result: SavePostResult;
      if (editing) {
        result = await callApi<SavePostResult>(me, `/v1/posts/${encodeURIComponent(editing.id)}`, {
          method: "PATCH",
          body: payload,
        });
      } else {
        const done = await submitOutbox(me, {
          kind: "userPost",
          id: postId,
          target: "posts",
          label: "Post",
          path: "/v1/posts",
          body: { ...payload, ...(w && { workout: w }) },
          preview: body.trim(),
          files: payload.uploadIds.length,
        });
        if (done === "queued") setQueued(queuedNotice("Post"));
        result = { id: postId, images: [] };
      }
      if (!editing) {
        reset();
        setPosted(null);
      }
      onSaved?.(result, { body: body.trim(), links: payload.links, ...(!repost && { tournament: tag }) });
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
      // The new-post composer (not a post being edited): what `n` and #compose focus.
      data-compose={editing ? undefined : "new"}
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
        {!editing && audiences.length > 0 && (
          <label className="audience-chip">
            <span>To</span>
            <select value={teamId ?? ""} onChange={(e) => pickAudience(e.target.value || null)} disabled={busy}>
              <option value="">Everyone</option>
              {audiences.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </label>
        )}
        {team && (
          <input
            className="composer-title"
            aria-label="Title"
            placeholder="Title (optional)"
            value={title}
            maxLength={100}
            onChange={(e) => setTitle(e.target.value)}
          />
        )}
        <label className="sr-only" htmlFor={`composer-${postId}`}>
          {repost ? "Your note" : team ? `Post to ${team.name}` : "Write a post"}
        </label>
        <textarea
          id={`composer-${postId}`}
          ref={text}
          value={body}
          rows={editing ? 3 : 2}
          placeholder={repost ? "Add a note" : team ? `What's the news for ${team.name}?` : workout ? "How did it go? (optional)" : "What's happening on the field?"}
          onChange={(e) => {
            setBody(e.target.value);
            if (posted) setPosted(null);
          }}
          onPaste={onPaste}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) void submit();
            if (e.key === "Escape" && onCancel) onCancel();
          }}
        />

        {team && (
          <input
            className="composer-place"
            aria-label="Where"
            placeholder="Where (optional)"
            value={place}
            maxLength={200}
            onChange={(e) => setPlace(e.target.value)}
          />
        )}

        {workout && <WorkoutFields draft={workout} onChange={setWorkout} onRemove={() => setWorkout(null)} />}

        <ComposerPhotos
          photos={photos.map((p) =>
            p.kind === "saved"
              ? { kind: "saved", key: p.image.path, path: p.image.path, url: p.image.url, alt: "" }
              : { kind: "new", key: p.key, preview: p.preview, uploading: !p.uploadId && !p.error, error: p.error },
          )}
          onRemove={removePhoto}
        />

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
        {!repost && !team && tagOptions.length > 0 && (
          <label className="composer-tag small">
            At a tournament
            <select
              value={tag?.key ?? ""}
              onChange={(e) => setTag(tagOptions.find((o) => o.key === e.target.value) ?? null)}
            >
              <option value="">None</option>
              {tagOptions.map((o) => (
                <option key={o.key} value={o.key}>
                  {o.name}
                </option>
              ))}
            </select>
          </label>
        )}

        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        {queued && (
          <p className="muted small" role="status">
            {queued}
          </p>
        )}
        {posted && (
          <p className="form-ok" role="status">
            Posted to <Link href={`/teams/${encodeURIComponent(posted.id)}`}>{posted.name}</Link>.
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
                disabled={photos.length >= imagesMax}
                onClick={() => files.current?.click()}
              >
                <PhotoIcon />
                <span>Photo</span>
              </button>
              {!editing && !team && (
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
          {team && !team.privateGroup && (
            <label className="composer-public small" title="Public posts show on the team page to everyone">
              <input type="checkbox" checked={isPublic} onChange={(e) => setPublic(e.target.checked)} /> Public
            </label>
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
          <input inputMode="numeric" value={draft.minutes} placeholder="e.g. 45" onChange={(e) => set({ minutes: digits(e.target.value, 4) })} />
        </label>
        <label>
          Distance (optional)
          <span className="workout-distance">
            <input
              inputMode="decimal"
              value={draft.distance}
              placeholder="e.g. 3.1"
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
              <span className="exercise-head">
                <b>Exercise {i + 1}</b>
                <button
                  type="button"
                  className="exercise-remove"
                  aria-label={`Remove exercise ${i + 1}`}
                  onClick={() => set({ exercises: draft.exercises.filter((_, j) => j !== i) })}
                >
                  ×
                </button>
              </span>
              <input
                className="exercise-name"
                aria-label={`Exercise ${i + 1}`}
                placeholder="What you did, e.g. Squats"
                value={x.name}
                maxLength={60}
                onChange={(e) => setExercise(i, { name: e.target.value })}
              />
              <label>
                Sets
                <input inputMode="numeric" placeholder="e.g. 3" value={x.sets} onChange={(e) => setExercise(i, { sets: digits(e.target.value, 3) })} />
              </label>
              <label>
                Reps
                <input inputMode="numeric" placeholder="e.g. 10" value={x.reps} onChange={(e) => setExercise(i, { reps: digits(e.target.value, 4) })} />
              </label>
              <label>
                Weight
                <input placeholder="e.g. 135 lb" value={x.weight} maxLength={20} onChange={(e) => setExercise(i, { weight: e.target.value })} />
              </label>
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

