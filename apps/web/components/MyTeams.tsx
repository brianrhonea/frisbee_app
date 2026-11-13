"use client";
import { where } from "firebase/firestore";
import Link from "next/link";
import { useState } from "react";
import { type Doc, useLiveQuery } from "@/lib/live";
import { divisionLabels, listingSubtitle } from "@/lib/site";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { roleLabel, TeamList } from "./ProfileDashboard";

interface MyTeam {
  name?: string;
  kind?: "team" | "community" | "organization";
  division?: string;
  level?: string;
  city?: string;
  members?: Record<string, string>;
  orgId?: string;
  orgName?: string;
  orgLinked?: boolean;
  linkedTeams?: Record<string, { name?: string; division?: string }>;
}

/** Teams a community shows before folding the rest away. */
const shownTeams = 3;

const byName = (a: { name?: string }, b: { name?: string }) => (a.name ?? "").localeCompare(b.name ?? "");

/**
 * The signed-in member's teams, as the app's Teams tab: their teams, then
 * each community with its teams under it. A team one of their communities
 * lists sits only under the community.
 */
export function MyTeams() {
  const { user } = useAuth();
  const live = useLiveQuery<MyTeam>(user ? "teams" : null, user ? [where("memberIds", "array-contains", user.uid)] : [], user?.uid ?? "");

  if (user === undefined) return null;
  if (!user) {
    return (
      <div className="card">
        <p>Join teams and pickup groups to see their schedules, chat and posts in one place.</p>
        <div className="home-actions">
          <Link className="btn btn-primary btn-small" href="/sign-up?next=/teams">
            Sign up free
          </Link>
          <Link className="btn btn-small" href="/explore">
            Find a team
          </Link>
        </div>
      </div>
    );
  }
  if (live.error) return <p className="form-error">Couldn&apos;t load your teams. Try again.</p>;
  if (!live.data) return <p className="muted" aria-busy="true">Loading your teams…</p>;

  const all = live.data;
  const mine = new Set(all.map((t) => t.id));
  const communities = all.filter((t) => t.kind && t.kind !== "team").sort(byName);
  const viaCommunity = (t: Doc<MyTeam>) =>
    t.orgLinked === true && communities.some((c) => c.id === t.orgId && Object.hasOwn(c.linkedTeams ?? {}, t.id));
  const teams = all.filter((t) => (t.kind ?? "team") === "team" && !viaCommunity(t)).sort(byName);
  const role = (t: Doc<MyTeam>) => roleLabel(t.members?.[user.uid] ?? "player", t.kind);

  if (all.length === 0) {
    return (
      <div className="card">
        <p className="muted small">
          No teams yet. <Link href="/explore">Find a team or group</Link>, or start one in the app.
        </p>
      </div>
    );
  }
  return (
    <div className="stack">
      {teams.length > 0 && (
        <TeamList
          title="Your teams"
          teams={teams.map((t) => ({
            id: t.id,
            name: t.name ?? "Team",
            subtitle: [role(t), listingSubtitle(t), t.orgLinked && t.orgName ? `Part of ${t.orgName}` : ""].filter(Boolean).join(" · "),
          }))}
        />
      )}
      {communities.length > 0 && (
        <section className="card">
          <h2 className="card-title">Communities</h2>
          <ul className="community-list">
            {communities.map((c) => (
              <CommunityRow key={c.id} community={c} role={role(c)} isOn={(id) => mine.has(id)} />
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

function CommunityRow({ community: c, role, isOn }: { community: Doc<MyTeam>; role: string; isOn: (id: string) => boolean }) {
  const teams = Object.entries(c.linkedTeams ?? {})
    .map(([id, t]) => ({ id, name: t.name ?? "Team", division: t.division }))
    .sort(byName);
  const [open, setOpen] = useState(teams.length <= shownTeams);
  return (
    <li>
      <Link className="community-head" href={`/teams/${encodeURIComponent(c.id)}`}>
        <Avatar name={c.name ?? "Community"} size={36} />
        <span>
          <b>{c.name ?? "Community"}</b>
          <small>
            {[role, listingSubtitle(c), teams.length ? `${teams.length} ${teams.length === 1 ? "team" : "teams"}` : ""]
              .filter(Boolean)
              .join(" · ")}
          </small>
        </span>
      </Link>
      {open && teams.length > 0 && (
        <ul className="team-list nested">
          {teams.map((t) => (
            <li key={t.id}>
              <Link href={`/teams/${encodeURIComponent(t.id)}`}>
                <Avatar name={t.name} size={26} />
                <span>
                  <b>{t.name}</b>
                  <small>{[divisionLabels[t.division ?? ""], isOn(t.id) ? "You're on it" : ""].filter(Boolean).join(" · ")}</small>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
      {teams.length > shownTeams && (
        <button type="button" className="link-button small" onClick={() => setOpen(!open)}>
          {open ? "Hide teams" : `Show ${teams.length} teams`}
        </button>
      )}
    </li>
  );
}
