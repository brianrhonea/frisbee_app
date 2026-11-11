import type { ProfilePage, StatTotals } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { cache } from "react";
import { Avatar } from "@/components/Avatar";
import { LocalTime } from "@/components/LocalTime";
import { PostCard } from "@/components/PostCard";
import { getPublic } from "@/lib/api";

type Props = {
  params: Promise<{ uid: string }>;
  searchParams: Promise<{ before?: string }>;
};

const load = cache((uid: string, before?: number) =>
  getPublic<ProfilePage>(`/v1/public/players/${encodeURIComponent(uid)}`, { before }),
);

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

export default async function Player({ params, searchParams }: Props) {
  const { uid } = await params;
  const before = Number((await searchParams).before) || undefined;
  const { profile, posts, next } = await load(uid, before);
  const name = profile.name || "Player";
  const seasons = Object.entries(profile.stats ?? {}).sort(([a], [b]) => b.localeCompare(a));
  const facts = [
    profile.pronouns,
    profile.hometown,
    profile.school,
    profile.throwingHand && `Throws ${profile.throwingHand}`,
    profile.playingSince && `Playing since ${profile.playingSince}`,
  ].filter(Boolean);

  return (
    <div className="page">
      <header className="profile-head">
        <Avatar name={name} url={profile.photoUrl} size={84} />
        <div>
          <h1>{name}</h1>
          {profile.username && <p className="muted" style={{ margin: 0 }}>@{profile.username}</p>}
          {facts.length > 0 && (
            <ul className="profile-facts">
              {facts.map((f) => (
                <li key={String(f)}>{f}</li>
              ))}
            </ul>
          )}
        </div>
      </header>

      {profile.private ? (
        <p className="empty">This profile is private.</p>
      ) : (
        <>
          {profile.bio && <p className="bio">{profile.bio}</p>}
          <div className="cta-card">
            <p>Follow {name.split(" ")[0]} on Stall 10.</p>
            <Link className="btn btn-primary btn-small" href={`/sign-up?next=${encodeURIComponent(`/players/${uid}`)}`}>
              Sign up to follow
            </Link>
          </div>

          {profile.teams && profile.teams.length > 0 && (
            <>
              <h2 className="section-title">Teams</h2>
              <div className="stack">
                {profile.teams.map((t) => (
                  <Link key={t.id} className="row-card" href={`/teams/${encodeURIComponent(t.id)}`}>
                    <Avatar name={t.name} />
                    <span>
                      <b>{t.name}</b>
                      <small>
                        {[t.subtitle, t.number !== undefined ? `#${t.number}` : null, t.position]
                          .filter(Boolean)
                          .join(" · ")}
                      </small>
                    </span>
                  </Link>
                ))}
              </div>
            </>
          )}

          {seasons.length > 0 && (
            <>
              <h2 className="section-title">Stats</h2>
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
            </>
          )}

          {profile.games && profile.games.length > 0 && (
            <>
              <h2 className="section-title">Recent games</h2>
              <div className="stack">
                {profile.games.map((g, i) => (
                  <div key={i} className="row-card">
                    <span>
                      <b>
                        {g.teamName ?? "Team"} vs {g.opponent ?? "opponent"}
                        {g.ourScore !== undefined && g.theirScore !== undefined
                          ? ` · ${g.ourScore}–${g.theirScore}`
                          : ""}
                      </b>
                      <small>
                        <LocalTime iso={g.date} />
                        {g.line ? ` · ${g.line}` : ""}
                      </small>
                    </span>
                  </div>
                ))}
              </div>
            </>
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
          {next !== null && (
            <nav className="pager">
              <Link className="btn" href={`/players/${encodeURIComponent(uid)}?before=${next}`}>
                Older posts
              </Link>
            </nav>
          )}
        </>
      )}
    </div>
  );
}
