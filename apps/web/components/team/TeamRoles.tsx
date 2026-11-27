"use client";
import { roleLimits, type TeamPermission, teamPermissions } from "@stall10/shared";
import { type FormEvent, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { type CustomRoleDoc, useTeamHub } from "./TeamContext";
import { EmptyState } from "../StatusViews";
import { useConfirm } from "@/components/ui/ConfirmDialog";

/** What each permission lets a role do (TeamPermission in the app). */
export const permissionInfo: Record<TeamPermission, { label: string; summary: string }> = {
  manageTeam: { label: "Manage team", summary: "Edit details, roster, playbook, posts and videos" },
  manageMembers: { label: "Manage members", summary: "Invite, approve and remove members" },
  manageChats: { label: "Manage chats", summary: "Create, edit and delete rooms and folders" },
  manageEvents: { label: "Manage events", summary: "Events, meetings and tournaments" },
  moderate: { label: "Moderate", summary: "Delete other people's chat messages" },
  keepStats: { label: "Keep stats", summary: "Track games and edit stats" },
};

/** The app's role colors (roleColors); 0 is no color. */
const roleColors = [0, 0xffe53935, 0xfffb8c00, 0xfffdd835, 0xff43a047, 0xff00acc1, 0xff1e88e5, 0xff8e24aa, 0xffd81b60, 0xff6d4c41, 0xff546e7a];

/** A Flutter ARGB color as CSS; null for none. */
function roleCss(color: number | undefined): string | null {
  if (!color) return null;
  return `#${(color & 0xffffff).toString(16).padStart(6, "0")}`;
}

/** A new role id like the app's newRoleId: 16 letters and digits. */
function newRoleId(): string {
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}

type Draft = { id: string; name: string; color: number; perms: TeamPermission[]; members: string[] };

/**
 * The team's custom roles, like the app's Roles screen: a name, a color,
 * the permissions they grant and who has them (`PUT /v1/teams/:id/roles`,
 * owner only). Roles also pick chat room and event audiences.
 */
export function TeamRoles() {
  const askConfirm = useConfirm();
  const { teamId, kind, viewer } = useTeamHub();
  const { user } = useAuth();
  const [draft, setDraft] = useState<Draft | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (viewer.state !== "member" || !user) return null;
  const me = user;
  const team = viewer.team;
  const roles = team.roles ?? {};
  const list = Object.entries(roles).sort(([, a], [, b]) => (a.position ?? 0) - (b.position ?? 0));
  const memberRoles = team.memberRoles ?? {};
  const membersOf = (id: string) => Object.entries(memberRoles).filter(([, ids]) => ids.includes(id)).map(([uid]) => uid);
  const perms = kind === "team" ? teamPermissions : teamPermissions.filter((p) => p !== "keepStats");
  const people = (team.memberIds ?? []).slice().sort((a, b) => (team.memberNames?.[a] ?? "").localeCompare(team.memberNames?.[b] ?? ""));

  async function write(next: Record<string, CustomRoleDoc>, nextMembers: Record<string, string[]>) {
    setBusy(true);
    setError(null);
    try {
      const body = {
        roles: Object.fromEntries(
          Object.entries(next).map(([id, r]) => [id, { name: r.name, color: r.color ?? 0, position: r.position ?? 0, perms: r.perms ?? [] }]),
        ),
        memberRoles: nextMembers,
      };
      await callApi(me, `/v1/teams/${encodeURIComponent(teamId)}/roles`, { method: "PUT", body });
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }

  /** memberRoles with role [id] held by exactly [holders]. */
  function withHolders(id: string, holders: string[] | null) {
    const out: Record<string, string[]> = {};
    const set = new Set(holders ?? []);
    for (const uid of new Set([...Object.keys(memberRoles), ...set])) {
      const ids = (memberRoles[uid] ?? []).filter((r) => r !== id);
      if (set.has(uid)) ids.push(id);
      if (ids.length) out[uid] = ids;
    }
    return out;
  }

  async function save(e: FormEvent) {
    e.preventDefault();
    if (!draft) return;
    if (!draft.name.trim()) return setError("Name the role.");
    const existing = roles[draft.id];
    const position = existing?.position ?? list.length;
    const next = { ...roles, [draft.id]: { name: draft.name.trim(), color: draft.color, position, perms: draft.perms } };
    if (await write(next, withHolders(draft.id, draft.members))) setDraft(null);
  }

  async function remove(id: string) {
    if (!(await askConfirm({ message: `Delete the ${roles[id]?.name ?? ""} role? Members keep their other roles.`, confirmLabel: "Delete", destructive: true }))) return;
    const next = { ...roles };
    delete next[id];
    await write(next, withHolders(id, null));
    if (draft?.id === id) setDraft(null);
  }

  async function shift(id: string, by: number) {
    const ids = list.map(([i]) => i);
    const at = ids.indexOf(id);
    const to = at + by;
    if (to < 0 || to >= ids.length) return;
    [ids[at], ids[to]] = [ids[to]!, ids[at]!];
    const next = Object.fromEntries(ids.map((i, n) => [i, { ...roles[i]!, position: n }]));
    await write(next, memberRoles);
  }

  const toggle = <T,>(xs: T[], x: T) => (xs.includes(x) ? xs.filter((y) => y !== x) : [...xs, x]);
  return (
    <section className="card">
      <div className="card-head">
        <h2 className="card-title">Roles</h2>
        {!draft && list.length < roleLimits.roles && (
          <button type="button" className="btn btn-small" onClick={() => setDraft({ id: newRoleId(), name: "", color: 0, perms: [], members: [] })}>
            New role
          </button>
        )}
      </div>
      <p className="muted small">
        Roles give members permissions on top of their tier, and pick who sees chat rooms and events. Higher roles are
        listed first.
      </p>
      {list.length === 0 && !draft && <EmptyState>No custom roles yet.</EmptyState>}
      <ul className="role-list">
        {list.map(([id, r], i) => {
          const color = roleCss(r.color);
          const holders = membersOf(id);
          return (
            <li key={id}>
              <span className="role-dot" style={color ? { background: color } : undefined} aria-hidden="true" />
              <span className="role-main">
                <b>{r.name}</b>
                <small className="muted">
                  {[(r.perms ?? []).map((p) => permissionInfo[p]?.label).filter(Boolean).join(", ") || "No permissions", `${holders.length} ${holders.length === 1 ? "member" : "members"}`].join(" · ")}
                </small>
              </span>
              <span className="post-admin">
                <button type="button" className="text-btn" disabled={busy || i === 0} aria-label={`Move ${r.name} up`} onClick={() => void shift(id, -1)}>
                  ↑
                </button>
                <button type="button" className="text-btn" disabled={busy || i === list.length - 1} aria-label={`Move ${r.name} down`} onClick={() => void shift(id, 1)}>
                  ↓
                </button>
                <button
                  type="button"
                  className="text-btn"
                  disabled={busy}
                  onClick={() => setDraft({ id, name: r.name, color: r.color ?? 0, perms: [...(r.perms ?? [])], members: holders })}
                >
                  Edit
                </button>
                <button type="button" className="text-btn" disabled={busy} onClick={() => void remove(id)}>
                  Delete
                </button>
              </span>
            </li>
          );
        })}
      </ul>

      {draft && (
        <form className="settings-form role-editor" onSubmit={(e) => void save(e)}>
          <h3>{roles[draft.id] ? `Edit ${roles[draft.id]!.name}` : "New role"}</h3>
          <label>
            Name
            <input value={draft.name} maxLength={roleLimits.roleName} autoFocus onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          </label>
          <fieldset>
            <legend>Color</legend>
            <div className="role-swatches">
              {roleColors.map((c) => (
                <button
                  key={c}
                  type="button"
                  className={`role-swatch${draft.color === c ? " on" : ""}`}
                  style={c ? { background: roleCss(c)! } : undefined}
                  aria-label={c ? `Color ${roleCss(c)}` : "No color"}
                  aria-pressed={draft.color === c}
                  onClick={() => setDraft({ ...draft, color: c })}
                />
              ))}
            </div>
          </fieldset>
          <fieldset>
            <legend>Permissions</legend>
            {perms.map((p) => (
              <label className="switch-row" key={p}>
                <span>
                  <b>{permissionInfo[p].label}</b>
                  <small className="muted">{permissionInfo[p].summary}</small>
                </span>
                <input type="checkbox" role="switch" checked={draft.perms.includes(p)} onChange={() => setDraft({ ...draft, perms: toggle(draft.perms, p) })} />
              </label>
            ))}
          </fieldset>
          <fieldset>
            <legend>Members with this role</legend>
            <div className="role-members">
              {people.map((uid) => (
                <label key={uid} className="check-row">
                  <input type="checkbox" checked={draft.members.includes(uid)} onChange={() => setDraft({ ...draft, members: toggle(draft.members, uid) })} />
                  {team.memberNames?.[uid] || "Member"}
                </label>
              ))}
            </div>
          </fieldset>
          <div className="home-actions">
            <button className="btn btn-primary btn-small" disabled={busy}>
              {busy ? "Saving…" : "Save role"}
            </button>
            <button type="button" className="btn btn-small" disabled={busy} onClick={() => setDraft(null)}>
              Cancel
            </button>
          </div>
        </form>
      )}
      {error && <p className="form-error" role="alert">{error}</p>}
    </section>
  );
}
