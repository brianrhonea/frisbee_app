"use client";
import {
  competitionLevels,
  type EditTeamRequest,
  type InviteCodeResponse,
  inviteTtls,
} from "@stall10/shared";
import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { roleLabel } from "../ProfileDashboard";
import { useTeamHub } from "./TeamContext";
import { TeamRoles } from "./TeamRoles";
import { DiscordImport } from "./DiscordImport";
import { TeamCommunity } from "./CommunityAdmin";
import { MembersOnlySection } from "./TeamNav";

/** The team doc's editable details (Team.toEditableMap in the app). */
interface Details {
  name?: string;
  level?: string;
  city?: string;
  division?: string;
  description?: string;
  requiresApproval?: boolean;
}

const levelLabels: Record<string, string> = { club: "Club", college: "College", youth: "Youth", league: "League", pickup: "Pickup" };
const ttlLabels: Record<number, string> = { 45: "45 seconds (a code to read out)", 3600: "1 hour", 86400: "1 day", 604800: "7 days", 2592000: "30 days" };
const site = process.env.NEXT_PUBLIC_SITE_URL || "";

/**
 * A team's or group's settings, for its members: details (manageTeam),
 * invite links, join requests and who has which role (manageMembers),
 * handing it to someone else (the owner), and leaving.
 */
export function TeamSettings() {
  const { teamId, kind, viewer } = useTeamHub();
  if (viewer.state !== "member") return <MembersOnlySection what="settings" />;
  const owner = viewer.tier === "owner";
  return (
    <div className="stack settings-stack">
      {viewer.can("manageTeam") && <DetailsForm />}
      {viewer.can("manageMembers") && <InviteLinks />}
      {viewer.can("manageMembers") && kind !== "team" && viewer.team.requiresApproval && <JoinRequests />}
      {viewer.can("manageMembers") && <MemberRoles />}
      {owner && <TeamRoles />}
      {owner && <DiscordImport />}
      {kind === "team" && viewer.can("manageTeam") && <TeamCommunity />}
      {owner ? <TransferOwnership /> : <LeaveTeam teamId={teamId} />}
      {owner && <DeleteTeam />}
    </div>
  );
}

function useAct() {
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  async function act<T>(path: string, method: string, body?: unknown, done?: string): Promise<T | null> {
    if (!user) return null;
    setBusy(true);
    setError(null);
    setOk(null);
    try {
      const res = await callApi<T>(user, path, { method, body });
      if (done) setOk(done);
      return res;
    } catch (e) {
      setError((e as Error).message);
      return null;
    } finally {
      setBusy(false);
    }
  }
  return { act, busy, error, ok };
}

function Status({ error, ok }: { error: string | null; ok: string | null }) {
  if (error) return <span className="form-error" role="alert">{error}</span>;
  if (ok) return <span className="form-ok">{ok}</span>;
  return null;
}

function DetailsForm() {
  const { teamId, kind, viewer } = useTeamHub();
  const team = (viewer.state === "member" ? viewer.team : {}) as Details;
  const [name, setName] = useState(team.name ?? "");
  const [level, setLevel] = useState(team.level ?? "club");
  const [city, setCity] = useState(team.city ?? "");
  const [description, setDescription] = useState(team.description ?? "");
  const [approval, setApproval] = useState(team.requiresApproval === true);
  const { act, busy, error, ok } = useAct();
  const group = kind !== "team";

  function save(e: FormEvent) {
    e.preventDefault();
    const body: EditTeamRequest = {
      name: name.trim(),
      level: level as EditTeamRequest["level"],
      city: city.trim(),
      ...(group && { description: description.trim(), requiresApproval: approval }),
    };
    void act(`/v1/teams/${encodeURIComponent(teamId)}`, "PATCH", body, "Saved.");
  }

  return (
    <form className="card settings-form" onSubmit={save}>
      <h2 className="card-title">Details</h2>
      <label>
        Name
        <input value={name} required maxLength={80} onChange={(e) => setName(e.target.value)} />
      </label>
      <div className="form-row">
        <label>
          Level
          <select value={level} onChange={(e) => setLevel(e.target.value)}>
            {competitionLevels.map((l) => (
              <option key={l} value={l}>
                {levelLabels[l]}
              </option>
            ))}
          </select>
        </label>
        <label>
          City
          <input value={city} maxLength={80} onChange={(e) => setCity(e.target.value)} />
        </label>
      </div>
      {group && (
        <>
          <label>
            Description
            <textarea value={description} rows={3} maxLength={1000} onChange={(e) => setDescription(e.target.value)} />
          </label>
          <label className="switch-row">
            <input type="checkbox" checked={approval} onChange={(e) => setApproval(e.target.checked)} /> Approve who joins (makes it
            private: outsiders see only its name, city and description)
          </label>
        </>
      )}
      <div className="form-actions">
        <Status error={error} ok={ok} />
        <button type="submit" className="btn btn-primary" disabled={busy}>
          Save
        </button>
      </div>
    </form>
  );
}

function InviteLinks() {
  const { teamId } = useTeamHub();
  const [ttl, setTtl] = useState<number>(604800);
  const [invite, setInvite] = useState<InviteCodeResponse | null>(null);
  const { act, busy, error } = useAct();
  const link = invite ? `${site || window.location.origin}/join/${encodeURIComponent(invite.code)}` : "";
  return (
    <section className="card settings-form">
      <h2 className="card-title">Invite with a link</h2>
      <p className="muted small">Anyone with the link joins while it lasts. Invite people by name from Roster.</p>
      <div className="form-row">
        <label>
          Lasts
          <select value={ttl} onChange={(e) => setTtl(Number(e.target.value))}>
            {inviteTtls.map((t) => (
              <option key={t} value={t}>
                {ttlLabels[t]}
              </option>
            ))}
          </select>
        </label>
      </div>
      <div className="form-actions">
        <Status error={error} ok={null} />
        <button
          type="button"
          className="btn btn-primary"
          disabled={busy}
          onClick={() => void act<InviteCodeResponse>("/v1/invite-codes", "POST", { teamId, ttl }).then((r) => r && setInvite(r))}
        >
          Make a link
        </button>
      </div>
      {invite && (
        <p className="invite-panel">
          {ttl === 45 ? (
            <>
              Code: <b className="invite-code">{invite.code}</b>{" "}
            </>
          ) : (
            <>
              <input readOnly value={link} aria-label="Invite link" onFocus={(e) => e.currentTarget.select()} />{" "}
              <button type="button" className="btn btn-small" onClick={() => void navigator.clipboard?.writeText(link)}>
                Copy
              </button>
            </>
          )}
          <small className="muted">
            {" "}
            Expires {new Date(invite.expiresAt).toLocaleString()}
          </small>
        </p>
      )}
    </section>
  );
}

function JoinRequests() {
  const { teamId } = useTeamHub();
  const requests = useLiveQuery<{ name?: string }>(`teams/${teamId}/joinRequests`, [], teamId);
  const { act, busy, error } = useAct();
  return (
    <section className="card">
      <h2 className="card-title">Asking to join</h2>
      {requests.error ? (
        <p className="form-error">{requests.error}</p>
      ) : !requests.data ? (
        <p className="muted small">Loading…</p>
      ) : requests.data.length === 0 ? (
        <p className="muted small">No one is waiting.</p>
      ) : (
        <ul className="people-list">
          {requests.data.map((r) => (
            <li key={r.id} className="person-row">
              <span>{r.name || "Player"}</span>
              <span className="post-admin">
                <button type="button" className="btn btn-small btn-primary" disabled={busy} onClick={() => void act(`/v1/teams/${encodeURIComponent(teamId)}/join-requests/${encodeURIComponent(r.id)}/approve`, "POST")}>
                  Approve
                </button>
                <button type="button" className="btn btn-small" disabled={busy} onClick={() => void act(`/v1/teams/${encodeURIComponent(teamId)}/join-requests/${encodeURIComponent(r.id)}`, "DELETE")}>
                  Decline
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}
      <Status error={error} ok={null} />
    </section>
  );
}

function MemberRoles() {
  const { teamId, kind, viewer } = useTeamHub();
  const { act, busy, error } = useAct();
  if (viewer.state !== "member") return null;
  const team = viewer.team;
  const me = viewer.uid;
  const owner = viewer.tier === "owner";
  const ids = (team.memberIds ?? []).slice().sort((a, b) => (team.memberNames?.[a] ?? "").localeCompare(team.memberNames?.[b] ?? ""));
  const tiers = ["coach", "captain", "player"] as const;
  return (
    <section className="card">
      <h2 className="card-title">Members and roles</h2>
      <div className="table-scroll">
        <table className="data-table roster-table">
          <thead>
            <tr>
              <th>Member</th>
              <th>Role</th>
              {owner && kind === "team" && <th>Keeps stats</th>}
              <th />
            </tr>
          </thead>
          <tbody>
            {ids.map((uid) => {
              const tier = team.members?.[uid] ?? "player";
              const fixed = uid === me || tier === "owner";
              return (
                <tr key={uid}>
                  <td>
                    {team.memberNames?.[uid] || "Member"}
                    {uid === me && <span className="muted"> (you)</span>}
                  </td>
                  <td>
                    {fixed ? (
                      roleLabel(tier, kind)
                    ) : (
                      <select
                        aria-label={`Role for ${team.memberNames?.[uid] ?? "member"}`}
                        value={tier === "stats" ? "player" : tier}
                        disabled={busy}
                        onChange={(e) => void act(`/v1/teams/${encodeURIComponent(teamId)}/members/${encodeURIComponent(uid)}/role`, "PUT", { role: e.target.value })}
                      >
                        {tiers.map((t) => (
                          <option key={t} value={t} disabled={!owner && t === "coach"}>
                            {roleLabel(t, kind)}
                          </option>
                        ))}
                      </select>
                    )}
                  </td>
                  {owner && kind === "team" && (
                    <td>
                      <input
                        type="checkbox"
                        aria-label={`${team.memberNames?.[uid] ?? "Member"} keeps stats`}
                        checked={tier === "owner" || (team.statKeepers ?? []).includes(uid)}
                        disabled={busy || tier === "owner"}
                        onChange={(e) =>
                          void act(`/v1/teams/${encodeURIComponent(teamId)}/members/${encodeURIComponent(uid)}/stat-keeper`, "PUT", { on: e.target.checked })
                        }
                      />
                    </td>
                  )}
                  <td>
                    {!fixed && (
                      <button
                        type="button"
                        className="text-btn danger"
                        disabled={busy}
                        onClick={() => {
                          if (window.confirm(`Remove ${team.memberNames?.[uid] ?? "this member"}?`)) {
                            void act(`/v1/teams/${encodeURIComponent(teamId)}/members/${encodeURIComponent(uid)}`, "DELETE");
                          }
                        }}
                      >
                        Remove
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <p className="muted small">
        {owner ? "Give members custom roles and permissions under Roles below." : "The owner sets custom roles and their permissions."}
      </p>
      <Status error={error} ok={null} />
    </section>
  );
}

function TransferOwnership() {
  const { teamId, kind, viewer } = useTeamHub();
  const [to, setTo] = useState("");
  const { act, busy, error, ok } = useAct();
  if (viewer.state !== "member") return null;
  const team = viewer.team;
  const others = (team.memberIds ?? []).filter((u) => u !== viewer.uid);
  return (
    <section className="card settings-form danger-zone">
      <h2 className="card-title">Hand over the {kind === "team" ? "team" : "group"}</h2>
      <p className="muted small">The new owner gets full control; you stay on as a coach. Owners can&apos;t leave until they hand it over.</p>
      <div className="form-row">
        <label>
          New owner
          <select value={to} onChange={(e) => setTo(e.target.value)}>
            <option value="">Pick a member</option>
            {others.map((u) => (
              <option key={u} value={u}>
                {team.memberNames?.[u] || "Member"}
              </option>
            ))}
          </select>
        </label>
      </div>
      <div className="form-actions">
        <Status error={error} ok={ok} />
        <button
          type="button"
          className="btn btn-danger"
          disabled={busy || !to}
          onClick={() => {
            if (window.confirm(`Make ${team.memberNames?.[to] ?? "them"} the owner?`)) {
              void act(`/v1/teams/${encodeURIComponent(teamId)}/owner`, "POST", { uid: to }, "Done.");
            }
          }}
        >
          Hand over
        </button>
      </div>
    </section>
  );
}

/** Deletes it for everyone (the owner, typing its name; `DELETE /v1/teams/:id`). */
function DeleteTeam() {
  const { teamId, name, kind, viewer } = useTeamHub();
  const router = useRouter();
  const [typed, setTyped] = useState("");
  // As the rules ask: the owner removes everyone else, or hands it on, first.
  const others = Math.max(0, (viewer.state === "member" ? (viewer.team.memberIds?.length ?? 1) : 1) - 1);
  const { act, busy, error } = useAct();
  const noun = kind === "team" ? "team" : kind === "organization" ? "community" : "group";
  const matches = typed.trim().toLowerCase() === name.trim().toLowerCase();
  return (
    <section className="card settings-form danger-zone">
      <h2 className="card-title">Delete the {noun}</h2>
      <p className="muted small">
        This deletes {name} for everyone: its chat, events, posts, playbook, stats, videos and files. It can&apos;t be undone.
      </p>
      {others > 0 && (
        <p className="small">
          {others === 1 ? "1 other person is" : `${others} other people are`} still on it. Remove them from the roster, or hand it over
          (above), before deleting it.
        </p>
      )}
      <label>
        Type {name} to confirm
        <input value={typed} autoComplete="off" onChange={(e) => setTyped(e.target.value)} />
      </label>
      <div className="form-actions">
        <Status error={error} ok={null} />
        <button
          type="button"
          className="btn btn-danger"
          disabled={busy || !matches || others > 0}
          onClick={() => {
            if (!window.confirm(`Delete ${name} for everyone? This can't be undone.`)) return;
            void act(`/v1/teams/${encodeURIComponent(teamId)}`, "DELETE", { name: typed.trim() }).then((r) => {
              if (r !== null) router.push("/teams");
            });
          }}
        >
          {busy ? "Deleting…" : `Delete ${noun}`}
        </button>
      </div>
    </section>
  );
}

function LeaveTeam({ teamId }: { teamId: string }) {
  const { user } = useAuth();
  const router = useRouter();
  const { act, busy, error } = useAct();
  return (
    <section className="card danger-zone">
      <h2 className="card-title">Leave</h2>
      <div className="form-actions">
        <Status error={error} ok={null} />
        <button
          type="button"
          className="btn btn-danger"
          disabled={busy || !user}
          onClick={() => {
            if (!user || !window.confirm("Leave? You'll need a new invite to come back.")) return;
            void act(`/v1/teams/${encodeURIComponent(teamId)}/members/${encodeURIComponent(user.uid)}`, "DELETE").then((r) => {
              if (r !== null) router.push("/teams");
            });
          }}
        >
          Leave
        </button>
      </div>
    </section>
  );
}
