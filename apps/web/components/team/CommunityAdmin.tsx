"use client";
import {
  clubRolesNotice,
  competitionLevels,
  divisions,
  roleLimits,
  type SearchPage,
  teamLimits,
} from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import { type FormEvent, useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { divisionLabels } from "@/lib/site";
import { useAuth } from "../AuthProvider";
import { ClubAgeNote } from "../ClubAge";
import { rolesInOrder, useTeamHub } from "./TeamContext";
import { EmptyState } from "../StatusViews";
import { useConfirm } from "@/components/ui/ConfirmDialog";
import { ErrorNote } from "@/components/StatusViews";

const levelLabels: Record<string, string> = { club: "Club", college: "College", youth: "Youth", league: "League", pickup: "Pickup" };

/** teams/{orgId}/linkRequests/{teamId}: a team asking to be in the community. */
interface LinkRequest {
  teamName?: string;
  division?: string;
  requestedByName?: string;
}

function useCall() {
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function call(path: string, method: string, body?: unknown): Promise<boolean> {
    if (!user) return false;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, path, { method, body });
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }
  return { call, busy, error };
}

/** Picks community roles whose holders are put on a team. */
function RolePicker({ value, onChange }: { value: string[]; onChange: (v: string[]) => void }) {
  const { viewer } = useTeamHub();
  const roles = rolesInOrder(viewer.state === "member" ? viewer.team.roles : undefined);
  if (roles.length === 0) return <p className="muted small">Make roles in Settings to put their members on teams automatically.</p>;
  return (
    <div className="role-members">
      <p className="muted small">{clubRolesNotice}</p>
      {roles.map((r) => (
        <label key={r.id} className="check-row">
          <input
            type="checkbox"
            checked={value.includes(r.id)}
            disabled={!value.includes(r.id) && value.length >= roleLimits.roles}
            onChange={() => onChange(value.includes(r.id) ? value.filter((x) => x !== r.id) : [...value, r.id])}
          />
          {r.name}
        </label>
      ))}
    </div>
  );
}

/**
 * A school or club community's team admin (manageTeam on the community):
 * start a team in it, answer teams asking to join, pick which community
 * roles put people on each team, and take teams out.
 */
export function CommunityAdmin() {
  const askConfirm = useConfirm();
  const { teamId: orgId, viewer } = useTeamHub();
  const requests = useLiveQuery<LinkRequest>(`teams/${orgId}/linkRequests`, [orderBy("createdAt", "desc"), limit(100)], orgId);
  const { call, busy, error } = useCall();
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [roles, setRoles] = useState<string[]>([]);
  const [form, setForm] = useState({ name: "", division: "mixed", level: "college", city: "" });
  if (viewer.state !== "member") return null;
  const linked = Object.entries(viewer.team.linkedTeams ?? {}).sort(([, a], [, b]) => (a.name ?? "").localeCompare(b.name ?? ""));
  const full = linked.length >= roleLimits.linkedTeams;
  const base = `/v1/teams/${encodeURIComponent(orgId)}`;

  async function create(e: FormEvent) {
    e.preventDefault();
    if (!form.name.trim()) return;
    if (await call(`${base}/linked-teams`, "POST", { ...form, name: form.name.trim(), city: form.city.trim(), roles })) {
      setAdding(false);
      setForm({ name: "", division: "mixed", level: "college", city: "" });
      setRoles([]);
    }
  }

  return (
    <section className="card settings-form">
      <div className="card-head">
        <h2 className="card-title">Manage teams</h2>
        {!adding && !full && (
          <button type="button" className="btn btn-small" onClick={() => { setAdding(true); setRoles([]); setEditing(null); }}>
            Add a team
          </button>
        )}
      </div>
      {full && <p className="muted small">A community can have {roleLimits.linkedTeams} teams.</p>}

      {adding && (
        <form className="settings-form role-editor" onSubmit={(e) => void create(e)}>
          <h3>New team</h3>
          <label>
            Name
            <input value={form.name} maxLength={teamLimits.name} autoFocus onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </label>
          <div className="form-grid">
            <label>
              Division
              <select value={form.division} onChange={(e) => setForm({ ...form, division: e.target.value })}>
                {divisions.map((d) => (
                  <option key={d} value={d}>
                    {divisionLabels[d] ?? d}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Level
              <select value={form.level} onChange={(e) => setForm({ ...form, level: e.target.value })}>
                {competitionLevels.map((l) => (
                  <option key={l} value={l}>
                    {levelLabels[l] ?? l}
                  </option>
                ))}
              </select>
            </label>
            <label>
              City
              <input value={form.city} maxLength={teamLimits.city} onChange={(e) => setForm({ ...form, city: e.target.value })} />
            </label>
          </div>
          {form.level === "club" && <ClubAgeNote />}
          <fieldset>
            <legend>Who&apos;s on it</legend>
            <RolePicker value={roles} onChange={setRoles} />
          </fieldset>
          <div className="home-actions">
            <button className="btn btn-primary btn-small" disabled={busy || !form.name.trim()}>
              {busy ? "Adding…" : "Add team"}
            </button>
            <button type="button" className="btn btn-small" onClick={() => setAdding(false)}>
              Cancel
            </button>
          </div>
        </form>
      )}

      {(requests.data?.length ?? 0) > 0 && (
        <>
          <h3>Asking to join</h3>
          <ul className="role-list">
            {requests.data!.map((r) => (
              <li key={r.id}>
                <span className="role-main">
                  <b>{r.teamName || "Team"}</b>
                  <small className="muted">
                    {[divisionLabels[r.division ?? ""], r.requestedByName && `Asked by ${r.requestedByName}`].filter(Boolean).join(" · ")}
                  </small>
                </span>
                <span className="post-admin">
                  <button type="button" className="text-btn" disabled={busy || full} onClick={() => void call(`${base}/link-requests/${encodeURIComponent(r.id)}/accept`, "POST", { roles: [] })}>
                    Accept
                  </button>
                  <button type="button" className="text-btn" disabled={busy} onClick={() => void call(`${base}/link-requests/${encodeURIComponent(r.id)}`, "DELETE")}>
                    Decline
                  </button>
                </span>
              </li>
            ))}
          </ul>
        </>
      )}

      {linked.length > 0 && (
        <>
          <h3>Teams in this community</h3>
          <ul className="role-list">
            {linked.map(([id, t]) => (
              <li key={id} className="linked-team">
                <div className="linked-team-row">
                  <span className="role-main">
                    <b>{t.name || "Team"}</b>
                    <small className="muted">
                      {[divisionLabels[t.division ?? ""], (t.roles ?? []).length ? `${t.roles!.length} ${t.roles!.length === 1 ? "role joins" : "roles join"}` : ""].filter(Boolean).join(" · ")}
                    </small>
                  </span>
                  <span className="post-admin">
                    <button type="button" className="text-btn" disabled={busy} aria-expanded={editing === id} onClick={() => { setEditing(editing === id ? null : id); setRoles(t.roles ?? []); setAdding(false); }}>
                      Roles
                    </button>
                    <button
                      type="button"
                      className="text-btn"
                      disabled={busy}
                      onClick={async () => {
                        if ((await askConfirm({ message: `Take ${t.name || "this team"} out of the community? The team itself stays.`, confirmLabel: "Remove", destructive: true }))) void call(`${base}/linked-teams/${encodeURIComponent(id)}`, "DELETE");
                      }}
                    >
                      Remove
                    </button>
                  </span>
                </div>
                {editing === id && (
                  <div className="role-editor">
                    <RolePicker value={roles} onChange={setRoles} />
                    <div className="home-actions">
                      <button
                        type="button"
                        className="btn btn-primary btn-small"
                        disabled={busy}
                        onClick={async () => {
                          if (await call(`${base}/linked-teams/${encodeURIComponent(id)}`, "PUT", { roles })) setEditing(null);
                        }}
                      >
                        Save roles
                      </button>
                    </div>
                  </div>
                )}
              </li>
            ))}
          </ul>
        </>
      )}
      {error && <ErrorNote>{error}</ErrorNote>}
    </section>
  );
}

/**
 * A team's school or club (manageTeam on the team): ask to join one, see
 * that it's waiting or in, and leave.
 */
export function TeamCommunity() {
  const askConfirm = useConfirm();
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const { call, busy, error } = useCall();
  const [q, setQ] = useState("");
  const [found, setFound] = useState<SearchPage["teams"] | null>(null);
  if (viewer.state !== "member" || !user) return null;
  const me = user;
  const team = viewer.team;
  const base = `/v1/teams/${encodeURIComponent(teamId)}/community`;

  async function search(e: FormEvent) {
    e.preventDefault();
    const term = q.trim();
    if (term.length < 2) return;
    try {
      const r = await callApi<SearchPage>(me, `/v1/public/search?q=${encodeURIComponent(term)}`);
      setFound(r.teams.filter((t) => t.kind === "organization"));
    } catch {
      setFound([]);
    }
  }

  return (
    <section className="card settings-form">
      <h2 className="card-title">School or club</h2>
      {team.orgId ? (
        <>
          <p>
            {team.orgLinked ? "Part of " : "Waiting for "}
            <b>{team.orgName || "a community"}</b>
            {team.orgLinked ? "." : " to accept."}
          </p>
          <div className="home-actions">
            <button
              type="button"
              className="btn btn-small"
              disabled={busy}
              onClick={async () => {
                if ((await askConfirm(team.orgLinked ? { title: "Leave the community?", confirmLabel: "Leave community" } : { title: "Cancel the request?", confirmLabel: "Cancel request", cancelLabel: "Keep request" }))) void call(base, "DELETE");
              }}
            >
              {team.orgLinked ? "Leave community" : "Cancel request"}
            </button>
          </div>
        </>
      ) : (
        <>
          <p className="muted small">Ask a school or club community to list this team. Its admins decide.</p>
          <form className="invite-search" onSubmit={(e) => void search(e)}>
            <input value={q} placeholder="Search schools and clubs" aria-label="Search schools and clubs" onChange={(e) => setQ(e.target.value)} />
            <button className="btn btn-small" disabled={q.trim().length < 2}>
              Search
            </button>
          </form>
          {found && found.length === 0 && <EmptyState>No schools or clubs found.</EmptyState>}
          {found && found.length > 0 && (
            <ul className="role-list">
              {found.map((o) => (
                <li key={o.id}>
                  <span className="role-main">
                    <b>{o.name}</b>
                    {o.city && <small className="muted">{o.city}</small>}
                  </span>
                  <button type="button" className="btn btn-small" disabled={busy} onClick={() => void call(base, "PUT", { orgId: o.id })}>
                    Ask to join
                  </button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
      {error && <ErrorNote>{error}</ErrorNote>}
    </section>
  );
}
