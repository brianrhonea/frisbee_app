"use client";
import type { PublicEvent, PublicTeamPost, Series } from "@stall10/shared";
import { Directions } from "../Directions";
import { RepeatNote, scopeQuery, useSeriesScope } from "../Repeat";
import { limit, orderBy, type QueryConstraint, Timestamp, where } from "firebase/firestore";
import { eventReactions, scheduleEntryOver } from "@stall10/shared";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useRef, useState } from "react";
import { useAuth } from "../AuthProvider";
import { LocalTime } from "../LocalTime";
import { AddToCalendar } from "../AddToCalendar";
import { callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQueries, useLiveQuery } from "@/lib/live";
import { type Meeting, meetingHref, meetingsHref, useTeamMeetings } from "./meetings/model";
import { type TeamViewer, useTeamHub, viewerSectionOn } from "./TeamContext";
import { TeamEventEditor } from "./TeamEventEditor";
import { EventVideos } from "./videos/EventVideos";
import { DateTile, isToday } from "./DateTile";
import { needsRsvp, NeedsPill, RsvpPill } from "../RsvpPill";
import { NoteQuote, RsvpNoteField } from "../RsvpNote";
import "./team_schedule_meetings.css";
import { startOfToday } from "@/lib/dates";
import { validId } from "@/lib/text";
import { EmptyState, Loading } from "../StatusViews";
import { useConfirm } from "@/components/ui/ConfirmDialog";

/** A team event as members read it (TeamEvent in the app). */
export interface TeamEventDoc extends PublicEvent {
  poll?: { question?: string; options?: Array<{ id: string; text: string }>; multiple?: boolean };
  rsvps?: Record<string, string>;
  /** uid → a short note on their answer ("Late 15 min"), only while they have one. */
  rsvpNotes?: Record<string, string>;
  votes?: Record<string, string[]>;
  reactions?: Record<string, string[]>;
  public?: boolean;
  audience?: string[];
  tournamentId?: string;
  /** Its place in a repeating series (recurrence.ts in packages/shared). */
  series?: Series;
}

export const typeLabels: Record<string, string> = {
  practice: "Practice",
  game: "Game",
  tournament: "Tournament",
  scrimmage: "Scrimmage",
  workout: "Workout",
  social: "Social",
  other: "Other",
  pickup: "Pickup",
};
const rsvpLabels: Array<[string, string, string]> = [
  ["going", "Going", "Attending"],
  ["maybe", "Maybe", "Planning to attend"],
  ["notGoing", "Can't go", "Can't make it"],
];
const reactionEmoji: Record<string, string> = { thumbsUp: "👍", fire: "🔥", disc: "🥏", clap: "🙌", laugh: "😂", grimace: "😬" };


/**
 * The Firestore reads for a member's events: upcoming ones from today
 * (or, for [past], ones before tomorrow). An organization's events say who
 * sees them, so a member without manageEvents asks once per audience id,
 * as the app does; teams and groups show every event to every member.
 * [lookBackDays] starts upcoming reads that many days before today, so
 * multi-day events under way stay in (MySchedule.lookBack). [key] names
 * the set for useLiveQueries. Shared with My schedule.
 *
 * Every read is bounded: the first [upcomingEventCap] upcoming events, and
 * the past a page at a time ([pages]): the newest [pastEventCap] per page,
 * or, for an organization's audiences (whose index is ascending only, so a
 * limit would keep the oldest), [pastWindowDays] more days per page.
 */
export function teamEventQueries(member: Extract<TeamViewer, { state: "member" }>, past = false, lookBackDays = 0, pages = 1) {
  const today = Timestamp.fromDate(startOfToday());
  const since = lookBackDays > 0 ? Timestamp.fromMillis(today.toMillis() - lookBackDays * day) : today;
  const scoped = member.team.kind === "organization" && !member.can("manageEvents");
  const tomorrow = Timestamp.fromMillis(today.toMillis() + day);
  const range: QueryConstraint[] = !past
    ? [where("startsAt", ">=", since), orderBy("startsAt"), limit(upcomingEventCap)]
    : scoped
      ? [where("startsAt", ">=", Timestamp.fromMillis(today.toMillis() - pages * pastWindowDays * day)), where("startsAt", "<", tomorrow), orderBy("startsAt")]
      : [where("startsAt", "<", tomorrow), orderBy("startsAt", "desc"), limit(pages * pastEventCap)];
  const queries = scoped ? member.audience.map((id) => [where("audience", "array-contains", id), ...range]) : [range];
  const key = `${past}|${scoped ? member.audience.join(",") : "all"}|${since.seconds}|${past ? pages : 0}`;
  return { queries, key, scoped };
}

/** How many upcoming events a team's schedule reads; past ones come a page at a time. */
const upcomingEventCap = 200;
const pastEventCap = 50;
const pastWindowDays = 90;
/** An organization's past goes back at most this many windows (about five years). */
const pastWindowsMax = 20;

/**
 * A member's events that haven't finished (or have, newest first, for
 * [past]), live: as the app's upcomingEvents, an event is over at its end,
 * or two hours after it starts without one (scheduleEntryOver). Null for
 * non-members. The past comes [pages] pages at a time; [more] when there
 * may be earlier ones, and the last pages stay while the next loads.
 */
export function useTeamEvents(teamId: string, viewer: TeamViewer, past = false, pages = 1) {
  const member = viewer.state === "member" ? viewer : null;
  const { queries, key, scoped } = member ? teamEventQueries(member, past, 0, pages) : { queries: [], key: "", scoped: false };
  const path = member ? `teams/${teamId}/events` : null;
  const live = useLiveQueries<TeamEventDoc>(path, queries, key);
  // Keep what's showing while a bigger page of the past loads.
  const base = `${path}|${past}`;
  const last = useRef<{ base: string; data: Array<Doc<TeamEventDoc>> } | null>(null);
  if (live.data !== undefined) last.current = { base, data: live.data };
  const data = live.data ?? (last.current?.base === base ? last.current.data : undefined);
  const now = Date.now();
  const sorted = data
    ?.filter((e) => scheduleEntryOver(e.startsAt, e.endsAt, now) === past)
    .sort((a, b) => (a.startsAt ?? "").localeCompare(b.startsAt ?? "") * (past ? -1 : 1));
  const more = past && data !== undefined && (scoped ? pages < pastWindowsMax : data.length >= pages * pastEventCap);
  return { ...live, data: sorted, more, loadingMore: live.data === undefined && data !== undefined && !live.error };
}

/**
 * The member's meetings for the schedule, as the app's team schedule lists
 * them beside events: not ended ones only; live ones are upcoming, others
 * are over at their end, or two hours after they start.
 */
export function scheduleMeetings(all: Meeting[] | undefined, past: boolean): Meeting[] {
  const now = Date.now();
  return (all ?? [])
    .filter((m) => m.status !== "ended" && !!m.startsAt)
    .filter((m) => (m.status !== "live" && scheduleEntryOver(m.startsAt, m.endsAt, now)) === past)
    .sort((a, b) => a.startsAt!.localeCompare(b.startsAt!) * (past ? -1 : 1));
}

const day = 86_400_000;

/** What visitors see in place of a youth team's posts and schedule (the app says the same). */
export const youthVisitorNote = "Youth teams share their posts and schedule with members only.";

/**
 * A youth team's public posts (the feed's; [eventLimit] events only, for
 * the schedule) and upcoming public events for someone signed in who isn't
 * on it, read live as the app reads them: the server-rendered public page
 * leaves them out, since visitors get a youth team's card only.
 */
export function useYouthOutsiderPublic(teamId: string, on: boolean, opts: { posts: boolean; eventLimit: number }) {
  const [since] = useState(() => Timestamp.fromMillis(Date.now()));
  const posts = useLiveQuery<PublicTeamPost>(
    on && opts.posts ? `teams/${teamId}/posts` : null,
    [where("public", "==", true), orderBy("createdAt", "desc"), limit(30)],
    "public-feed",
  );
  const events = useLiveQuery<PublicEvent>(
    on ? `teams/${teamId}/publicEvents` : null,
    [where("startsAt", ">=", since), orderBy("startsAt"), limit(opts.eventLimit)],
    `public-events-${opts.eventLimit}`,
  );
  return { posts, events };
}

type Entry = { kind: "event"; event: Doc<TeamEventDoc> } | { kind: "meeting"; meeting: Meeting };
const entryStart = (x: Entry) => (x.kind === "event" ? x.event.startsAt : x.meeting.startsAt) ?? "";

/** The schedule: events and meetings down the left, the open event (?event=) beside them; a meeting opens its own page. */
export function TeamSchedule({ publicEvents }: { publicEvents: PublicEvent[] }) {
  const { teamId, kind, privateGroup, privatePage, youth, viewer } = useTeamHub();
  const params = useSearchParams();
  const pathname = usePathname();
  const past = params.get("when") === "past";
  // A youth team's upcoming public events, live, for someone signed in who isn't on it (not while its page is off).
  const outsiderYouth = youth && !privatePage && viewer.state === "outsider";
  const outsider = useYouthOutsiderPublic(teamId, outsiderYouth && !past, { posts: false, eventLimit: upcomingEventCap });
  // Pages of the past shown; back to one on switching tabs.
  const [pastPages, setPastPages] = useState({ past, n: 1 });
  const pages = pastPages.past === past ? pastPages.n : 1;
  const live = useTeamEvents(teamId, viewer, past, pages);
  const meetings = useTeamMeetings(teamId, viewer);
  const member = viewer.state === "member" ? viewer : null;
  const router = useRouter();
  const [editing, setEditing] = useState<string | null>(null);
  const manager = member?.can("manageEvents") ?? false;
  // ?new=event (the community page's New event, F27) opens the editor for those who add events.
  const shownEditor = editing ?? (manager && params.get("new") === "event" ? "new" : null);
  // ?event= for an event that isn't in the list showing (a past one, say): read it by id.
  const wanted = validId(params.get("event"));
  const listed = !!wanted && (member ? (live.data ?? []) : publicEvents).some((e) => e.id === wanted);
  const linked = useLiveDoc<TeamEventDoc>(member && wanted && live.data && !listed ? `teams/${teamId}/events/${wanted}` : null);

  if (viewer.state === "loading") return <Loading />;
  if (!member && privateGroup) {
    return <EmptyState>Only members see this community&apos;s events.</EmptyState>;
  }
  if (!member && privatePage) {
    return <EmptyState>This team&apos;s page is private. Only members see its events.</EmptyState>;
  }
  // Signed out: a youth team's card only.
  if (youth && viewer.state === "visitor") return <EmptyState>{youthVisitorNote}</EmptyState>;
  if (live.error) return <p className="form-error">{live.error}</p>;
  const events: Array<Doc<TeamEventDoc>> = member ? (live.data ?? []) : outsiderYouth ? ((past ? [] : outsider.events.data) ?? []) : publicEvents;
  if (member && !live.data) return <Loading label="Loading the schedule…" />;

  const entries: Entry[] = [
    ...events.map((event) => ({ kind: "event" as const, event })),
    ...(member ? scheduleMeetings(meetings.data, past).map((meeting) => ({ kind: "meeting" as const, meeting })) : []),
  ].sort((a, b) => entryStart(a).localeCompare(entryStart(b)) * (past ? -1 : 1));
  const openId = wanted ?? events[0]?.id;
  const open = events.find((e) => e.id === openId) ?? (linked.data && linked.data.id === wanted ? linked.data : undefined);
  const link = (q: Record<string, string | null>) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(q)) v === null ? next.delete(k) : next.set(k, v);
    const s = next.toString();
    return s ? `${pathname}?${s}` : pathname;
  };

  return (
    <div className="hub-split sched-split">
      <div className="hub-list">
        {(manager || member) && (
          <div className="sched-tools">
            {member && (
              <div className="segmented" role="tablist" aria-label="Show">
                <Link href={link({ when: null, event: null })} className={past ? "" : "on"} aria-selected={!past} role="tab">
                  Upcoming
                </Link>
                <Link href={link({ when: "past", event: null })} className={past ? "on" : ""} aria-selected={past} role="tab">
                  Past
                </Link>
              </div>
            )}
            {manager && (
              <p className="schedule-new">
                <button type="button" className="btn btn-primary btn-small" onClick={() => setEditing("new")}>
                  New event
                </button>
                {/* The app's New → Meeting; the API lets the same admins schedule meetings. With Meetings off (Settings › Sections) New adds an event only. */}
                {viewerSectionOn(viewer, "meetings") && (
                  <Link className="btn btn-small btn-quiet" href={`${meetingsHref(teamId)}/new`}>
                    New meeting
                  </Link>
                )}
              </p>
            )}
          </div>
        )}
        {entries.length === 0 ? (
          <EmptyState>{past ? "No past events." : "Nothing scheduled."}</EmptyState>
        ) : (
          <div className="card sched-card">
            <ul className="hub-items sched-list">
              {entries.map((x) => {
                if (x.kind === "meeting") return <MeetingItem key={`m-${x.meeting.id}`} teamId={teamId} meeting={x.meeting} />;
                const e = x.event;
                const on = e.id === open?.id;
                return (
                  <li key={e.id}>
                    <Link
                      href={link({ event: e.id })}
                      scroll={false}
                      className={`team-sched-row${on ? " active" : ""}${isToday(e.startsAt) ? " today" : ""}`}
                      aria-current={on ? "true" : undefined}
                    >
                      <DateTile startsAt={e.startsAt} />
                      <span className="sched-main">
                        <b>
                          <span className="type-dot" aria-hidden="true" />
                          {e.title || typeLabels[e.type ?? ""] || "Event"}
                        </b>
                        <small>
                          <LocalTime iso={e.startsAt} style="dateTime" />
                          {e.location ? ` · ${e.location}` : ""}
                        </small>
                      </span>
                      {member && <RsvpLine event={e} uid={member.uid} past={past} />}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        )}
        {live.more && (
          <div className="pager">
            <button type="button" className="btn btn-small" disabled={live.loadingMore} onClick={() => setPastPages({ past, n: pages + 1 })}>
              {live.loadingMore ? "Loading…" : "Earlier events"}
            </button>
          </div>
        )}
        {!member && (
          <p className="muted small">
            {viewer.state === "visitor" ? "Members see the full schedule." : `Only ${kind === "team" ? "the team's" : "the community's"} public events show here.`}
          </p>
        )}
      </div>
      <div className="hub-detail">
        {shownEditor ? (
          <TeamEventEditor
            event={shownEditor === "new" ? undefined : (events.find((e) => e.id === shownEditor) ?? (open?.id === shownEditor ? open : undefined))}
            onDone={(id) => {
              setEditing(null);
              if (id) router.replace(link({ event: id, new: null }), { scroll: false });
              else if (params.get("new")) router.replace(link({ new: null }), { scroll: false });
            }}
          />
        ) : open ? (
          <EventDetail event={open} onEdit={manager ? () => setEditing(open.id) : undefined} />
        ) : null}
      </div>
    </div>
  );
}

/** A meeting in the schedule (TeamMeeting.toEvent): "Live now" or "Video meeting", opening the meeting's page. */
function MeetingItem({ teamId, meeting }: { teamId: string; meeting: Meeting }) {
  const live = meeting.status === "live";
  return (
    <li className="schedule-meeting">
      <Link href={meetingHref(teamId, meeting.id)} className={`team-sched-row${live ? " today" : ""}`}>
        <DateTile startsAt={meeting.startsAt} />
        <span className="sched-main">
          <b>
            <span className="type-dot" aria-hidden="true" />
            {meeting.title || "Meeting"}
          </b>
          <small>
            <LocalTime iso={meeting.startsAt} style="dateTime" />
            {" · "}
            <span className={live ? "schedule-meeting-live" : ""}>{live ? "Live now" : "Video meeting"}</span>
          </small>
        </span>
      </Link>
    </li>
  );
}

/**
 * A row's answers: how many are going and the member's own answer as a
 * pill (the app's RsvpStatusPill): Going in turf, others neutral, and
 * "Needs RSVP" in amber only on an upcoming event they haven't answered.
 */
function RsvpLine({ event, uid, past }: { event: TeamEventDoc; uid: string; past: boolean }) {
  const mine = event.rsvps?.[uid];
  const going = Object.values(event.rsvps ?? {}).filter((s) => s === "going").length;
  return (
    <span className="rsvp-line">
      <small>{going} going</small>
      <RsvpPill answer={mine} type={event.type} needs={!past && needsRsvp(mine, event.startsAt, event.endsAt)} />
    </span>
  );
}

function EventDetail({ event, onEdit }: { event: Doc<TeamEventDoc>; onEdit?: () => void }) {
  const askConfirm = useConfirm();
  const { viewer, teamId } = useTeamHub();
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const base = `/v1/teams/${encodeURIComponent(teamId)}/events/${encodeURIComponent(event.id)}`;
  const scope = useSeriesScope();
  async function send(path: string, method: "PUT" | "DELETE", body?: unknown) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `${base}${path}`, { method, body });
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const member = viewer.state === "member" ? viewer : null;
  const names = member?.team.memberNames ?? {};
  const name = (uid: string) => (uid === member?.uid ? "You" : names[uid] || "Member");
  const tournament = event.type === "tournament";
  const options = event.poll?.options ?? [];
  const voters = new Set(Object.entries(event.votes ?? {}).filter(([, v]) => v.some((id) => options.some((o) => o.id === id))).map(([u]) => u));
  const tally = Object.entries(reactionEmoji)
    .map(([r, emoji]) => [emoji, Object.values(event.reactions ?? {}).filter((s) => s.includes(r)).length] as const)
    .filter(([, n]) => n > 0);

  const mine = member ? event.rsvps?.[member.uid] : undefined;
  const going = mine === "going";
  // "Needs RSVP" (amber) only while it's the member's to answer: unanswered and not over.
  const unanswered = !!member && !mine && !scheduleEntryOver(event.startsAt, event.endsAt, Date.now());
  const myReactions = member ? (event.reactions?.[member.uid] ?? []) : [];
  const myVotes = member ? (event.votes?.[member.uid] ?? []) : [];
  function vote(id: string) {
    const picked = myVotes.includes(id);
    const next = event.poll?.multiple ? (picked ? myVotes.filter((v) => v !== id) : [...myVotes, id]) : picked ? [] : [id];
    void send("/votes", "PUT", { optionIds: next });
  }

  return (
    <article className="card event-detail">
      {scope.dialog}
      <div className="event-detail-head">
        <p className="pill type-chip">
          <span className="type-dot" aria-hidden="true" />
          {typeLabels[event.type ?? ""] ?? "Event"}
        </p>
        {onEdit && (
          <span className="post-admin">
            {!event.tournamentId && (
              <button type="button" className="btn btn-small btn-quiet" onClick={onEdit}>
                Edit
              </button>
            )}
            <button
              type="button"
              className="btn btn-small btn-quiet"
              disabled={busy}
              onClick={async () => {
                // A repeating event: this one, or it and every later one.
                if (event.series) {
                  void scope.ask(`Delete "${event.title || "Event"}"?`, "Delete").then((which) => which && void send(scopeQuery(which), "DELETE"));
                } else if ((await askConfirm({ message: "Delete this event for everyone?", confirmLabel: "Delete", destructive: true }))) void send("", "DELETE");
              }}
            >
              Delete
            </button>
          </span>
        )}
      </div>
      <h2>{event.title || "Event"}</h2>
      <p className="muted">
        <LocalTime iso={event.startsAt} style="dateTime" />
        {event.endsAt && (
          <>
            {" – "}
            <LocalTime iso={event.endsAt} style="dateTime" />
          </>
        )}
      </p>
      {event.location && (
        <p className="event-place">
          <span>{event.location}</span>
          <Directions to={event.location} />
        </p>
      )}
      {event.notes && (
        <div className="event-notes">
          <h3>Notes</h3>
          <p className="post-body">{event.notes}</p>
        </div>
      )}
      {event.startsAt && (
        <div className="event-cal">
          <AddToCalendar
            event={{
              uid: `team-${teamId}-${event.id}@stall10.app`,
              title: event.title || typeLabels[event.type ?? ""] || "Event",
              startsAt: event.startsAt,
              endsAt: event.endsAt,
              location: event.location,
              description: event.notes,
            }}
          />
        </div>
      )}

      <EventTournamentLink event={event} />
      <EventVideos eventId={event.id} />

      {member && (
        <>
          <div className={`rsvp-ask${unanswered ? " needs" : ""}`}>
            <p className="rsvp-ask-title">
              Are you in?
              {unanswered && <NeedsPill>Needs RSVP</NeedsPill>}
            </p>
          <div className="segmented rsvp-buttons" role="group" aria-label="Your answer">
            {rsvpLabels.map(([status, label, tLabel]) => (
              <button
                key={status}
                type="button"
                className={mine === status ? "on" : ""}
                aria-pressed={mine === status}
                disabled={busy}
                onClick={() => void send("/rsvp", "PUT", { status: mine === status ? null : status })}
              >
                <span>{tournament ? tLabel : label}</span>
                <small className="rsvp-count">{Object.values(event.rsvps ?? {}).filter((x) => x === status).length}</small>
              </button>
            ))}
          </div>
          {/* A note goes with an answer, and goes when it's taken back. */}
          {mine && (
            <RsvpNoteField
              note={event.rsvpNotes?.[member.uid] ?? ""}
              disabled={busy}
              onSave={(note) => send("/rsvp", "PUT", { status: mine, note })}
            />
          )}
          </div>
          {going && (
            <p className="reaction-picker" role="group" aria-label="React">
              {eventReactions.map((r) => (
                <button
                  key={r}
                  type="button"
                  className={myReactions.includes(r) ? "on" : ""}
                  aria-pressed={myReactions.includes(r)}
                  disabled={busy}
                  onClick={() => void send("/reaction", "PUT", { reaction: r, on: !myReactions.includes(r) })}
                >
                  {reactionEmoji[r]}
                </button>
              ))}
            </p>
          )}
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
          <div className="rsvp-columns">
            {[
              ...rsvpLabels.map(([status, label, tLabel]) => ({
                status,
                label: tournament ? tLabel : label,
                who: Object.entries(event.rsvps ?? {}).filter(([, s]) => s === status).map(([u]) => u),
              })),
              // The app's "No reply": members who haven't answered.
              { status: "none", label: "No reply", who: (member.team.memberIds ?? []).filter((u) => !event.rsvps?.[u]) },
            ].map(({ status, label, who }) => (
              <div key={status} className={`rsvp-group ${status}`}>
                <h3>
                  <b>{who.length}</b> <span>{label}</span>
                </h3>
                <ul>
                  {who.map((u) => (
                    <li key={u}>
                      {name(u)}
                      {event.rsvps?.[u] && <NoteQuote note={event.rsvpNotes?.[u]} />}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
          {tally.length > 0 && (
            <p className="reaction-tally">
              {tally.map(([emoji, n]) => (
                <span key={emoji}>
                  {emoji} {n}
                </span>
              ))}
            </p>
          )}
          {event.poll && options.length > 0 && (
            <div className="poll">
              <h3>{event.poll.question || "Poll"}</h3>
              {options.map((o) => {
                const n = Object.values(event.votes ?? {}).filter((v) => v.includes(o.id)).length;
                const pct = voters.size ? Math.round((n / voters.size) * 100) : 0;
                const picked = myVotes.includes(o.id);
                return (
                  <button
                    key={o.id}
                    type="button"
                    className={`poll-option${picked ? " on" : ""}`}
                    disabled={!going || busy}
                    aria-pressed={picked}
                    onClick={() => vote(o.id)}
                  >
                    <span className="poll-bar" style={{ width: `${pct}%` }} />
                    <span>
                      {picked ? "✓ " : ""}
                      {o.text}
                    </span>
                    <b>{n}</b>
                  </button>
                );
              })}
              <p className="muted small">
                {voters.size} voted{!going && " · Say you're going to vote"}
              </p>
            </div>
          )}
        </>
      )}
    </article>
  );
}

/**
 * The tournament played at this event, as the app's event detail shows
 * it: a hosted tournament's page, a group's own tournament, or for a
 * group's organizers "Set up tournament" on a Tournament event.
 */
function EventTournamentLink({ event }: { event: Doc<TeamEventDoc> }) {
  const { teamId, kind, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const group = kind !== "team";
  const organizer = !!member && member.can("manageEvents");
  // The rules show organizers every tournament and players the ones they're on.
  const list = useLiveQuery<{ name?: string; eventId?: string }>(
    member && group && !event.tournamentId ? `teams/${teamId}/groupTournaments` : null,
    organizer ? [where("eventId", "==", event.id)] : member ? [where("participantIds", "array-contains", member.uid)] : [],
    `event-tournament-${organizer}-${event.id}`,
  );
  const base = `/teams/${encodeURIComponent(teamId)}/tournaments`;
  if (event.tournamentId) {
    return (
      <p className="home-actions">
        <Link href={`/tournaments/${encodeURIComponent(event.tournamentId)}`} className="btn btn-primary btn-small">
          Open tournament page
        </Link>
      </p>
    );
  }
  const found = list.data?.find((t) => t.eventId === event.id);
  if (found) {
    return (
      <p className="home-actions">
        <Link href={`${base}/${encodeURIComponent(found.id)}`} className="btn btn-primary btn-small">
          View {found.name || "tournament"}
        </Link>
      </p>
    );
  }
  if (organizer && group && event.type === "tournament" && list.data) {
    return (
      <p className="home-actions">
        <Link href={`${base}/new?event=${encodeURIComponent(event.id)}`} className="btn btn-small">
          Set up tournament
        </Link>
      </p>
    );
  }
  return null;
}
