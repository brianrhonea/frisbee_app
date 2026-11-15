"use client";
import { type MeetingRsvp, meetingRsvpLabels, meetingRsvps } from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../../AuthProvider";
import { type TeamDoc, useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { MeetingAlerts } from "./MeetingAlerts";
import { audienceLine, canSee, inviteTier, isEditorTier, type MeetingData, meetingApi, meetingHref, meetingsHref, needsApproval, roomHref, whenLine } from "./model";
import "./meetings.css";

/** Members of [team] who can see [m] (TeamMeeting.invitees). */
function invitees(team: TeamDoc, m: MeetingData): string[] {
  return Object.entries(team.members ?? {})
    .filter(([uid, role]) => {
      const perms = team.memberPerms?.[uid] ?? [];
      return isEditorTier(role) || perms.includes("manageEvents") || (m.inviteRoles ?? []).includes(inviteTier(role)) || (m.inviteUsers ?? []).includes(uid);
    })
    .map(([uid]) => uid);
}

/**
 * One meeting (MeetingDetailScreen): when, who's invited, notes, your
 * answer and everyone's, and the way into the room. Admins edit and
 * delete it.
 */
export function MeetingPage({ meetingId }: { meetingId: string }) {
  const { user } = useAuth();
  const router = useRouter();
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const live = useLiveDoc<MeetingData>(member ? `teams/${teamId}/meetings/${meetingId}` : null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const back = (
    <Link href={meetingsHref(teamId)} className="text-btn">
      ← Meetings
    </Link>
  );

  if (viewer.state === "loading") return <p className="muted" aria-busy="true">Loading…</p>;
  if (!member) return <MembersOnlySection what="meetings" />;
  if (live.error) return <p className="empty">This meeting isn&apos;t available to you. {back}</p>;
  if (live.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  const m = live.data;
  if (!m || !canSee(m, member)) return <p className="empty">This meeting no longer exists. {back}</p>;

  const admin = member.can("manageEvents");
  const mine = m.rsvps?.[member.uid] ?? null;
  const ended = m.status === "ended";
  const invited = invitees(member.team, m);
  const name = (uid: string) => member.team.memberNames?.[uid] || "Member";
  const groups: Array<[string, string[]]> = [
    ...meetingRsvps.map((a) => [meetingRsvpLabels[a], invited.filter((u) => m.rsvps?.[u] === a).map(name)] as [string, string[]]),
    ["No reply", invited.filter((u) => !m.rsvps?.[u]).map(name)],
  ];

  async function run(fn: () => Promise<unknown>) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const answer = (a: MeetingRsvp | null) =>
    run(() => callApi(user!, `${meetingApi(teamId, meetingId)}/rsvp`, { method: "PUT", body: { answer: a } }));
  const remove = () => {
    const warning = m.status === "live" ? "The meeting is live. Everyone in it will be disconnected." : "RSVPs and the meeting chat will be lost.";
    if (!window.confirm(`Delete "${m.title || "Meeting"}"? ${warning}`)) return;
    void run(async () => {
      await callApi(user!, meetingApi(teamId, meetingId), { method: "DELETE" });
      router.push(meetingsHref(teamId));
    });
  };

  return (
    <div className="stack meeting-page">
      <MeetingAlerts />
      {back}
      <section className="card">
        <div className="card-head">
          <h2 className="card-title">
            {m.title || "Meeting"}{" "}
            {m.status === "live" && <span className="meeting-badge live">Live</span>}
            {ended && <span className="meeting-badge">Ended</span>}
          </h2>
          {admin && (
            <span className="post-admin">
              <Link className="text-btn" href={`${meetingHref(teamId, meetingId)}/edit`}>
                Edit
              </Link>{" "}
              <button type="button" className="text-btn" disabled={busy} onClick={remove}>
                Delete
              </button>
            </span>
          )}
        </div>
        <p>{whenLine(m)}</p>
        <p className="muted small">
          {audienceLine(m)} ·{" "}
          {m.requireApproval
            ? needsApproval(m, admin)
              ? "An admin lets you in once you ask to join."
              : "Invitees wait for an admin to let them in."
            : "Invitees can join once it starts."}
        </p>
        {m.notes && <p className="meeting-notes">{m.notes}</p>}
        {!ended && (
          <div className="home-actions">
            <Link className="btn btn-primary" href={roomHref(teamId, meetingId)}>
              {m.status === "live" ? "Join meeting room" : "Go to meeting room"}
            </Link>
          </div>
        )}
      </section>
      {!ended && (
        <section className="card">
          <h2 className="card-title">Will you attend?</h2>
          <div className="segmented" role="group" aria-label="Your answer">
            {meetingRsvps.map((a) => (
              <button key={a} type="button" className={mine === a ? "on" : ""} aria-pressed={mine === a} disabled={busy} onClick={() => void answer(mine === a ? null : a)}>
                {meetingRsvpLabels[a]}
              </button>
            ))}
          </div>
          <p className="muted small">{mine === "attending" ? "We'll notify you when it starts." : "Attending? You get a notification when it starts."}</p>
        </section>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <section className="card">
        <h2 className="card-title">Invited ({invited.length})</h2>
        {groups.map(([label, names]) => (
          <div key={label} className="meeting-group">
            <h3 className="small">
              {label} ({names.length})
            </h3>
            {names.length === 0 ? <p className="muted small">Nobody yet.</p> : <p className="meeting-names">{names.sort().join(", ")}</p>}
          </div>
        ))}
      </section>
    </div>
  );
}
