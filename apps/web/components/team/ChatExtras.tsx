"use client";
// Pins, event cards and polls in team rooms (redesign F2, F3, F33), as the
// app's chat_extras.dart and chat_polls.dart: the pinned strip with every
// pin a click away, the card a shared event shows as (RSVPs through the
// event's own endpoint), the "Share an event" picker, and poll cards with
// the "Poll" form. Pins, shares and polls are API-only.
import {
  type ChatPoll,
  chatPinsMax,
  chatPollClosed,
  chatPollOptionMax,
  chatPollOptionsMax,
  chatPollOptionsMin,
  chatPollPreview,
  chatPollQuestionMax,
  chatPollTally,
  chatPollToggle,
  sharedEventPreview,
} from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { fromLocalInput } from "@/lib/dates";
import { useAuth } from "../AuthProvider";
import { Dialog } from "../Dialog";
import { LocalTime } from "../LocalTime";
import { needsRsvp, NeedsPill, RsvpPill } from "../RsvpPill";
import { EmptyState, Loading } from "../StatusViews";
import { DateTile } from "./DateTile";
import type { TeamViewer } from "./TeamContext";
import { type TeamEventDoc, useTeamEvents } from "./TeamSchedule";
import "./chat_extras.css";
import { useConfirm } from "@/components/ui/ConfirmDialog";

/** A team room message as the pins and cards need it. */
export interface ExtrasMessage {
  authorName?: string;
  text?: string;
  attachments?: unknown[];
  createdAt?: string;
  event?: { id?: string; title?: string };
  /** A poll asked in the room (F33). */
  poll?: ChatPoll;
  pinnedAt?: string;
}

const roomPath = (teamId: string, roomId: string) => `/v1/teams/${encodeURIComponent(teamId)}/chats/${encodeURIComponent(roomId)}`;
const pinPath = (teamId: string, roomId: string, messageId: string) =>
  `${roomPath(teamId, roomId)}/messages/${encodeURIComponent(messageId)}/pin`;

/** A message's one line: its text, else its event or files (ChatMessage.preview). */
export function previewOf(m: ExtrasMessage): string {
  const t = (m.text ?? "").trim().replace(/\s+/g, " ");
  if (t) return t.length > 120 ? `${t.slice(0, 117)}…` : t;
  if (m.event) return sharedEventPreview(m.event.title ?? "");
  if (m.poll) return chatPollPreview(m.poll.question ?? "");
  const n = m.attachments?.length ?? 0;
  return n === 0 ? "" : n === 1 ? "📎 File" : `📎 ${n} files`;
}

/** The room's pins, newest first: messages with pinnedAt (a deleted one's pin goes with it). */
export function useRoomPins<T extends ExtrasMessage>(teamId: string, roomId: string) {
  return useLiveQuery<T>(`teams/${teamId}/chats/${roomId}/messages`, [orderBy("pinnedAt", "desc"), limit(chatPinsMax)], `pins-${roomId}`);
}

/**
 * Pin, unpin, and pinning into a full room: the API refuses it, and the
 * panel opens asking which pin to take down ([replacing]).
 */
export function usePinActions(teamId: string, roomId: string) {
  const { user } = useAuth();
  const [error, setError] = useState<string | null>(null);
  const [replacing, setReplacing] = useState<string | null>(null);
  async function call(messageId: string, method: "PUT" | "DELETE", body?: unknown) {
    if (!user) return;
    setError(null);
    try {
      await callApi(user, pinPath(teamId, roomId, messageId), { method, body });
      setReplacing(null);
    } catch (e) {
      if (e instanceof ApiError && e.code === "failed_precondition" && method === "PUT") setReplacing(messageId);
      else setError((e as Error).message);
    }
  }
  return {
    error,
    replacing,
    cancelReplace: () => setReplacing(null),
    pin: (id: string) => call(id, "PUT", {}),
    unpin: (id: string) => call(id, "DELETE"),
    /** Pins [replacing] in place of [unpin]. */
    replace: (unpin: string) => (replacing ? call(replacing, "PUT", { unpin }) : Promise.resolve()),
  };
}

/**
 * A room's pins as their own view (the room's ⋯ → Pinned messages, as in
 * Discord; the app's PinnedMessagesScreen): a card each, newest pin first,
 * with the author, date, whole text and files. Clicking one goes back to
 * the chat at that message ([onOpen]); chat managers unpin here.
 */
export function PinnedView({
  pins,
  canPin,
  actions,
  onOpen,
  onBack,
}: {
  pins: Array<Doc<ExtrasMessage>>;
  canPin: boolean;
  actions: ReturnType<typeof usePinActions>;
  onOpen: (messageId: string) => void;
  onBack: () => void;
}) {
  return (
    <div className="pinned-view">
      <div className="pinned-view-head">
        <button type="button" className="text-btn" onClick={onBack}>
          ‹ Back to the chat
        </button>
        <h3>
          Pinned messages <small className="muted">{pins.length} of {chatPinsMax}</small>
        </h3>
      </div>
      {actions.error && <p className="form-error">{actions.error}</p>}
      {pins.length === 0 ? (
        <EmptyState>
          Nothing pinned yet.{" "}
          {canPin ? "Choose Pin on a message to keep it here." : "Coaches and captains pin important messages here."}
        </EmptyState>
      ) : (
        <ul className="pin-cards">
          {pins.map((m) => (
            <li key={m.id} className="pin-card">
              <button type="button" className="pin-card-open" onClick={() => onOpen(m.id)} aria-label={`See this message in the chat: ${previewOf(m)}`}>
                <span className="pin-card-meta">
                  <span className="pin-avatar" aria-hidden="true">
                    {(m.authorName || "M").charAt(0).toUpperCase()}
                  </span>
                  <b>{m.authorName || "Member"}</b>
                  <small className="muted">
                    <LocalTime iso={m.createdAt} />
                  </small>
                </span>
                {(m.text?.trim() || previewOf(m)) && <span className="pin-card-text">{m.text?.trim() ? m.text : previewOf(m)}</span>}
                {files(m).length > 0 && (
                  <span className="pin-card-files">
                    {files(m).map((f, i) => (
                      <span key={`${f.name}-${i}`} className="pin-file">
                        <span aria-hidden="true">{fileIcon(f.contentType)}</span> {f.name}
                      </span>
                    ))}
                  </span>
                )}
                <span className="pin-card-go">See it in the chat →</span>
              </button>
              {canPin && (
                <button type="button" className="text-btn pin-card-unpin" onClick={() => void actions.unpin(m.id)}>
                  Unpin
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** A message's files, as far as the pin cards show them. */
function files(m: ExtrasMessage): Array<{ name: string; contentType: string }> {
  return (m.attachments ?? []).flatMap((a) => {
    const f = a as { name?: unknown; contentType?: unknown };
    return typeof f.name === "string" ? [{ name: f.name, contentType: typeof f.contentType === "string" ? f.contentType : "" }] : [];
  });
}

function fileIcon(type: string): string {
  if (type.startsWith("image/")) return "🖼️";
  if (type.startsWith("video/")) return "🎬";
  return type === "application/pdf" ? "📕" : "📄";
}

/** Pinning into a full room: which pin to take down (usePinActions' replacing), and pin errors. */
export function ReplacePinDialog({ pins, actions }: { pins: Array<Doc<ExtrasMessage>>; actions: ReturnType<typeof usePinActions> }) {
  if (!actions.replacing) return actions.error ? <p className="form-error pinned-error">{actions.error}</p> : null;
  return (
    <Dialog label="Unpin one to pin this" onClose={actions.cancelReplace} className="card pins-dialog" dismissOnBackdrop>
      <h2>Unpin one to pin this</h2>
      <p className="muted small">A room holds {chatPinsMax} pinned messages.</p>
      <ul className="pins-list">
        {pins.map((m) => (
          <li key={m.id}>
            <p className="pin-meta">
              {m.authorName || "Member"} · <LocalTime iso={m.createdAt} />
            </p>
            <p className="pin-text">{m.text?.trim() ? m.text : previewOf(m)}</p>
            <button type="button" className="btn btn-small" onClick={() => void actions.replace(m.id)}>
              Unpin this one
            </button>
          </li>
        ))}
      </ul>
      <div className="form-actions">
        <button type="button" className="btn btn-small" onClick={actions.cancelReplace}>
          Cancel
        </button>
      </div>
    </Dialog>
  );
}

const answers: Array<[string, string]> = [
  ["going", "Going"],
  ["maybe", "Maybe"],
  ["notGoing", "Can't go"],
];

/**
 * A shared event as a card: date tile, title, time and place, the
 * member's answer and the Going count, and Going / Maybe / Can't go
 * (PUT .../rsvp; picking the current answer takes it back, and the note
 * stays). "Event no longer available" when it's deleted or not theirs to see.
 */
export function ChatEventCard({ teamId, eventId, uid }: { teamId: string; eventId: string; uid: string }) {
  const { user } = useAuth();
  const event = useLiveDoc<TeamEventDoc>(`teams/${teamId}/events/${eventId}`);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (event.data === undefined && !event.error) return <div className="chat-event-card muted">Loading event…</div>;
  const e = event.data;
  if (!e) return <div className="chat-event-card gone">Event no longer available</div>;
  const mine = e.rsvps?.[uid];
  const count = (s: string) => Object.values(e.rsvps ?? {}).filter((x) => x === s).length;
  const end = Date.parse(e.endsAt || "") || Date.parse(e.startsAt || "") + 2 * 3600_000;
  const over = !Number.isNaN(end) && end < Date.now();
  const needs = !over && needsRsvp(mine, e.startsAt, e.endsAt);
  async function answer(status: string) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/events/${encodeURIComponent(eventId)}/rsvp`, {
        method: "PUT",
        body: { status: mine === status ? null : status },
      });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="chat-event-card">
      <Link className="chat-event-head" href={`/teams/${teamId}/schedule?event=${encodeURIComponent(eventId)}`}>
        <DateTile startsAt={e.startsAt} />
        <span className="chat-event-info">
          <b>
            <span className="type-dot" aria-hidden="true" />
            {e.title || "Event"}
          </b>
          <small>
            <LocalTime iso={e.startsAt} style="dateTime" />
            {e.location ? ` · ${e.location}` : ""}
          </small>
          <small>
            {count("going")} going{count("maybe") > 0 ? ` · ${count("maybe")} maybe` : ""}
          </small>
        </span>
        {mine && <RsvpPill answer={mine} type={e.type} />}
      </Link>
      {!over && (
        <div className="chat-event-actions">
          {needs && <NeedsPill>RSVP needed</NeedsPill>}
          {answers.map(([status, label]) => (
            <button
              key={status}
              type="button"
              disabled={busy}
              aria-pressed={mine === status}
              className={`btn btn-small${needs && status === "going" ? " btn-amber" : mine === status ? " chosen" : ""}`}
              onClick={() => void answer(status)}
            >
              {label}
            </button>
          ))}
        </div>
      )}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}

/**
 * "Share an event": the team's upcoming events (on a school or club
 * community only those for everyone, as the API checks); picking one
 * posts it into the room as a card.
 */
export function ShareEventDialog({
  teamId,
  roomId,
  viewer,
  onClose,
}: {
  teamId: string;
  roomId: string;
  viewer: TeamViewer;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const events = useTeamEvents(teamId, viewer);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const org = viewer.state === "member" && viewer.team.kind === "organization";
  const list = (events.data ?? []).filter((e) => !org || (e.audience ?? []).includes("everyone"));
  async function share(eventId: string) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `${roomPath(teamId, roomId)}/event-shares`, { method: "POST", body: { eventId } });
      onClose();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Dialog label="Share an event" onClose={onClose} className="card pins-dialog" dismissOnBackdrop>
      <h2>Share an event</h2>
      {events.error ? (
        <p className="form-error">{events.error}</p>
      ) : !events.data ? (
        <Loading label="Loading events…" />
      ) : list.length === 0 ? (
        <EmptyState>{org ? "No upcoming events for everyone." : "No upcoming events."}</EmptyState>
      ) : (
        <ul className="share-event-list">
          {list.map((e) => (
            <li key={e.id}>
              <button type="button" disabled={busy} onClick={() => void share(e.id)}>
                <DateTile startsAt={e.startsAt} />
                <span>
                  <b>{e.title || "Event"}</b>
                  <small>
                    <LocalTime iso={e.startsAt} style="dateTime" />
                    {e.location ? ` · ${e.location}` : ""}
                  </small>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
      {error && <p className="form-error">{error}</p>}
      <div className="form-actions">
        <button type="button" className="btn btn-small" onClick={onClose}>
          Cancel
        </button>
      </div>
    </Dialog>
  );
}

/**
 * A poll asked in the room (F33), as a card: the question, each option
 * with its count and bar (the viewer's picks marked), the total, and "Poll
 * closed" once it's over. Click an option to vote, again to take it back
 * (a single-choice poll swaps). "See votes" lists who picked what: votes
 * aren't anonymous. The card listens to its own message, since older pages
 * of a thread aren't live.
 */
export function ChatPollCard({
  teamId,
  roomId,
  messageId,
  authorId,
  initial,
  uid,
  canManage,
  nameOf,
}: {
  teamId: string;
  roomId: string;
  messageId: string;
  authorId?: string;
  initial: ChatPoll;
  uid: string;
  /** The owner and chat managers close anyone's poll. */
  canManage: boolean;
  nameOf: (uid: string) => string;
}) {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const live = useLiveDoc<{ poll?: ChatPoll }>(`teams/${teamId}/chats/${roomId}/messages/${messageId}`);
  const [sending, setSending] = useState<number[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [voters, setVoters] = useState(false);
  // The vote being sent has landed (or someone else's change has).
  useEffect(() => setSending(null), [live.data]);
  if (live.data === null) return <div className="chat-event-card gone">Poll no longer available</div>;
  const poll = live.data?.poll ?? initial;
  const options = poll.options ?? [];
  const mine = sending ?? poll.votes?.[uid] ?? [];
  // Counts the viewer's choice as sent.
  const { counts, voters: total } = chatPollTally({ options, votes: { ...(poll.votes ?? {}), [uid]: mine } });
  const closed = chatPollClosed(poll, Date.now());
  const needs = !closed && mine.length === 0;
  const canClose = !closed && (authorId === uid || canManage);
  const path = `${roomPath(teamId, roomId)}/messages/${encodeURIComponent(messageId)}`;
  async function run(fn: () => Promise<unknown>): Promise<boolean> {
    setBusy(true);
    setError(null);
    try {
      await fn();
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }
  function vote(i: number) {
    if (!user || closed || busy) return;
    const next = chatPollToggle(mine, i, poll.multiple === true);
    setSending(next);
    // On success the choice stays shown until the live message brings it back, so it doesn't flash back.
    void run(() => callApi(user, `${path}/vote`, { method: "PUT", body: { options: next } })).then((ok) => {
      if (!ok) setSending(null);
    });
  }
  async function close() {
    if (!user || !(await askConfirm({ message: "Close this poll? Nobody can vote or change their vote after.", confirmLabel: "Close", destructive: true }))) return;
    void run(() => callApi(user, `${path}/close-poll`, { method: "POST", body: {} }));
  }
  const votersOf = (i: number) =>
    Object.entries(poll.votes ?? {})
      .filter(([, v]) => Array.isArray(v) && v.includes(i))
      .map(([u]) => nameOf(u))
      .sort((a, b) => a.localeCompare(b));
  return (
    <div className="chat-event-card chat-poll-card">
      <p className="chat-poll-head">
        <b>📊 Poll · {poll.multiple ? "pick any" : "pick one"}</b>
        {needs && <NeedsPill>Vote</NeedsPill>}
      </p>
      <p className="chat-poll-question">{poll.question || "Poll"}</p>
      <div className="chat-poll-options">
        {options.map((o, i) => {
          const picked = mine.includes(i);
          const pct = total ? Math.round((counts[i] / total) * 100) : 0;
          return (
            <button
              key={i}
              type="button"
              className={`poll-option${picked ? " on" : ""}`}
              disabled={closed || busy}
              aria-pressed={picked}
              onClick={() => vote(i)}
            >
              <span className="poll-bar" style={{ width: `${pct}%` }} />
              <span>
                {picked ? "✓ " : ""}
                {o}
              </span>
              <b>{counts[i]}</b>
            </button>
          );
        })}
      </div>
      <div className="chat-poll-foot">
        <small>
          {total === 1 ? "1 vote" : `${total} votes`}
          {closed ? (
            " · Poll closed"
          ) : poll.closesAt ? (
            <>
              {" · Closes "}
              <LocalTime iso={poll.closesAt} style="dateTime" />
            </>
          ) : null}
        </small>
        {total > 0 && (
          <button type="button" className="text-btn" aria-expanded={voters} onClick={() => setVoters(!voters)}>
            {voters ? "Hide votes" : "See votes"}
          </button>
        )}
        {canClose && (
          <button type="button" className="text-btn" disabled={busy} onClick={close}>
            Close poll
          </button>
        )}
      </div>
      {voters && (
        <ul className="chat-poll-voters">
          {options.map((o, i) => {
            const names = votersOf(i);
            return (
              <li key={i}>
                <b>
                  {o} · {names.length}
                </b>
                <span>{names.length ? names.join(", ") : "No votes"}</span>
              </li>
            );
          })}
        </ul>
      )}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}

/**
 * "Poll" in a room's attach menu (F33): a question, 2–6 options, "Allow
 * multiple answers" and an optional closing time, checked as the API
 * checks them; posting adds it to the room as a card.
 */
export function CreatePollDialog({ teamId, roomId, onClose }: { teamId: string; roomId: string; onClose: () => void }) {
  const { user } = useAuth();
  const [question, setQuestion] = useState("");
  const [options, setOptions] = useState(() => [
    { id: 0, text: "" },
    { id: 1, text: "" },
  ]);
  const [nextId, setNextId] = useState(2);
  const [multiple, setMultiple] = useState(false);
  const [closesAt, setClosesAt] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const texts = options.map((o) => o.text.trim());
  const closes = fromLocalInput(closesAt);
  const problem = !question.trim()
    ? "Ask a question."
    : texts.some((t) => !t)
      ? "Fill in every option, or remove it."
      : new Set(texts.map((t) => t.toLowerCase())).size !== texts.length
        ? "Each option must be different."
        : closes && Date.parse(closes) <= Date.now()
          ? "Pick a closing time in the future."
          : null;
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!user || problem) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `${roomPath(teamId, roomId)}/polls`, {
        method: "POST",
        body: { question: question.trim(), options: texts, multiple, ...(closes && { closesAt: closes }) },
      });
      onClose();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Dialog label="New poll" onClose={onClose} className="card pins-dialog" dismissOnBackdrop>
      <form className="chat-poll-form" onSubmit={(e) => void submit(e)}>
        <h2>New poll</h2>
        <label>
          Question
          <input value={question} required maxLength={chatPollQuestionMax} autoFocus onChange={(e) => setQuestion(e.target.value)} />
        </label>
        {options.map((o, i) => (
          <div key={o.id} className="input-row">
            <input
              aria-label={`Option ${i + 1}`}
              placeholder={`Option ${i + 1}`}
              value={o.text}
              maxLength={chatPollOptionMax}
              onChange={(e) => setOptions(options.map((x) => (x.id === o.id ? { ...x, text: e.target.value } : x)))}
            />
            {options.length > chatPollOptionsMin && (
              <button type="button" className="text-btn" onClick={() => setOptions(options.filter((x) => x.id !== o.id))}>
                Remove
              </button>
            )}
          </div>
        ))}
        {options.length < chatPollOptionsMax && (
          <p>
            <button
              type="button"
              className="btn btn-small"
              onClick={() => {
                setOptions([...options, { id: nextId, text: "" }]);
                setNextId(nextId + 1);
              }}
            >
              Add option
            </button>
          </p>
        )}
        <label className="switch-row">
          <input type="checkbox" checked={multiple} onChange={(e) => setMultiple(e.target.checked)} /> Allow multiple answers
        </label>
        <label>
          Closes <small className="muted">(optional; otherwise when someone closes it)</small>
          <input type="datetime-local" value={closesAt} onChange={(e) => setClosesAt(e.target.value)} />
        </label>
        {problem && question.trim() && texts.every(Boolean) && <p className="form-error">{problem}</p>}
        {error && <p className="form-error">{error}</p>}
        <p className="muted small">Everyone in the room sees who voted for what.</p>
        <div className="form-actions">
          <button type="button" className="btn btn-small" onClick={onClose}>
            Cancel
          </button>
          <button type="submit" className="btn btn-primary btn-small" disabled={busy || problem !== null}>
            {busy ? "Posting…" : "Post poll"}
          </button>
        </div>
      </form>
    </Dialog>
  );
}
