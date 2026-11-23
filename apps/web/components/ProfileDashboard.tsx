import type { PublicProfile, StatTotals } from "@stall10/shared";
import Link from "next/link";
import type { ReactNode } from "react";
import { Avatar } from "./Avatar";
import { NavIcon, type NavIconName } from "./NavIcons";
import "./member.css";

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
  staff = false,
}: {
  profile: PublicProfile;
  actions?: ReactNode;
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
  return (
    <div className={`card profile-card${profile.headerUrl ? " has-header" : ""}`}>
      {profile.headerUrl && <div className="profile-header" style={{ backgroundImage: `url(${JSON.stringify(profile.headerUrl)})` }} />}
      <Avatar name={name} url={profile.photoUrl} size={96} />
      <h1>{name}</h1>
      {handle && <p className="muted handle">{handle}</p>}
      {(staff || profile.private) && (
        <div className="profile-badges">
          {staff && (
            <span className="staff-badge" title="Stall 10 staff">
              <span aria-hidden="true">✓</span> Stall 10 staff
            </span>
          )}
          {profile.private && <span className="pill">Private profile</span>}
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
      {actions && <div className="profile-actions">{actions}</div>}
    </div>
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
        <div className="tiles">
          {tiles.map(([k, label]) => (
            <div key={k} className="tile">
              <b>{s[k] ?? 0}</b>
              <small>{label}</small>
            </div>
          ))}
        </div>
      ) : (
        <p className="muted small">No stats yet. Stats come from games kept in the app.</p>
      )}
    </div>
  );
}

interface TeamRow {
  id: string;
  name: string;
  subtitle?: string;
}

export function TeamList({ title = "Teams", teams, empty }: { title?: string; teams: TeamRow[]; empty?: ReactNode }) {
  return (
    <div className="card">
      <h2 className="card-title">{title}</h2>
      {teams.length === 0 ? (
        (empty ?? <p className="muted small">No teams yet.</p>)
      ) : (
        <ul className="team-list">
          {teams.map((t) => (
            <li key={t.id}>
              <Link href={`/teams/${encodeURIComponent(t.id)}`}>
                <Avatar name={t.name} size={32} />
                <span>
                  <b>{t.name}</b>
                  {t.subtitle && <small>{t.subtitle}</small>}
                </span>
              </Link>
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
