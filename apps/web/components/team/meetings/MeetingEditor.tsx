"use client";
import { meetingLimits, type SaveMeetingRequest, type SaveMeetingResult } from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../../AuthProvider";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { inviteTier, isEditorTier, type MeetingData, meetingApi, meetingHref, meetingsApi, meetingsHref } from "./model";
import "./meetings.css";
import { fromLocalInput, toLocalInput } from "@/lib/dates";
import { ErrorNote } from "@/components/StatusViews";

/** 7 PM today, after practice (MeetingEditorViewModel._defaultStart). */
function defaultStart() {
  const d = new Date();
  d.setHours(19, 0, 0, 0);
  return d;
}

/** Schedules (meetingId "new") or edits a meeting: admins with manageEvents only. */
export function MeetingEditorPage({ meetingId }: { meetingId: string | null }) {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const live = useLiveDoc<MeetingData>(member && meetingId ? `teams/${teamId}/meetings/${meetingId}` : null);
  const back = (
    <Link href={meetingId ? meetingHref(teamId, meetingId) : meetingsHref(teamId)} className="text-btn">
      ← {meetingId ? "Meeting" : "Meetings"}
    </Link>
  );
  if (viewer.state === "loading") return <p className="muted" aria-busy="true">Loading…</p>;
  if (!member) return <MembersOnlySection what="meetings" />;
  if (!member.can("manageEvents")) return <p className="empty">Only admins can schedule meetings. {back}</p>;
  if (meetingId) {
    if (live.error) return <ErrorNote>{live.error}</ErrorNote>;
    if (live.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
    if (live.data === null) return <p className="empty">Meeting not found. {back}</p>;
  }
  return (
    <div className="stack">
      {back}
      <MeetingForm key={meetingId ?? "new"} meetingId={meetingId} initial={live.data ?? null} />
    </div>
  );
}

function MeetingForm({ meetingId, initial }: { meetingId: string | null; initial: MeetingData | null }) {
  const { user } = useAuth();
  const router = useRouter();
  const { teamId, viewer } = useTeamHub();
  const team = viewer.state === "member" ? viewer.team : null;
  const [title, setTitle] = useState(initial?.title ?? "");
  const [startsAt, setStartsAt] = useState(toLocalInput(initial?.startsAt ? new Date(initial.startsAt) : defaultStart()));
  const [endsAt, setEndsAt] = useState(toLocalInput(initial?.endsAt ? new Date(initial.endsAt) : null));
  const [notes, setNotes] = useState(initial?.notes ?? "");
  // A new meeting invites everyone; admins are always in.
  const [players, setPlayers] = useState((initial?.inviteRoles ?? ["player"]).includes("player"));
  const [people, setPeople] = useState<string[]>(initial?.inviteUsers ?? []);
  const [approval, setApproval] = useState(initial?.requireApproval === true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Members who can be invited one by one, by name (invitableMembers).
  const invitable = Object.entries(team?.members ?? {})
    .filter(([, role]) => !isEditorTier(role))
    .map(([uid, role]) => ({ uid, role: inviteTier(role), name: team?.memberNames?.[uid] || "Member" }))
    .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));

  async function save(e: FormEvent) {
    e.preventDefault();
    if (!user) return;
    const start = fromLocalInput(startsAt);
    if (!start) return setError("Give a date and time.");
    const inviteRoles = players ? (["player"] as const) : [];
    // Per-person invites only for people not invited by role (the app's editor).
    const inviteUsers = people.filter((u) => invitable.some((m) => m.uid === u && !(players && m.role === "player")));
    if (inviteUsers.length > meetingLimits.inviteUsers) return setError(`Invite at most ${meetingLimits.inviteUsers} people.`);
    const body: SaveMeetingRequest = {
      title: title.trim(),
      startsAt: start,
      endsAt: fromLocalInput(endsAt),
      notes,
      inviteRoles: [...inviteRoles],
      inviteUsers,
      requireApproval: approval,
    };
    setBusy(true);
    setError(null);
    try {
      const id = meetingId
        ? (await callApi<void>(user, meetingApi(teamId, meetingId), { method: "PATCH", body }), meetingId)
        : (await callApi<SaveMeetingResult>(user, meetingsApi(teamId), { method: "POST", body })).id;
      router.push(meetingHref(teamId, id));
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <form className="card settings-form meeting-editor" onSubmit={(e) => void save(e)}>
      <h2>{meetingId ? "Edit meeting" : "New meeting"}</h2>
      <label>
        Title
        <input value={title} required maxLength={meetingLimits.title} autoFocus onChange={(e) => setTitle(e.target.value)} />
      </label>
      <div className="form-row">
        <label>
          Starts
          <input type="datetime-local" required value={startsAt} onChange={(e) => setStartsAt(e.target.value)} />
        </label>
        <label>
          Ends <small className="muted">(optional)</small>
          <input type="datetime-local" value={endsAt} min={startsAt} onChange={(e) => setEndsAt(e.target.value)} />
        </label>
      </div>
      <label>
        Notes <small className="muted">(invitees see these)</small>
        <textarea value={notes} rows={3} maxLength={meetingLimits.notes} onChange={(e) => setNotes(e.target.value)} />
      </label>
      <fieldset>
        <legend>Who&apos;s invited</legend>
        <p className="muted small">Admins can always see and join.</p>
        <label className="switch-row">
          <input type="checkbox" checked={players} onChange={(e) => setPlayers(e.target.checked)} /> Everyone on the team
        </label>
        {!players && (
          <div className="meeting-people">
            {invitable.length === 0 ? (
              <p className="muted small">No one else to invite.</p>
            ) : (
              invitable.map((m) => (
                <label key={m.uid} className="switch-row">
                  <input
                    type="checkbox"
                    checked={people.includes(m.uid)}
                    onChange={(e) => setPeople(e.target.checked ? [...people, m.uid] : people.filter((u) => u !== m.uid))}
                  />{" "}
                  {m.name}
                </label>
              ))
            )}
          </div>
        )}
      </fieldset>
      <label className="switch-row">
        <input type="checkbox" checked={approval} onChange={(e) => setApproval(e.target.checked)} /> Admins let people in (they wait in the lobby)
      </label>
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        <button type="button" className="btn" disabled={busy} onClick={() => router.back()}>
          Cancel
        </button>
        <button type="submit" className="btn btn-primary" disabled={busy}>
          {busy ? "Saving…" : meetingId ? "Save" : "Schedule"}
        </button>
      </div>
    </form>
  );
}
