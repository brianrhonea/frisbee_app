"use client";
import type { MemberProfilePage, ProfilePage, StatTotals } from "@stall10/shared";
import { limit, orderBy, where } from "firebase/firestore";
import { useEffect, useState } from "react";
import { ApiError, callApi, problem } from "@/lib/client";
import { type Signal, useChangeSignal } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { FollowButton } from "./FollowButton";
import { ForVisitors } from "./ForVisitors";
import { LocalTime } from "./LocalTime";
import { MessageButton } from "./MessageButton";
import { PostCard } from "./PostCard";
import { DashboardLayout, ProfileCard, StatTiles, TeamList } from "./ProfileDashboard";

const statColumns: Array<[keyof StatTotals, string]> = [
  ["games", "Games"],
  ["points", "Points"],
  ["goals", "Goals"],
  ["assists", "Assists"],
  ["blocks", "Blocks"],
  ["completions", "Comp."],
  ["throwaways", "Turns"],
];

/**
 * A player's page, for members only (visitors are asked to sign up). A
 * member gets it as they may see it (`/v1/players/:uid`: a private profile
 * they follow in full), refetched whenever the profile, the player's
 * posts or the member's follow of them changes, so privacy switches,
 * edits and an accepted request show within a moment.
 */
export function LivePlayer({ uid }: { uid: string }) {
  const { user } = useAuth();
  const [member, setMember] = useState<MemberProfilePage | null>(null);
  // Why it isn't showing: not found (404), or a failure to retry.
  const [failed, setFailed] = useState<{ notFound: boolean; text: string } | null>(null);
  const [attempt, setAttempt] = useState(0);
  const unlocked = member ? !member.locked : false;
  const privateDetails = unlocked && member?.profile.private === true;
  const signals: Signal[] | null = user
    ? [
        { doc: `profiles/${uid}` },
        { doc: `users/${user.uid}/follows/user_${uid}` },
        { collection: "posts", constraints: [where("authorId", "==", uid), orderBy("createdAt", "desc"), limit(20)] },
        // A private profile's details: only once the rules let this member read them.
        ...(privateDetails ? [{ doc: `profiles/${uid}/private/details` }] : []),
      ]
    : null;
  // Every signal's shape is in the key, so the private details' signal starts and stops with it.
  const version = useChangeSignal(signals, user ? `${user.uid}|${uid}|${privateDetails}` : "");

  useEffect(() => {
    if (!user) {
      setMember(null);
      setFailed(null);
      return;
    }
    let live = true;
    // Several signals fire together (e.g. on subscribing): fetch once.
    const timer = setTimeout(() => {
      callApi<MemberProfilePage>(user, `/v1/players/${encodeURIComponent(uid)}`).then(
        (page) => {
          if (!live) return;
          setMember(page);
          setFailed(null);
        },
        (e) => {
          if (live) setFailed({ notFound: e instanceof ApiError && e.status === 404, text: problem(e, "Couldn't load this profile. Check your connection and try again.") });
        },
      );
    }, 150);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [user, uid, version, attempt]);
  // Another player: don't show the last one while this one loads.
  useEffect(() => setMember(null), [uid]);

  if (!member) {
    return failed?.notFound ? (
      <div className="page">
        <p className="empty">This player couldn&apos;t be found.</p>
      </div>
    ) : failed ? (
      <div className="page">
        <p className="form-error">{failed.text}</p>
        <button
          type="button"
          className="btn btn-small"
          onClick={() => {
            setFailed(null);
            setAttempt((n) => n + 1);
          }}
        >
          Try again
        </button>
      </div>
    ) : (
      <div className="page">
        <p className="muted" aria-busy="true">Loading…</p>
      </div>
    );
  }
  return <PlayerView uid={uid} page={member} locked={member.locked} />;
}

function PlayerView({ uid, page, locked }: { uid: string; page: ProfilePage; locked: boolean }) {
  const { profile, posts } = page;
  const name = profile.name || "Player";
  const first = name.split(" ")[0];
  const seasons = Object.entries(profile.stats ?? {}).sort(([a], [b]) => b.localeCompare(a));
  const follow = <FollowButton targetId={uid} isPrivate={profile.private === true} signUpNext={`/players/${uid}`} />;
  // Follow and Message, as the app's profile header has them.
  const actions = (
    <>
      {follow}
      <MessageButton uid={uid} />
    </>
  );

  if (locked) {
    return (
      <div className="page page-wide">
        <DashboardLayout side={<ProfileCard profile={profile} actions={actions} />}>
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
      <ProfileCard profile={profile} actions={actions} />
      {profile.visibility?.stats !== false && <StatTiles stats={profile.stats} />}
      {profile.visibility?.teams !== false && (
        <TeamList teams={(profile.teams ?? []).map((t) => ({ id: t.id, name: t.name, subtitle: t.subtitle }))} />
      )}
    </>
  );

  return (
    <div className="page page-wide">
      <DashboardLayout side={side}>
        {seasons.length > 0 && profile.visibility?.stats !== false && (
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

        {profile.visibility?.games !== false && profile.games && profile.games.length > 0 && (
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
