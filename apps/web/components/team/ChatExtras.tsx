"use client";
// Pins and event cards in team rooms (redesign F2, F3), as the app's
// chat_extras.dart: the pinned strip with every pin a click away, the
// card a shared event shows as (RSVPs through the event's own endpoint),
// and the "Share an event" picker. Pins and shares are API-only.
import { chatPinsMax, sharedEventPreview } from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import Link from "next/link";
import { useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Dialog } from "../Dialog";
import { LocalTime } from "../LocalTime";
import { needsRsvp, RsvpPill } from "../RsvpPill";
import { EmptyState, Loading } from "../StatusViews";
import { DateTile } from "./DateTile";
import type { TeamViewer } from "./TeamContext";
import { type TeamEventDoc, useTeamEvents } from "./TeamSchedule";
import "./chat_extras.css";

/** A team room message as the pins and cards need it. */
export interface ExtrasMessage {
  authorName?: string;
  text?: string;
  attachments?: unknown[];
  createdAt?: string;
  event?: { id?: string; title?: string };
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

/** The strip at the top of a room: the newest pin; click for every pin. */
export function PinnedStrip({
  pins,
  canPin,
  actions,
}: {
  pins: Array<Doc<ExtrasMessage>>;
  canPin: boolean;
  actions: ReturnType<typeof usePinActions>;
}) {
  const [open, setOpen] = useState(false);
  const latest = pins[0];
  return (
    <>
      {latest && (
        <button type="button" className="pinned-strip" onClick={() => setOpen(true)} aria-label={`Pinned messages, ${pins.length}`}>
          <span className="pinned-icon" aria-hidden="true">
            📌
          </span>
          <span className="pinned-text">
            <b>{pins.length > 1 ? `Pinned · ${pins.length}` : "Pinned"}</b>
            <span>
              {latest.authorName || "Member"}: {previewOf(latest)}
            </span>
          </span>
          <span aria-hidden="true">›</span>
        </button>
      )}
      {actions.error && <p className="form-error pinned-error">{actions.error}</p>}
      {(open || actions.replacing) && (
        <Dialog
          label={actions.replacing ? "Unpin one to pin this" : "Pinned messages"}
          onClose={() => {
            setOpen(false);
            actions.cancelReplace();
          }}
          className="card pins-dialog"
          dismissOnBackdrop
        >
          <h2>{actions.replacing ? "Unpin one to pin this" : "Pinned messages"}</h2>
          {actions.replacing && <p className="muted small">A room holds {chatPinsMax} pinned messages.</p>}
          {pins.length === 0 ? (
            <EmptyState>Nothing is pinned.</EmptyState>
          ) : (
            <ul className="pins-list">
              {pins.map((m) => (
                <li key={m.id}>
                  <p className="pin-meta">
                    {m.authorName || "Member"} · <LocalTime iso={m.createdAt} />
                  </p>
                  {/* The whole text: opening the message in a paged thread isn't cheap. */}
                  <p className="pin-text">{m.text?.trim() ? m.text : previewOf(m)}</p>
                  {actions.replacing ? (
                    <button type="button" className="btn btn-small" onClick={() => void actions.replace(m.id)}>
                      Unpin this one
                    </button>
                  ) : (
                    canPin && (
                      <button type="button" className="text-btn" onClick={() => void actions.unpin(m.id)}>
                        Unpin
                      </button>
                    )
                  )}
                </li>
              ))}
            </ul>
          )}
          <div className="form-actions">
            <button
              type="button"
              className="btn btn-small"
              onClick={() => {
                setOpen(false);
                actions.cancelReplace();
              }}
            >
              Close
            </button>
          </div>
        </Dialog>
      )}
    </>
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
          {needs && <span className="rsvp-pill needs">RSVP needed</span>}
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
