import type { ProfilePage, StatTotals } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { cache } from "react";
import { FollowButton } from "@/components/FollowButton";
import { ForVisitors } from "@/components/ForVisitors";
import { LocalTime } from "@/components/LocalTime";
import { PostCard } from "@/components/PostCard";
import { DashboardLayout, ProfileCard, StatTiles, TeamList } from "@/components/ProfileDashboard";
import { getPublic } from "@/lib/api";

type Props = { params: Promise<{ uid: string }> };

const load = cache((uid: string) => getPublic<ProfilePage>(`/v1/public/players/${encodeURIComponent(uid)}`));

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { profile } = await load((await params).uid);
  const name = profile.name || "A player";
  return {
    title: profile.username ? `${name} (@${profile.username})` : name,
    description: profile.private ? `${name} on Stall 10.` : profile.bio?.slice(0, 200) || `${name}'s profile on Stall 10.`,
    openGraph: { images: profile.photoUrl ?? "/logo.png" },
  };
}

const statColumns: Array<[keyof StatTotals, string]> = [
  ["games", "Games"],
  ["points", "Points"],
  ["goals", "Goals"],
  ["assists", "Assists"],
  ["blocks", "Blocks"],
  ["completions", "Comp."],
  ["throwaways", "Turns"],
];

/** Anyone's profile as a dashboard: who they are on the left, what they've done on the right. */
export default async function Player({ params }: Props) {
  const { uid } = await params;
  const { profile, posts } = await load(uid);
  const name = profile.name || "Player";
  const first = name.split(" ")[0];
  const seasons = Object.entries(profile.stats ?? {}).sort(([a], [b]) => b.localeCompare(a));
  const follow = <FollowButton targetId={uid} isPrivate={profile.private} signUpNext={`/players/${uid}`} />;

  if (profile.private) {
    return (
      <div className="page page-wide">
        <DashboardLayout side={<ProfileCard profile={profile} actions={follow} />}>
          <div className="card">
            <h2 className="card-title">This profile is private</h2>
            <p className="muted small">
              {first} shares their stats, teams and posts with the people they approve. Ask to follow, and{" "}
              {first} can accept you.
            </p>
          </div>
        </DashboardLayout>
      </div>
    );
  }

  const side = (
    <>
      <ProfileCard profile={profile} actions={follow} />
      {profile.visibility?.stats !== false && <StatTiles stats={profile.stats} />}
      {profile.visibility?.teams !== false && (
        <TeamList teams={(profile.teams ?? []).map((t) => ({ id: t.id, name: t.name, subtitle: t.subtitle }))} />
      )}
    </>
  );

  return (
    <div className="page page-wide">
      <DashboardLayout side={side}>
        {seasons.length > 0 && (
          <div className="card">
            <h2 className="card-title">Career</h2>
            <div className="table-scroll">
              <table className="stats-table">
                <thead>
                  <tr>
                    <th>Season</th>
                    {statColumns.map(([, label]) => (
                      <th key={label}>{label}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {seasons.map(([season, s]) => (
                    <tr key={season}>
                      <td>{season}</td>
                      {statColumns.map(([k]) => (
                        <td key={k}>{s[k] ?? 0}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {profile.games && profile.games.length > 0 && (
          <div className="card">
            <h2 className="card-title">Recent games</h2>
            <ul className="game-list">
              {profile.games.map((g, i) => (
                <li key={i}>
                  <b>
                    {g.teamName ?? "Team"} vs {g.opponent ?? "opponent"}
                    {g.ourScore !== undefined && g.theirScore !== undefined ? ` · ${g.ourScore}–${g.theirScore}` : ""}
                  </b>
                  <small>
                    <LocalTime iso={g.date} />
                    {g.line ? ` · ${g.line}` : ""}
                  </small>
                </li>
              ))}
            </ul>
          </div>
        )}

        <h2 className="section-title">Posts</h2>
        {posts.length === 0 ? (
          <p className="empty">No posts yet.</p>
        ) : (
          <div className="stack">
            {posts.map((p) => (
              <PostCard key={p.id} post={p} />
            ))}
          </div>
        )}
        <ForVisitors>
          <div className="cta-card">
            <p>Sign up to see more from {first} and follow along.</p>
            {follow}
          </div>
        </ForVisitors>
      </DashboardLayout>
    </div>
  );
}
