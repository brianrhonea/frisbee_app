import type { PublicProfile, StatTotals } from "@stall10/shared";
import Link from "next/link";
import type { ReactNode } from "react";
import { Avatar } from "./Avatar";

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

export function ProfileCard({ profile, actions }: { profile: PublicProfile; actions?: ReactNode }) {
  const name = profile.name || "Player";
  const facts = [
    profile.pronouns,
    profile.hometown,
    profile.school,
    profile.throwingHand && `Throws ${profile.throwingHand === "both" ? "with both hands" : profile.throwingHand}`,
    profile.playingSince && `Playing since ${profile.playingSince}`,
  ].filter((f): f is string => Boolean(f));
  return (
    <div className="card profile-card">
      <Avatar name={name} url={profile.photoUrl} size={96} />
      <h1>{name}</h1>
      {profile.username && <p className="muted handle">@{profile.username}</p>}
      {profile.private && <p className="pill">Private profile</p>}
      {profile.bio && <p className="bio">{profile.bio}</p>}
      {facts.length > 0 && (
        <ul className="profile-facts">
          {facts.map((f) => (
            <li key={f}>{f}</li>
          ))}
        </ul>
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

/** The latest season's totals as tiles. */
export function StatTiles({ stats }: { stats?: Record<string, StatTotals> }) {
  const seasons = Object.keys(stats ?? {}).sort().reverse();
  const season = seasons[0];
  const s = season ? stats![season] : undefined;
  return (
    <div className="card">
      <h2 className="card-title">{season ? `${season} season` : "Stats"}</h2>
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

export interface TeamRow {
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
