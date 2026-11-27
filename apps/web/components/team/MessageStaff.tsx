"use client";
import Link from "next/link";
import type { TeamRoster } from "@stall10/shared";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { Dialog } from "../Dialog";
import { openConversation } from "../MessageButton";
import { roleLabel } from "../ProfileDashboard";
import { ErrorNote, Loading } from "../StatusViews";
import { Button } from "../ui/Button";
import { StatusPill } from "../ui/StatusPill";
import { ListRow } from "../ui/ListRow";
import { type TeamDoc, useTeamHub } from "./TeamContext";
import "./message_staff.css";

/**
 * Who the Message dialog lists: members whose tier is owner, coach or captain (as the app's does), for members
 * and outsiders alike. Permission-based admins and custom roles are not staff here.
 */
export const staffTiers = ["owner", "coach", "captain"];

/** [uid] is missing when the API keeps it from an outsider (a non-staff or hidden person): they can't be messaged. */
export type StaffPerson = { uid?: string; name: string; tier: string; photoUrl?: string };

/** The team doc's people with their tiers, from what the hub already holds. */
export function peopleOf(team: TeamDoc): StaffPerson[] {
  return (team.memberIds ?? []).map((uid) => ({ uid, name: team.memberNames?.[uid] || "Member", tier: team.members?.[uid] ?? "player" }));
}

/** The staff to list: owner, coach, captain, then by name; never the viewer or anyone without a uid. Pure, for tests. */
export function staffOf(people: StaffPerson[], viewerUid: string): StaffPerson[] {
  return people
    .filter((p) => staffTiers.includes(p.tier) && !!p.uid && p.uid !== viewerUid)
    .sort((a, b) => staffTiers.indexOf(a.tier) - staffTiers.indexOf(b.tier) || a.name.localeCompare(b.name));
}

/**
 * The team header's Message button. Members get "Team chat" at the top of a small dialog, then the team's
 * staff (from the team doc the hub already holds). Each person opens a normal direct conversation
 * (`POST /v1/conversations`, as a player's page does): the server's message settings decide, and its refusal
 * is shown here. A signed-in person who is not on the team gets the staff only, read from the roster
 * (`GET /v1/teams/:id/roster`, which any signed-in person may read) when the dialog opens. Signed-out visitors
 * never see Message, and neither does anyone outside a youth team or a private group, whose roster is private.
 */
export function MessageStaff() {
  const { teamId, kind, youth, privateGroup, viewer } = useTeamHub();
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const member = viewer.state === "member";
  const outsider = viewer.state === "outsider" && !youth && !privateGroup;
  if (!user || (!member && !outsider)) return null;
  return (
    <>
      <Button size="small" className="btn-quiet" aria-haspopup="dialog" onClick={() => setOpen(true)}>
        Message
      </Button>
      {open && (
        <Dialog label="Message the team" onClose={() => setOpen(false)} className="card staff-dialog" dismissOnBackdrop>
          <StaffList teamId={teamId} kind={kind} onClose={() => setOpen(false)} />
        </Dialog>
      )}
    </>
  );
}

function StaffList({ teamId, kind, onClose }: { teamId: string; kind: string; onClose: () => void }) {
  const { viewer } = useTeamHub();
  const { user } = useAuth();
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [fetched, setFetched] = useState<StaffPerson[] | null>(null);
  const [loadError, setLoadError] = useState("");
  const member = viewer.state === "member";

  // Outsiders can't read the team doc: the roster has its members and tiers.
  useEffect(() => {
    if (member || !user) return;
    let live = true;
    callApi<TeamRoster>(user, `/v1/teams/${encodeURIComponent(teamId)}/roster`).then(
      (r) => live && setFetched(r.members as StaffPerson[]),
      (e) => live && setLoadError(problem(e, "Couldn't load the team's staff. Try again.")),
    );
    return () => {
      live = false;
    };
  }, [member, user, teamId]);

  if (!user) return null;
  const people = viewer.state === "member" ? peopleOf(viewer.team) : fetched;
  const staff = people ? staffOf(people, user.uid) : null;

  async function message(uid: string | undefined) {
    if (!user || !uid) return;
    setBusy(uid);
    setError("");
    try {
      const res = await openConversation(user, uid);
      onClose();
      router.push(`/messages?c=${encodeURIComponent(res.id)}`);
    } catch (e) {
      setError(problem(e, "Couldn't open the conversation. Try again."));
      setBusy(null);
    }
  }

  return (
    <div className="staff-list">
      <div className="staff-head">
        <h2 className="card-title">Message the team</h2>
        <button type="button" className="icon-btn" aria-label="Close" onClick={onClose}>
          ×
        </button>
      </div>
      {member && (
        <Link className="btn btn-primary" href={`/teams/${encodeURIComponent(teamId)}/chat`} onClick={onClose}>
          Team chat
        </Link>
      )}
      <h3 className="line-group-title">{kind === "team" ? "Team staff" : "Organizers"}</h3>
      {loadError ? (
        <ErrorNote>{loadError}</ErrorNote>
      ) : !staff ? (
        <Loading label="Loading…" />
      ) : staff.length === 0 ? (
        <p className="muted small">No one else to message.</p>
      ) : (
        <ul className="staff-rows">
          {staff.map((p) => (
            <li key={p.uid}>
              <ListRow
                leading={<Avatar name={p.name} url={p.photoUrl} size={40} />}
                title={p.name}
                subtitle={<StatusPill tone="accent">{roleLabel(p.tier, kind)}</StatusPill>}
                trailing={
                  <Button size="small" loading={busy === p.uid} disabled={busy !== null && busy !== p.uid} aria-label={`Message ${p.name}`} onClick={() => void message(p.uid)}>
                    Message
                  </Button>
                }
              />
            </li>
          ))}
        </ul>
      )}
      {error && <ErrorNote>{error}</ErrorNote>}
    </div>
  );
}
