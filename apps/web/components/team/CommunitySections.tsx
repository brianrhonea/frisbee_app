"use client";
import { chatSectionRooms, communityOrganizers, goingCount, nextEventCardText, roomHandle, type TeamChatSummary } from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { LocalTime } from "../LocalTime";
import { openConversation } from "../MessageButton";
import { DateTile } from "./DateTile";
import { useTeamHub } from "./TeamContext";
import { JoinButton } from "./TeamNav";
import { NeedsPill } from "../RsvpPill";
import type { Room } from "./TeamStatTiles";
import { ErrorNote } from "@/components/StatusViews";

// The community page's own sections (redesign F27), on a pickup
// community's or a school or club's page: the next event with RSVP, the
// chat rooms and the organizers. The app's are in
// apps/mobile/lib/ui/teams/widgets/community_sections.dart.

/** The next event as the feed has it: a member's live doc, or the public copy (no answers). */
export interface PickupEvent {
  id: string;
  title?: string;
  type?: string;
  startsAt?: string;
  endsAt?: string | null;
  location?: string;
  rsvps?: Record<string, string>;
}

const answers: Array<[string, string]> = [
  ["going", "Going"],
  ["maybe", "Maybe"],
  ["notGoing", "Can't go"],
];

/**
 * The community's next event at the top of its feed: date tile, title,
 * time, place and the Going count, with Going / Maybe / Can't go for
 * members (PUT .../rsvp, as the schedule: picking the current answer takes
 * it back, and its note goes with it) and an amber "RSVP needed" while
 * they haven't answered. Outsiders see the event and Join (the banner's
 * button; a group that approves members is private to them, so they never
 * get here); visitors a link to log in. With no event, a quiet "No
 * pickup scheduled" and, for those who add events, New event.
 */
export function NextPickupCard({ event }: { event?: PickupEvent }) {
  const { teamId, kind, viewer } = useTeamHub();
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const text = nextEventCardText(kind);
  const member = viewer.state === "member" ? viewer : null;
  const base = `/teams/${encodeURIComponent(teamId)}`;
  if (!event) {
    if (!member) return null;
    return (
      <div className="card pickup-card pickup-empty">
        <h2 className="card-title">{text.title}</h2>
        <p className="muted small">{text.empty}</p>
        {member.can("manageEvents") && (
          <Link className="btn btn-small" href={`${base}/schedule?new=event`}>
            New event
          </Link>
        )}
      </div>
    );
  }
  const mine = member ? event.rsvps?.[member.uid] : undefined;
  // The feed lists only events that aren't over, so unanswered means it's theirs to do.
  const needs = !!member && !mine;
  async function answer(status: string) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/events/${encodeURIComponent(event!.id)}/rsvp`, {
        method: "PUT",
        body: { status: mine === status ? null : status },
      });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const count = (s: string) => Object.values(event.rsvps ?? {}).filter((x) => x === s).length;
  return (
    <div className="card pickup-card">
      <div className="card-head">
        <h2 className="card-title">{text.title}</h2>
        {needs && <NeedsPill>RSVP needed</NeedsPill>}
      </div>
      <Link className="pickup-event" href={`${base}/schedule?event=${encodeURIComponent(event.id)}`}>
        <DateTile startsAt={event.startsAt} />
        <span className="pickup-info">
          <b>{event.title || "Event"}</b>
          <small>
            <LocalTime iso={event.startsAt} style="dateTime" />
          </small>
          {event.location && <small>{event.location}</small>}
          {/* Outsiders read the public copy, which has no answers. */}
          {member && <small className="pickup-going">{goingCount(event.rsvps)} going</small>}
        </span>
      </Link>
      {member ? (
        <div className={`rsvp-ask${needs ? " needs" : ""}`}>
          <div className="segmented rsvp-buttons" role="group" aria-label="Your answer">
            {answers.map(([status, label]) => (
              <button
                key={status}
                type="button"
                className={mine === status ? "on" : ""}
                aria-pressed={mine === status}
                disabled={busy}
                onClick={() => void answer(status)}
              >
                <span>{label}</span>
                <small className="rsvp-count">{count(status)}</small>
              </button>
            ))}
          </div>
        </div>
      ) : (
        <PickupJoin />
      )}
      {error && (
        <ErrorNote>
          {error}
        </ErrorNote>
      )}
    </div>
  );
}

/** An outsider's way in on the pickup card: the banner's Join / Ask to join; visitors log in first. */
function PickupJoin() {
  const { teamId, privateGroup, viewer } = useTeamHub();
  if (viewer.state === "visitor") {
    return (
      <p className="pickup-join">
        <span className="muted small">Join the community to RSVP.</span>
        <Link className="btn btn-primary btn-small" href={`/sign-in?next=${encodeURIComponent(`/teams/${teamId}`)}`}>
          Log in to join
        </Link>
      </p>
    );
  }
  if (viewer.state !== "outsider") return null;
  return (
    <p className="pickup-join">
      <span className="muted small">{privateGroup ? "Ask to join to RSVP and see who is going." : "Join the community to RSVP."}</span>
      <JoinButton />
    </p>
  );
}

/**
 * The community's chat rooms the member can read ([chat], useTeamChatRooms),
 * unread ones first with an amber dot (theirs to read), each opening its
 * room; All chat opens the chat page.
 */
export function CommunityChat({ chat }: { chat: TeamChatSummary<Room> | undefined }) {
  const { teamId, viewer } = useTeamHub();
  if (viewer.state !== "member") return null;
  const base = `/teams/${encodeURIComponent(teamId)}/chat`;
  const section = chat ? chatSectionRooms(chat) : null;
  return (
    <div className="card community-chat">
      <div className="card-head">
        <h2 className="card-title">Chat rooms</h2>
        <Link className="small" href={base}>
          {section && section.more > 0 ? `All chat (+${section.more})` : "All chat"}
        </Link>
      </div>
      {!section ? (
        <p className="muted small">Loading…</p>
      ) : section.rooms.length === 0 ? (
        <p className="muted small">No rooms yet.</p>
      ) : (
        <ul className="community-rooms">
          {section.rooms.map(({ room, unread }) => (
            <li key={room.id}>
              <Link
                href={`${base}?room=${encodeURIComponent(room.id)}`}
                className={unread ? "unread" : ""}
                aria-label={`#${roomHandle(room.name)}${unread ? ", new messages" : ""}`}
              >
                <span className="room-hash" aria-hidden="true">
                  #
                </span>
                <span className="room-name">{roomHandle(room.name)}</span>
                {unread && <span className="unread-dot" aria-hidden="true" />}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/**
 * The community's owner and those who run it (communityOrganizers: a coach
 * or captain tier, or Manage team, members or events from their roles or
 * their own switches), each with Message (POST /v1/conversations, as a
 * player's page) for everyone but the member themselves.
 */
export function CommunityOrganizers() {
  const { viewer } = useTeamHub();
  if (viewer.state !== "member") return null;
  const people = communityOrganizers(viewer.team);
  if (people.length === 0) return null;
  return (
    <div className="card community-organizers">
      <h2 className="card-title">Organizers</h2>
      <ul className="organizer-list">
        {people.map((p) => (
          <li key={p.uid}>
            <Link className="person" href={`/players/${p.uid}`}>
              <Avatar name={p.name} size={32} />
              <span>
                <b>
                  {p.name}
                  {p.uid === viewer.uid && <small className="muted"> (you)</small>}
                </b>
                <small className="organizer-role">{p.label}</small>
              </span>
            </Link>
            {p.uid !== viewer.uid && <OrganizerMessage uid={p.uid} />}
          </li>
        ))}
      </ul>
    </div>
  );
}

function OrganizerMessage({ uid }: { uid: string }) {
  const { user } = useAuth();
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function open() {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      const res = await openConversation(user, uid);
      router.push(`/messages?c=${encodeURIComponent(res.id)}`);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }
  return (
    <span className="organizer-message">
      <button type="button" className="btn btn-small" disabled={busy} onClick={() => void open()}>
        Message
      </button>
      {error && (
        <span className="form-error small" role="alert">
          {error}
        </span>
      )}
    </span>
  );
}
