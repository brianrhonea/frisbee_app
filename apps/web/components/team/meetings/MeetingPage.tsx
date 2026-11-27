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
import { NoteQuote, RsvpNoteField } from "../../RsvpNote";
import { audienceLine, canSee, inviteTier, isEditorTier, type MeetingData, meetingApi, meetingHref, meetingsHref, needsApproval, roomHref, whenLine } from "./model";
import "./meetings.css";
import { useConfirm } from "@/components/ui/ConfirmDialog";

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
  const askConfirm = useConfirm();
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
  // Each person by name, with the note on their answer (the app's responders).
  type Person = { uid: string; name: string; note: string };
  const people = (uids: string[]): Person[] =>
    uids
      .map((u) => ({ uid: u, name: name(u), note: m.rsvps?.[u] ? (m.rsvpNotes?.[u] ?? "") : "" }))
      .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
  const groups: Array<[string, Person[]]> = [
    ...meetingRsvps.map((a) => [meetingRsvpLabels[a], people(invited.filter((u) => m.rsvps?.[u] === a))] as [string, Person[]]),
    ["No reply", people(invited.filter((u) => !m.rsvps?.[u]))],
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
  const remove = async () => {
    const warning = m.status === "live" ? "The meeting is live. Everyone in it will be disconnected." : "RSVPs and the meeting chat will be lost.";
    if (!(await askConfirm({ message: `Delete "${m.title || "Meeting"}"? ${warning}`, confirmLabel: "Delete", destructive: true }))) return;
    void run(async () => {
      await callApi(user!, meetingApi(teamId, meetingId), { method: "DELETE" });
      router.push(meetingsHref(teamId));
    });
  };

  return (
    <div className="stack meeting-page">
      {back}
      <section className="card meeting-summary">
        <p className="meeting-kind">
          <span className="meeting-badge">Video meeting</span>
        </p>
        <div className="card-head">
          <h2 className="card-title">
            {m.title || "Meeting"}{" "}
            {m.status === "live" && <span className="meeting-badge live">Live</span>}
            {ended && <span className="meeting-badge">Ended</span>}
          </h2>
          {admin && (
            <span className="post-admin">
              <Link className="btn btn-small btn-quiet" href={`${meetingHref(teamId, meetingId)}/edit`}>
                Edit
              </Link>{" "}
              <button type="button" className="btn btn-small btn-quiet" disabled={busy} onClick={remove}>
                Delete
              </button>
            </span>
          )}
        </div>
        <p className="meeting-when">{whenLine(m)}</p>
        <p className="muted small">
          {audienceLine(m)} ·{" "}
          {m.requireApproval
            ? needsApproval(m, admin)
              ? "An admin lets you in once you ask to join."
              : "Invitees wait for an admin to let them in."
            : "Invitees can join once it starts."}
        </p>
        {!ended && (
          <div className="home-actions">
            <Link className="btn btn-primary" href={roomHref(teamId, meetingId)}>
              {m.status === "live" ? "Join meeting room" : "Go to meeting room"}
            </Link>
          </div>
        )}
      </section>
      {m.notes && (
        <section className="card meeting-agenda">
          <h2 className="card-title">Agenda</h2>
          <p className="meeting-notes">{m.notes}</p>
        </section>
      )}
      {!ended && (
        <section className={`card meeting-rsvp${mine ? "" : " needs"}`}>
          <h2 className="card-title">Will you attend?</h2>
          <div className="segmented rsvp-buttons" role="group" aria-label="Your answer">
            {meetingRsvps.map((a) => (
              <button key={a} type="button" className={mine === a ? "on" : ""} aria-pressed={mine === a} disabled={busy} onClick={() => void answer(mine === a ? null : a)}>
                {meetingRsvpLabels[a]}
              </button>
            ))}
          </div>
          {/* A note goes with an answer, and goes when it's taken back. */}
          {mine && (
            <RsvpNoteField
              note={m.rsvpNotes?.[member.uid] ?? ""}
              disabled={busy}
              onSave={(note) => run(() => callApi(user!, `${meetingApi(teamId, meetingId)}/rsvp`, { method: "PUT", body: { answer: mine, note } }))}
            />
          )}
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
        {groups.map(([label, who]) => (
          <div key={label} className="meeting-group">
            <h3 className="small">
              {label} ({who.length})
            </h3>
            {who.length === 0 ? (
              <p className="muted small">Nobody yet.</p>
            ) : (
              <p className="meeting-names">
                {who.map((p, i) => (
                  <span key={p.uid}>
                    {i > 0 && ", "}
                    {p.name}
                    <NoteQuote note={p.note} />
                  </span>
                ))}
              </p>
            )}
          </div>
        ))}
      </section>
    </div>
  );
}
