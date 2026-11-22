"use client";
import { splitVideoComments, type VideoCommentDoc, videoCommentLimits, videoNoteTime, formatVideoTime } from "@stall10/shared";
import { limit, orderBy, Timestamp, where } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useMemo, useState } from "react";
import { useAuth } from "../../AuthProvider";
import { LocalTime } from "../../LocalTime";
import { callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { DateTile } from "../DateTile";
import { useTeamHub } from "../TeamContext";
import { type TeamEventDoc, typeLabels } from "../TeamSchedule";
import { videosApi } from "./model";
import type { VideoSeeker } from "./VideoPlayer";
import "./videos.css";

// A video page's extras (redesign F4–F6), as the app's video_discussion.dart:
// the event it's tagged to, its notes and clips (click one to play from
// there), and its comments. Writes go through the API.

type Comment = Doc<VideoCommentDoc>;
type TeamEvent = Doc<TeamEventDoc>;

const day = 86_400_000;
const eventHref = (teamId: string, eventId: string) => `/teams/${encodeURIComponent(teamId)}/schedule?event=${encodeURIComponent(eventId)}`;
const eventLine = (e: TeamEventDoc) => typeLabels[e.type ?? ""] ?? "Event";

/** The comments API for a video. */
const commentsApi = (teamId: string, videoId: string) => `${videosApi(teamId)}/${encodeURIComponent(videoId)}/comments`;

/** Notes, clips and comments on a video, live: everything the page needs to list and write them. */
export function useVideoComments(videoId: string) {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const live = useLiveQuery<VideoCommentDoc>(
    member ? `teams/${teamId}/videos/${videoId}/comments` : null,
    [orderBy("createdAt", "desc"), limit(videoCommentLimits.list)],
    `video-comments-${videoId}`,
  );
  const split = useMemo(() => splitVideoComments((live.data ?? []) as Comment[]), [live.data]);
  return { ...split, loading: live.data === undefined && !live.error, error: live.error };
}

/** One write at a time, with its error. */
function useSend() {
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function send(path: string, init: { method: string; body?: unknown }): Promise<boolean> {
    if (!user) return false;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, path, init);
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }
  return { busy, error, send };
}

/** The tagged event (F6), and for admins Tag / Change / Remove. */
export function VideoEventTag({ videoId, eventId }: { videoId: string; eventId?: string }) {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const canTag = !!member && member.can("manageTeam");
  const [picking, setPicking] = useState(false);
  const { busy, error, send } = useSend();
  const tagged = useLiveDoc<TeamEventDoc>(member && eventId ? `teams/${teamId}/events/${eventId}` : null);
  const path = `${videosApi(teamId)}/${encodeURIComponent(videoId)}/event`;
  async function tag(id: string | null) {
    if (await send(path, { method: "PUT", body: { eventId: id } })) setPicking(false);
  }

  const event = tagged.data as TeamEvent | null | undefined;
  return (
    <div className="video-event">
      {eventId ? (
        event ? (
          <Link href={eventHref(teamId, event.id)} className="video-event-link">
            <DateTile startsAt={event.startsAt} />
            <span>
              <span className="muted small">
                {eventLine(event)} · <LocalTime iso={event.startsAt} style="date" />
              </span>
              <b>{event.title || eventLine(event)}</b>
            </span>
          </Link>
        ) : (
          <p className="muted small">{tagged.data === undefined && !tagged.error ? "Loading…" : "Tagged event not available"}</p>
        )
      ) : null}
      {canTag && (
        <div className="video-event-actions">
          <button type="button" className="text-btn" disabled={busy} onClick={() => setPicking((p) => !p)} aria-expanded={picking}>
            {eventId ? "Change event" : "Tag a game or event"}
          </button>
          {eventId && (
            <button type="button" className="text-btn" disabled={busy} onClick={() => void tag(null)}>
              Remove tag
            </button>
          )}
        </div>
      )}
      {picking && <EventPicker current={eventId} busy={busy} onPick={(id) => void tag(id)} />}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

/** The last year's and next month's events, newest first; a community's for everyone only (as the API). */
function EventPicker({ current, busy, onPick }: { current?: string; busy: boolean; onPick: (id: string) => void }) {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const org = member?.team.kind === "organization";
  const since = useMemo(() => Timestamp.fromMillis(Date.now() - 365 * day), []);
  const live = useLiveQuery<TeamEventDoc>(
    member ? `teams/${teamId}/events` : null,
    org
      ? [where("audience", "array-contains", "everyone"), where("startsAt", ">=", since), orderBy("startsAt")]
      : [where("startsAt", ">=", since), orderBy("startsAt", "desc"), limit(300)],
    `video-tag-events-${org}`,
  );
  const until = Date.now() + 31 * day;
  const events = ((live.data ?? []) as TeamEvent[])
    .filter((e) => e.startsAt && Date.parse(e.startsAt) < until)
    .sort((a, b) => (b.startsAt ?? "").localeCompare(a.startsAt ?? ""));
  if (live.error) return <p className="form-error">{live.error}</p>;
  if (live.data === undefined) return <p className="muted small">Loading events…</p>;
  if (events.length === 0) return <p className="muted small">No events from the last year.</p>;
  return (
    <ul className="video-event-picker" aria-label="Pick an event">
      {events.map((e) => (
        <li key={e.id}>
          <button type="button" className={e.id === current ? "on" : ""} disabled={busy} aria-pressed={e.id === current} onClick={() => onPick(e.id)}>
            <DateTile startsAt={e.startsAt} />
            <span>
              <b>{e.title || eventLine(e)}</b>
              <span className="muted small">
                {eventLine(e)} · <LocalTime iso={e.startsAt} style="date" />
              </span>
            </span>
          </button>
        </li>
      ))}
    </ul>
  );
}

/** A note, clip or comment, with Delete for its author and the team's admins. */
function CommentRow({ c, videoId, onPlay }: { c: Comment; videoId: string; onPlay?: () => void }) {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const { busy, error, send } = useSend();
  const mine = !!member && c.authorId === member.uid;
  const canDelete = mine || (!!member && member.can("manageTeam"));
  const note = typeof c.atMs === "number";
  function remove() {
    if (!window.confirm(`Delete this ${note ? "note" : "comment"}? It will be removed for everyone on the team.`)) return;
    void send(`${commentsApi(teamId, videoId)}/${encodeURIComponent(c.id)}`, { method: "DELETE" });
  }
  return (
    <li className="video-comment">
      {note && (
        <button type="button" className="video-time" onClick={onPlay} disabled={!onPlay} title={onPlay ? "Play from here" : undefined}>
          {typeof c.endMs === "number" ? "✂ " : "▶ "}
          {videoNoteTime(c)}
        </button>
      )}
      <div className="video-comment-main">
        <p>{c.body}</p>
        <p className="muted small">
          {c.authorName || "Someone"}
          {c.createdAt && (
            <>
              {" · "}
              <LocalTime iso={c.createdAt} style="date" />
            </>
          )}
          {canDelete && (
            <>
              {" · "}
              <button type="button" className="text-btn" disabled={busy} onClick={remove}>
                Delete
              </button>
            </>
          )}
        </p>
        {error && <p className="form-error">{error}</p>}
      </div>
    </li>
  );
}

/** A one-line composer: Enter posts, Shift+Enter breaks the line. */
function Composer({ placeholder, busy, onPost }: { placeholder: string; busy: boolean; onPost: (body: string) => Promise<boolean> }) {
  const [text, setText] = useState("");
  async function submit(e?: FormEvent) {
    e?.preventDefault();
    const body = text.trim();
    if (!body || busy) return;
    if (await onPost(body)) setText("");
  }
  return (
    <form className="comment-box" onSubmit={(e) => void submit(e)}>
      <textarea
        rows={1}
        value={text}
        maxLength={videoCommentLimits.body}
        placeholder={placeholder}
        aria-label={placeholder}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            void submit();
          }
        }}
      />
      <button type="submit" className="btn btn-primary btn-small" disabled={busy || !text.trim()}>
        Post
      </button>
    </form>
  );
}

/** Notes and clips by time (F4): click one to play from there; members mark a start (and an end for a clip) and add one. */
export function VideoNotes({ videoId, notes, seeker }: { videoId: string; notes: Comment[]; seeker: VideoSeeker | null }) {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member";
  const { busy, error, send } = useSend();
  const [start, setStart] = useState<number | null>(null);
  const [end, setEnd] = useState<number | null>(null);
  // A player that hasn't loaded yet is at the start (as the app); none at all can't be marked.
  const now = () => (seeker ? (seeker.positionMs() ?? 0) : null);
  function markStart() {
    const at = now();
    if (at === null) return;
    setStart(at);
    if (end !== null && end <= at) setEnd(null);
  }
  function markEnd() {
    const at = now();
    if (at === null) return;
    if (start === null) setStart(at);
    else if (at > start) setEnd(at);
  }
  async function post(body: string) {
    const at = start ?? now();
    if (at === null) return false;
    const ok = await send(commentsApi(teamId, videoId), { method: "POST", body: { body, atMs: at, ...(end !== null && end > at && { endMs: end }) } });
    if (ok) {
      setStart(null);
      setEnd(null);
    }
    return ok;
  }
  const compose = member && seeker !== null;
  if (notes.length === 0 && !compose) return null;
  return (
    <section className="card video-notes" aria-labelledby="video-notes-h">
      <h2 id="video-notes-h">Notes{notes.length > 0 && ` · ${notes.length}`}</h2>
      {notes.length === 0 && <p className="muted small">Pin a note to a moment in the video. Click one to play from there.</p>}
      {notes.length > 0 && (
        <ul className="video-comments">
          {notes.map((n) => (
            <CommentRow key={n.id} c={n} videoId={videoId} onPlay={seeker ? () => seeker.playFrom(n.atMs ?? 0) : undefined} />
          ))}
        </ul>
      )}
      {compose && (
        <>
          <div className="video-marks">
            <button type="button" className="video-mark" onClick={markStart}>
              {start === null ? "Mark start" : `At ${formatVideoTime(start)}`}
            </button>
            <button type="button" className={`video-mark${end !== null ? " on" : ""}`} onClick={markEnd}>
              {end === null ? "Mark end (clip)" : `To ${formatVideoTime(end)}`}
            </button>
            {end !== null && (
              <button type="button" className="text-btn" onClick={() => setEnd(null)}>
                No end
              </button>
            )}
          </div>
          <Composer placeholder={start === null ? "Add a note at the current time" : `Add a note at ${formatVideoTime(start)}`} busy={busy} onPost={post} />
        </>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}

/** The comment thread (F5), oldest first. */
export function VideoComments({ videoId, comments }: { videoId: string; comments: Comment[] }) {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member";
  const { busy, error, send } = useSend();
  return (
    <section className="card video-notes" aria-labelledby="video-comments-h">
      <h2 id="video-comments-h">Comments{comments.length > 0 && ` · ${comments.length}`}</h2>
      {comments.length === 0 && <p className="muted small">No comments yet.</p>}
      {comments.length > 0 && (
        <ul className="video-comments">
          {comments.map((c) => (
            <CommentRow key={c.id} c={c} videoId={videoId} />
          ))}
        </ul>
      )}
      {member && <Composer placeholder="Add a comment" busy={busy} onPost={(body) => send(commentsApi(teamId, videoId), { method: "POST", body: { body } })} />}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}
