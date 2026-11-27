"use client";
import { PayoutsCard } from "@/components/payments/Payments";
import {
  allowJoinRequestsDescription,
  competitionLevels,
  type EditTeamRequest,
  optionalTeamSections,
  publicPageDescription,
  publicPageOn,
  sectionOn,
  type SetAllowJoinRequestsRequest,
  type SetPublicPageRequest,
  type SetTeamSectionsRequest,
} from "@stall10/shared";
import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { ClubAgeNote } from "../ClubAge";
import { roleLabel } from "../ProfileDashboard";
import { InviteButton, useInvite } from "./InviteDialog";
import { JoinRequests } from "./JoinRequests";
import { useTeamHub } from "./TeamContext";
import { TeamRoles } from "./TeamRoles";
import { MemberPermissions, ownPermissionsLabel } from "./MemberPermissions";
import { DiscordImport } from "./DiscordImport";
import { TeamCommunity } from "./CommunityAdmin";
import { MembersOnlySection } from "./TeamNav";
import { LEAVE_CONFIRM } from "./TeamContext";
import { optionalSectionInfo } from "./SectionGate";
import { TeamReports } from "./TeamReports";
import { useConfirm } from "@/components/ui/ConfirmDialog";

/** The team doc's editable details (Team.toEditableMap in the app). */
interface Details {
  name?: string;
  level?: string;
  city?: string;
  division?: string;
  description?: string;
  requiresApproval?: boolean;
}

/** Parallel to the app's team_form.dart notice. */
export const switchToClubNote = "Switching to club needs everyone on the team to be 16 or over with a date of birth.";

const levelLabels: Record<string, string> = { club: "Club", college: "College", youth: "Youth", league: "League", pickup: "Pickup" };

/**
 * A team's or group's settings, for its members: details (manageTeam),
 * a team's sections (Settings › Sections; the owner switches them), the invite dialog, join requests and who has which role (manageMembers),
 * handing it to someone else (the owner), and leaving.
 */
export function TeamSettings() {
  const { teamId, kind, viewer } = useTeamHub();
  const invite = useInvite();
  const { user } = useAuth();
  if (viewer.state !== "member") return <MembersOnlySection what="settings" />;
  const owner = viewer.tier === "owner";
  return (
    <div className="stack settings-stack">
      {viewer.can("manageTeam") && <DetailsForm />}
      {/* Payments: On / Finish setup / Not set up, with setup in the page (the owner's to do). */}
      {viewer.can("manageEvents") && user && <PayoutsCard user={user} teamId={teamId} />}
      {/* A league team has only its chat and members (TeamSection.forKind in the app). */}
      {kind === "team" && !viewer.team.leagueId && <SectionsCard />}
      {kind === "team" && !viewer.team.leagueId && <PublicPageCard />}
      {viewer.can("manageMembers") && <InviteCard />}
      {invite.hasRequests && <JoinRequests teamId={teamId} requests={invite.requests} />}
      {(viewer.can("moderate") || viewer.can("manageTeam")) && <TeamReports />}
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
  const [fields, setFields] = useState<Record<string, string>>({});
  async function act<T>(path: string, method: string, body?: unknown, done?: string): Promise<T | null> {
    if (!user) return null;
    setBusy(true);
    setError(null);
    setOk(null);
    setFields({});
    try {
      const res = await callApi<T>(user, path, { method, body });
      if (done) setOk(done);
      return res;
    } catch (e) {
      setError((e as Error).message);
      if (e instanceof ApiError && e.fields) setFields(e.fields);
      return null;
    } finally {
      setBusy(false);
    }
  }
  return { act, busy, error, ok, fields };
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
  const { act, busy, error, ok, fields } = useAct();
  const group = kind !== "team";
  // The API refuses a switch to club (412) with the reason under fields.level; show it by the field, not twice.
  const levelError = fields.level;

  function save(e: FormEvent) {
    e.preventDefault();
    const body: EditTeamRequest = {
      name: name.trim(),
      // Groups have no level (hasDivision).
      ...(!group && { level: level as EditTeamRequest["level"] }),
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
        {!group && (
        <label>
          Level
          <select
            value={level}
            onChange={(e) => setLevel(e.target.value)}
            aria-invalid={levelError ? true : undefined}
            aria-describedby={levelError ? "team-level-error" : undefined}
          >
            {competitionLevels.map((l) => (
              <option key={l} value={l}>
                {levelLabels[l]}
              </option>
            ))}
          </select>
          {levelError && (
            <span id="team-level-error" className="form-error" role="alert">
              {levelError}
            </span>
          )}
        </label>
        )}
        <label>
          City
          <input value={city} maxLength={80} onChange={(e) => setCity(e.target.value)} />
        </label>
      </div>
      {/* Switching to club needs everyone on the team to be 16 or over with a birth date (the API checks, 412). */}
      {!group && level === "club" && <ClubAgeNote more={(team.level ?? "club") === "club" ? undefined : switchToClubNote} />}
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
        <Status error={levelError ? null : error} ok={ok} />
        <button type="submit" className="btn btn-primary" disabled={busy}>
          Save
        </button>
      </div>
    </form>
  );
}

/**
 * Settings › Sections (team_settings_screen.dart): a switch for each of
 * Playbook, Videos, Stats and Meetings. Everyone on the team sees them;
 * only the owner can switch (`PUT /v1/teams/:id/sections`). The live team
 * doc shows the result.
 */
function SectionsCard() {
  const { teamId, viewer } = useTeamHub();
  const { act, busy, error } = useAct();
  // The switch in flight, until the live team doc shows it.
  const [pending, setPending] = useState<{ section: string; on: boolean } | null>(null);
  if (viewer.state !== "member") return null;
  const owner = viewer.tier === "owner";
  return (
    <section className="card settings-form team-sections" id="sections">
      <h2 className="card-title">Sections</h2>
      {optionalTeamSections.map((s) => (
        <label key={s} className={`switch-row${owner ? "" : " switch-row-locked"}`}>
          <span>
            <b>{optionalSectionInfo[s].label}</b>
            <small className="muted">{optionalSectionInfo[s].description}</small>
          </span>
          <input
            type="checkbox"
            role="switch"
            checked={pending?.section === s ? pending.on : sectionOn(viewer.team, s)}
            disabled={!owner || busy}
            onChange={(e) => {
              const body: SetTeamSectionsRequest = { [s]: e.target.checked };
              setPending({ section: s, on: e.target.checked });
              void act(`/v1/teams/${encodeURIComponent(teamId)}/sections`, "PUT", body).finally(() => setPending(null));
            }}
          />
        </label>
      ))}
      <p className="muted small">
        {owner
          ? "Feed, Schedule, Chat and Roster are always on. Turned-off sections are hidden from everyone on the team; turning one back on brings back what it had."
          : "Only the owner can turn sections on or off."}
      </p>
      <Status error={error} ok={null} />
    </section>
  );
}

/**
 * Settings › Visibility (team_settings_screen.dart): the "Public team
 * page" switch. Everyone on the team sees it; admins (manageTeam) switch
 * it (`PUT /v1/teams/:id/public-page`), which rewrites the listing too.
 * The live team doc shows the result.
 */
function PublicPageCard() {
  const askConfirm = useConfirm();
  const { teamId, viewer } = useTeamHub();
  const { act, busy, error } = useAct();
  // The switch in flight, until the live team doc shows it.
  const [pending, setPending] = useState<boolean | null>(null);
  const [asking, setAsking] = useState<boolean | null>(null);
  if (viewer.state !== "member") return null;
  const admin = viewer.can("manageTeam");
  // "Allow join requests" (F26): off declines those waiting, so it asks first.
  async function setRequests(on: boolean) {
    if (!on && !(await askConfirm({ message: "Stop taking join requests? Anyone still waiting is declined. People can still join with an invite.", confirmLabel: "Stop", destructive: true }))) return;
    const body: SetAllowJoinRequestsRequest = { on };
    setAsking(on);
    void act(`/v1/teams/${encodeURIComponent(teamId)}/allow-join-requests`, "PUT", body).finally(() => setAsking(null));
  }
  return (
    <section className="card settings-form team-sections team-visibility" id="visibility">
      <h2 className="card-title">Visibility</h2>
      <label className={`switch-row${admin ? "" : " switch-row-locked"}`}>
        <span>
          <b>Public team page</b>
          <small className="muted">{publicPageDescription}</small>
        </span>
        <input
          type="checkbox"
          role="switch"
          checked={pending ?? publicPageOn(viewer.team)}
          disabled={!admin || busy}
          onChange={(e) => {
            const body: SetPublicPageRequest = { public: e.target.checked };
            setPending(e.target.checked);
            void act(`/v1/teams/${encodeURIComponent(teamId)}/public-page`, "PUT", body).finally(() => setPending(null));
          }}
        />
      </label>
      <label className={`switch-row${admin ? "" : " switch-row-locked"}`}>
        <span>
          <b>Allow join requests</b>
          <small className="muted">{allowJoinRequestsDescription}</small>
        </span>
        <input
          type="checkbox"
          role="switch"
          checked={asking ?? viewer.team.allowJoinRequests === true}
          disabled={!admin || busy}
          onChange={(e) => setRequests(e.target.checked)}
        />
      </label>
      {!admin && <p className="muted small">Only the team&apos;s admins can change this.</p>}
      <Status error={error} ok={null} />
    </section>
  );
}

/**
 * Inviting lives in the hub's one invite dialog (a link, people by name,
 * join requests); Settings opens it too.
 */
function InviteCard() {
  const { kind } = useTeamHub();
  const { hasRequests, requestCount } = useInvite();
  return (
    <section className="card settings-form">
      <h2 className="card-title">Invite people</h2>
      <p className="muted small">
        Share a link{kind === "community" ? "" : " or a code to read out"}, or invite people by name
        {hasRequests ? `; ${requestCount === 1 ? "1 person is" : `${requestCount} people are`} asking to join` : ""}.
      </p>
      <div className="form-actions">
        <InviteButton className="btn btn-primary" />
      </div>
    </section>
  );
}

function MemberRoles() {
  const askConfirm = useConfirm();
  const { teamId, kind, viewer } = useTeamHub();
  const { act, busy, error } = useAct();
  // Whose permission switches are open (F25; the owner's).
  const [editing, setEditing] = useState<string | null>(null);
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
              {owner && <th>Permissions</th>}
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
                  {owner && (
                    <td>
                      {tier === "player" || tier === "stats" ? (
                        <>
                          <span className="muted">{ownPermissionsLabel(team, uid, kind !== "team") ?? "None"}</span>{" "}
                          {tier === "player" && uid !== me && (
                            <button type="button" className="text-btn" disabled={busy} aria-label={`Permissions for ${team.memberNames?.[uid] ?? "member"}`} onClick={() => setEditing(uid)}>
                              Edit
                            </button>
                          )}
                        </>
                      ) : (
                        <span className="muted">All</span>
                      )}
                    </td>
                  )}
                  <td>
                    {!fixed && (
                      <button
                        type="button"
                        className="text-btn"
                        disabled={busy}
                        onClick={async () => {
                          if ((await askConfirm({ message: `Remove ${team.memberNames?.[uid] ?? "this member"}?`, confirmLabel: "Remove", destructive: true }))) {
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
      {owner && editing && (team.memberIds ?? []).includes(editing) && (
        <MemberPermissions key={editing} teamId={teamId} team={team} uid={editing} group={kind !== "team"} onClose={() => setEditing(null)} />
      )}
      <p className="muted small">
        {owner
          ? "Give someone a preset or their own permissions with Edit, or custom roles under Roles below."
          : "The owner sets custom roles and their permissions."}
      </p>
      <Status error={error} ok={null} />
    </section>
  );
}

function TransferOwnership() {
  const askConfirm = useConfirm();
  const { teamId, kind, viewer } = useTeamHub();
  const [to, setTo] = useState("");
  const { act, busy, error, ok } = useAct();
  if (viewer.state !== "member") return null;
  const team = viewer.team;
  const others = (team.memberIds ?? []).filter((u) => u !== viewer.uid);
  return (
    <section className="card settings-form danger-zone">
      <h2 className="card-title">Hand over the {kind === "team" ? "team" : "community"}</h2>
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
          className="btn btn-quiet"
          disabled={busy || !to}
          onClick={async () => {
            if ((await askConfirm({ title: `Make ${team.memberNames?.[to] ?? "them"} the owner?`, confirmLabel: "Make owner", destructive: true }))) {
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
  const askConfirm = useConfirm();
  const { teamId, name, kind, viewer } = useTeamHub();
  const router = useRouter();
  const [typed, setTyped] = useState("");
  // As the rules ask: the owner removes everyone else, or hands it on, first.
  const others = Math.max(0, (viewer.state === "member" ? (viewer.team.memberIds?.length ?? 1) : 1) - 1);
  const { act, busy, error } = useAct();
  const noun = kind === "team" ? "team" : "community";
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
          className="btn btn-quiet"
          disabled={busy || !matches || others > 0}
          onClick={async () => {
            if (!(await askConfirm({ message: `Delete ${name} for everyone? This can't be undone.`, confirmLabel: "Delete", destructive: true }))) return;
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
  const askConfirm = useConfirm();
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
          className="btn btn-quiet"
          disabled={busy || !user}
          onClick={async () => {
            if (!user || !(await askConfirm(LEAVE_CONFIRM))) return;
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
