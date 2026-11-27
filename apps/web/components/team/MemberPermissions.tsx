"use client";
import { presetMatching, rolePresetsFor, type SetMemberPermissionsRequest, type TeamPermission, teamPermissions } from "@stall10/shared";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { rolesInOrder, type TeamDoc } from "./TeamContext";
import { permissionInfo } from "./TeamRoles";
import { ErrorNote } from "@/components/StatusViews";

/** A member's own permissions (memberGrants), with stats access counted as Keep stats (Team.ownPermissionsOf in the app). */
export function ownPermissionsOf(team: TeamDoc, uid: string): TeamPermission[] {
  const own = new Set<string>(team.memberGrants?.[uid] ?? []);
  if ((team.statKeepers ?? []).includes(uid)) own.add("keepStats");
  return teamPermissions.filter((p) => own.has(p));
}

/** "Captain", "Custom" or null (no permissions of their own), as the app's member row says it. */
export function ownPermissionsLabel(team: TeamDoc, uid: string, group: boolean): string | null {
  const own = ownPermissionsOf(team, uid);
  if (own.length === 0) return null;
  const preset = presetMatching(own, group);
  if (preset?.id === "statKeeper") return "Stats";
  return preset?.name ?? "Custom";
}

/**
 * The owner's per-person permission switches for [uid] (F25), like the
 * app's Permissions dialog: a preset in one click, then a switch per
 * permission with its one-line description; a mix no preset has reads
 * "Custom". Permissions a custom role gives are on and locked, naming the
 * role. Saves with `PUT /v1/teams/:id/members/:uid/permissions`.
 */
export function MemberPermissions({
  teamId,
  team,
  uid,
  group,
  onClose,
}: {
  teamId: string;
  team: TeamDoc;
  uid: string;
  group: boolean;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const [own, setOwn] = useState<TeamPermission[]>(() => ownPermissionsOf(team, uid));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const perms = group ? teamPermissions.filter((p) => p !== "keepStats") : teamPermissions;
  const presets = rolePresetsFor(group);
  const preset = presetMatching(own, group);
  const name = team.memberNames?.[uid] || "this member";
  const myRoles = rolesInOrder(team.roles).filter((r) => (team.memberRoles?.[uid] ?? []).includes(r.id));
  const rolesGiving = (p: TeamPermission) => myRoles.filter((r) => (r.perms ?? []).includes(p)).map((r) => r.name);
  const anyLocked = perms.some((p) => rolesGiving(p).length > 0);

  async function save() {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      const body: SetMemberPermissionsRequest = { perms: perms.filter((p) => own.includes(p)) };
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/members/${encodeURIComponent(uid)}/permissions`, { method: "PUT", body });
      onClose();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const toggle = (p: TeamPermission) => setOwn(own.includes(p) ? own.filter((x) => x !== p) : [...own, p]);
  return (
    <div className="settings-form member-perms">
      <h3>Permissions for {name}</h3>
      <fieldset>
        <legend>Start from a preset</legend>
        <div className="segmented" role="group" aria-label="Presets">
          {presets.map((p) => (
            <button key={p.id} type="button" className={preset?.id === p.id ? "on" : undefined} aria-pressed={preset?.id === p.id} title={p.summary} onClick={() => setOwn([...p.perms])}>
              {p.name}
            </button>
          ))}
          {!preset && (
            <button type="button" className="on" aria-pressed disabled>
              Custom
            </button>
          )}
        </div>
        <p className="muted small">{preset?.summary ?? "Your own mix of the permissions below."}</p>
      </fieldset>
      <fieldset>
        <legend>Permissions</legend>
        {perms.map((p) => {
          const roles = rolesGiving(p);
          return (
            <label className="switch-row" key={p}>
              <span>
                <b>{permissionInfo[p].label}</b>
                <small className="muted">
                  {permissionInfo[p].summary}
                  {roles.length > 0 && `. From the ${roles.join(", ")} ${roles.length === 1 ? "role" : "roles"}.`}
                </small>
              </span>
              <input
                type="checkbox"
                role="switch"
                aria-label={permissionInfo[p].label}
                checked={roles.length > 0 || own.includes(p)}
                disabled={busy || roles.length > 0}
                onChange={() => toggle(p)}
              />
            </label>
          );
        })}
        {anyLocked && <p className="muted small">Locked switches come from their roles; change those under Roles.</p>}
      </fieldset>
      <div className="home-actions">
        <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={() => void save()}>
          {busy ? "Saving…" : "Save permissions"}
        </button>
        <button type="button" className="btn btn-small" disabled={busy} onClick={onClose}>
          Cancel
        </button>
      </div>
      {error && (
        <ErrorNote>
          {error}
        </ErrorNote>
      )}
    </div>
  );
}
