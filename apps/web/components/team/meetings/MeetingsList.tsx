"use client";
import Link from "next/link";
import { useState } from "react";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { audienceLine, type Meeting, meetingHref, meetingsHref, roomHref, useTeamMeetings, whenLine } from "./model";
import "./meetings.css";
import { startOfToday } from "@/lib/dates";

/**
 * The team's video meetings (/teams/:id/meetings): live ones first, then
 * what's coming up, past ones on request. Admins schedule them. The app
 * lists them on the team's schedule beside events.
 */
export function MeetingsList() {
  const { teamId, viewer } = useTeamHub();
  const meetings = useTeamMeetings(teamId, viewer);
  const [past, setPast] = useState(false);

  if (viewer.state === "loading") return <p className="muted" aria-busy="true">Loading…</p>;
  if (viewer.state !== "member") return <MembersOnlySection what="meetings" />;
  if (meetings.error) return <p className="form-error">{meetings.error}</p>;
  if (!meetings.data) return <p className="muted" aria-busy="true">Loading meetings…</p>;

  const admin = viewer.can("manageEvents");
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
        <div className="segmented" role="tablist" aria-label="Show">
          <button type="button" role="tab" className={past ? "" : "on"} aria-selected={!past} onClick={() => setPast(false)}>
            Upcoming
          </button>
          <button type="button" role="tab" className={past ? "on" : ""} aria-selected={past} onClick={() => setPast(true)}>
            Past
          </button>
        </div>
      </div>
      {!past && live.length > 0 && (
        <section className="card">
          <h2 className="card-title">Live now</h2>
          <MeetingRows teamId={teamId} meetings={live} live />
        </section>
      )}
      <section className="card">
        <h2 className="card-title">{past ? "Past meetings" : "Coming up"}</h2>
        {shown.length === 0 ? (
          <p className="empty">{past ? "No past meetings." : admin ? "No meetings scheduled. Schedule one for film, planning or a chat." : "No meetings scheduled."}</p>
        ) : (
          <MeetingRows teamId={teamId} meetings={shown} />
        )}
      </section>
    </div>
  );
}

function MeetingRows({ teamId, meetings, live = false }: { teamId: string; meetings: Meeting[]; live?: boolean }) {
  return (
    <ul className="meeting-rows">
      {meetings.map((m) => (
        <li key={m.id} className="meeting-row">
          <Link href={meetingHref(teamId, m.id)} className="meeting-row-main">
            <b>{m.title || "Meeting"}</b>
            <small className="muted">
              {whenLine(m)} · {audienceLine(m)}
              {m.status === "ended" ? " · Ended" : ""}
            </small>
          </Link>
          {live && (
            <Link className="btn btn-primary btn-small" href={roomHref(teamId, m.id)}>
              Join
            </Link>
          )}
        </li>
      ))}
    </ul>
  );
}
