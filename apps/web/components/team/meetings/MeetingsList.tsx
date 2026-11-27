"use client";
import Link from "next/link";
import { useState } from "react";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { audienceLine, type Meeting, meetingHref, meetingsHref, roomHref, useTeamMeetings, whenLine } from "./model";
import "./meetings.css";
import { DateTile } from "../DateTile";
import { startOfToday } from "@/lib/dates";
import { meetingAnswer, needsRsvp, RsvpPill } from "../../RsvpPill";
import { SegmentedTabs } from "../../ui/SegmentedTabs";
import { ErrorNote } from "@/components/StatusViews";

/**
 * The team's video meetings (/teams/:id/meetings): live ones first, then
 * what's coming up, past ones on request. Admins schedule them. Rows
 * show the member's answer, with "Needs RSVP" while it's theirs to give
 * (the app's MeetingsListScreen, which also lists them on the schedule).
 */
export function MeetingsList() {
  const { teamId, viewer } = useTeamHub();
  const meetings = useTeamMeetings(teamId, viewer);
  const [past, setPast] = useState(false);

  if (viewer.state === "loading") return <p className="muted" aria-busy="true">Loading…</p>;
  if (viewer.state !== "member") return <MembersOnlySection what="meetings" />;
  if (meetings.error) return <ErrorNote>{meetings.error}</ErrorNote>;
  if (!meetings.data) return <p className="muted" aria-busy="true">Loading meetings…</p>;

  const admin = viewer.can("manageEvents");
  const uid = viewer.uid;
  const today = startOfToday().getTime();
  const isPast = (m: Meeting) => m.status === "ended" || (m.status !== "live" && Date.parse(m.startsAt ?? "") < today);
  const live = meetings.data.filter((m) => m.status === "live");
  const upcoming = meetings.data.filter((m) => m.status !== "live" && !isPast(m));
  const done = meetings.data.filter(isPast).reverse();
  const shown = past ? done : upcoming;

  return (
    <div className="stack meetings">
      <div className="home-actions meetings-actions">
        {admin && (
          <Link className="btn btn-primary btn-small" href={`${meetingsHref(teamId)}/new`}>
            New meeting
          </Link>
        )}
        <SegmentedTabs
          label="Show"
          items={[
            { id: "upcoming", label: "Upcoming" },
            { id: "past", label: "Past" },
          ]}
          value={past ? "past" : "upcoming"}
          onChange={(v) => setPast(v === "past")}
        />
      </div>
      {!past && live.length > 0 && (
        <section className="card">
          <h2 className="card-title">Live now</h2>
          <MeetingRows teamId={teamId} uid={uid} meetings={live} live />
        </section>
      )}
      <section className="card">
        <h2 className="card-title">{past ? "Past meetings" : "Coming up"}</h2>
        {shown.length === 0 ? (
          <p className="empty">{past ? "No past meetings." : admin ? "No meetings scheduled. Schedule one for film, planning or a chat." : "No meetings scheduled."}</p>
        ) : (
          <MeetingRows teamId={teamId} uid={uid} meetings={shown} />
        )}
      </section>
    </div>
  );
}

function MeetingRows({ teamId, uid, meetings, live = false }: { teamId: string; uid: string; meetings: Meeting[]; live?: boolean }) {
  return (
    <ul className="meeting-rows">
      {meetings.map((m) => {
        const answer = meetingAnswer(m.rsvps?.[uid]);
        const ended = m.status === "ended";
        const going = Object.values(m.rsvps ?? {}).filter((a) => a === "attending").length;
        return (
        <li key={m.id} className="meeting-row">
          <Link href={meetingHref(teamId, m.id)} className="meeting-row-main">
            <DateTile startsAt={m.startsAt} />
            <span className="meeting-row-text">
            <b>
              {m.title || "Meeting"}
              {m.status === "live" && <span className="meeting-badge live">Live</span>}
            </b>
            <small className="muted">
              {whenLine(m)} · {audienceLine(m)}
              {ended ? " · Ended" : going > 0 ? ` · ${going} going` : ""}
            </small>
            </span>
          </Link>
          {live ? (
            <Link className="btn btn-primary btn-small" href={roomHref(teamId, m.id)}>
              Join
            </Link>
          ) : (
            !ended && <RsvpPill answer={answer} needs={needsRsvp(answer, m.startsAt, m.endsAt)} />
          )}
        </li>
        );
      })}
    </ul>
  );
}
