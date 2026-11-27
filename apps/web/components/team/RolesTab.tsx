"use client";
import type { RosterMember, TeamRoster } from "@stall10/shared";
import Link from "next/link";
import { Avatar } from "../Avatar";
import { roleLabel } from "../ProfileDashboard";
import { StatusPill } from "../ui/StatusPill";
import { buttonClass } from "../ui/buttonClass";
import { rolesInOrder, useTeamHub } from "./TeamContext";
import "./roster_actions.css";

/** The tiers that run a team, then the stats keeper (a team's only); players are everyone else. */
const tierOrder = ["owner", "coach", "captain", "stats"] as const;

/**
 * The roster's Roles tab (members only): each tier (owner, coach, captain, stats) and each of the team's
 * custom roles, with the people who hold it. It reads what the hub and the roster already hold (the team
 * doc's roles and memberRoles; no new permission model). The ones who can edit roles get "Edit roles",
 * which opens the roles editor in Settings (the owner's) or the members' tiers there (member managers').
 */
export function RolesTab({ roster }: { roster: TeamRoster }) {
  const { teamId, kind, viewer } = useTeamHub();
  if (viewer.state !== "member") return null;
  const team = viewer.team;
  const tiers = tierOrder.filter((t) => t !== "stats" || kind === "team");
  const custom = rolesInOrder(team.roles);
  const memberRoles = team.memberRoles ?? {};
  const holdersOfTier = (t: string) => roster.members.filter((m) => m.tier === t);
  const holdersOfRole = (id: string) => roster.members.filter((m) => memberRoles[m.uid]?.includes(id));
  const owner = viewer.tier === "owner";
  const canEdit = owner || viewer.can("manageMembers");

  return (
    <section className="roster-section" aria-label="Roles">
      <div className="roles-bar">
        <h2 className="card-title">Roles</h2>
        {canEdit && (
          <Link className={buttonClass({ size: "small" })} href={`/teams/${encodeURIComponent(teamId)}/settings#${owner ? "team-roles" : "member-roles"}`}>
            Edit roles
          </Link>
        )}
      </div>
      <ul className="role-holders">
        {tiers.map((t) => (
          <RoleHolders key={t} title={roleLabel(t, kind)} pill="accent" people={holdersOfTier(t)} />
        ))}
        {custom.map((r) => (
          <RoleHolders key={r.id} title={r.name} people={holdersOfRole(r.id)} />
        ))}
      </ul>
      {custom.length === 0 && <p className="muted small">No custom roles yet.</p>}
    </section>
  );
}

function RoleHolders({ title, people, pill }: { title: string; people: RosterMember[]; pill?: "accent" }) {
  return (
    <li>
      <h3 className="line-group-title">
        <StatusPill tone={pill ?? "neutral"}>{title}</StatusPill> <span className="muted small">{people.length}</span>
      </h3>
      {people.length === 0 ? (
        <p className="muted small">No one yet.</p>
      ) : (
        <ul className="role-holder-names">
          {people.map((m) => (
            <li key={m.uid}>
              <Link className="person" href={`/players/${m.uid}`}>
                <Avatar name={m.name} url={m.photoUrl} size={28} />
                <span>{m.name}</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </li>
  );
}
