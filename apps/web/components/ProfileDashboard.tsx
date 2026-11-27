import type { PublicProfile, StatTotals } from "@stall10/shared";
import type { ReactNode } from "react";
import { Avatar } from "./Avatar";
import { NavIcon, type NavIconName } from "./NavIcons";
import "./member.css";
import { CoverHeader } from "./ui/CoverHeader";
import { ListRow } from "./ui/ListRow";
import { EmptyState } from "./ui/States";
import { SummaryTiles } from "./ui/SummaryTiles";
import { StatusPill } from "./ui/StatusPill";

/**
 * The profile dashboard: the person on the left (card, season stats,
 * teams), their activity on the right. Used for anyone's public profile
 * and for a member's own home page.
 */
export function DashboardLayout({ side, children }: { side: ReactNode; children: ReactNode }) {
  return (
    <div className="dash">
      <aside className="dash-side">{side}</aside>
      <section className="dash-main">{children}</section>
    </div>
  );
}

export function ProfileCard({
  profile,
  actions,
  secondary,
  staff = false,
}: {
  profile: PublicProfile;
  /** Follow, Message: beside the picture. */
  actions?: ReactNode;
  /** Report, Block: quieter, under the details. */
  secondary?: ReactNode;
  /** Stall 10 staff (`staff/{uid}`): the badge under the name, as in the app. */
  staff?: boolean;
}) {
  const name = profile.name || "Player";
  // One line each, with an icon: where they're from, school, hand, since.
  const facts = (
    [
      ["place", profile.hometown],
      ["school", profile.school],
      ["disc", profile.throwingHand && `Throws ${profile.throwingHand === "both" ? "with both hands" : profile.throwingHand}`],
      ["clock", profile.playingSince && `Playing since ${profile.playingSince}`],
    ] as Array<[NavIconName, string | undefined | false]>
  ).filter((f): f is [NavIconName, string] => Boolean(f[1]));
  const handle = [profile.username && `@${profile.username}`, profile.pronouns].filter(Boolean).join(" · ");
  // The shared cover header (the app's CoverHeader): cover, picture on its edge, name, handle, actions.
  return (
    <CoverHeader coverUrl={profile.headerUrl} avatar={<Avatar name={name} url={profile.photoUrl} size={96} />} title={name} subtitle={handle || undefined} actions={actions}>
      {(staff || profile.private) && (
        <div className="profile-badges">
          {staff && (
            <StatusPill tone="accent" icon="check">
              Stall 10 staff
            </StatusPill>
          )}
          {profile.private && <StatusPill tone="accent">Private profile</StatusPill>}
        </div>
      )}
      {(profile.bio || facts.length > 0) && (
        <div className="profile-about">
          {profile.bio && <p className="bio">{profile.bio}</p>}
          {facts.length > 0 && (
            <ul className="profile-facts">
              {facts.map(([icon, text]) => (
                <li key={icon}>
                  <NavIcon name={icon} size={16} />
                  <span>{text}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
      {secondary && <div className="profile-secondary">{secondary}</div>}
    </CoverHeader>
  );
}

const tiles: Array<[keyof StatTotals, string]> = [
  ["games", "Games"],
  ["goals", "Goals"],
  ["assists", "Assists"],
  ["blocks", "Blocks"],
];

/** The latest season's totals as tiles (for [teamName]'s games, when the Team filter picked one). */
export function StatTiles({ stats, teamName }: { stats?: Record<string, StatTotals>; teamName?: string }) {
  const seasons = Object.keys(stats ?? {}).sort().reverse();
  const season = seasons[0];
  const s = season ? stats![season] : undefined;
  const title = season ? `${season} season` : "Stats";
  return (
    <div className="card">
      <h2 className="card-title">{teamName ? `${title} · ${teamName}` : title}</h2>
      {s ? (
        <SummaryTiles label={title} items={tiles.map(([k, label]) => ({ id: k, label, value: s[k] ?? 0 }))} />
      ) : (
        <EmptyState quiet>No stats yet. Stats come from games kept in the app.</EmptyState>
      )}
    </div>
  );
}

interface TeamRow {
  id: string;
  name: string;
  subtitle?: string;
}

export function TeamList({ title = "Teams", teams, empty, plain = false }: { title?: string; teams: TeamRow[]; empty?: ReactNode; plain?: boolean }) {
  // Plain: a heading over list rows (C3), no box (the Teams tab); otherwise the profile's card.
  if (plain) {
    return (
      <section className="teams-section">
        <h2 className="card-title">{title}</h2>
        {teams.length === 0 ? (
          (empty ?? <p className="muted small">No teams yet.</p>)
        ) : (
          <ul className="teams-rows">
            {teams.map((t) => (
              <li key={t.id}>
                <ListRow href={`/teams/${encodeURIComponent(t.id)}`} leading={<Avatar name={t.name} size={40} />} title={t.name} subtitle={t.subtitle} />
              </li>
            ))}
          </ul>
        )}
      </section>
    );
  }
  return (
    <div className="card">
      <h2 className="card-title">{title}</h2>
      {teams.length === 0 ? (
        (empty ?? <EmptyState quiet>No teams yet.</EmptyState>)
      ) : (
        <ul className="teams-rows">
          {teams.map((t) => (
            <li key={t.id}>
              <ListRow href={`/teams/${encodeURIComponent(t.id)}`} leading={<Avatar name={t.name} size={40} />} title={t.name} subtitle={t.subtitle} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

const roleLabels: Record<string, string> = {
  owner: "Owner",
  coach: "Coach",
  captain: "Captain",
  player: "Player",
  stats: "Stats",
};

/** "Captain", or "Member" for a group's players. */
export function roleLabel(role: string, kind?: string): string {
  if (role === "player" && kind && kind !== "team") return "Member";
  return roleLabels[role] ?? role;
}
