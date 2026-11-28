"use client";
import { type MemberProfilePage, type ProfilePage, profileStatsChoice, type StatTotals } from "@stall10/shared";
import { collection, getCountFromServer, limit, orderBy, query, where } from "firebase/firestore";
import { firestoreDb } from "@/lib/firebase";
import { SummaryTiles } from "@/components/ui/SummaryTiles";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { ApiError, callApi, problem } from "@/lib/client";
import { type Signal, useChangeSignal, useLiveDoc } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { FollowButton } from "./FollowButton";
import { ForVisitors } from "./ForVisitors";
import { LocalTime } from "./LocalTime";
import { MessageButton } from "./MessageButton";
import { unblockPerson, useBlocks } from "@/lib/moderation";
import { BlockButton, ReportButton } from "./Report";
import { PostCard } from "./PostCard";
import { DashboardLayout, ProfileCard, StatTiles, TeamList } from "./ProfileDashboard";
import { useConfirm } from "@/components/ui/ConfirmDialog";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { Button } from "@/components/ui/Button";
import { RosterSpots } from "./RosterSpots";

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
  // Every post for the member's own page or a private profile they're an
  // accepted follower of (the rules check the follow); else public ones
  // only, which the rules let anyone read (S1).
  const allPosts = user?.uid === uid || privateDetails;
  const signals: Signal[] | null = user
    ? [
        { doc: `profiles/${uid}` },
        { doc: `users/${user.uid}/follows/user_${uid}` },
        {
          collection: "posts",
          constraints: [
            where("authorId", "==", uid),
            ...(allPosts ? [] : [where("private", "==", false)]),
            orderBy("createdAt", "desc"),
            limit(20),
          ],
        },
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
  useEffect(() => {
    setMember(null);
    setFailed(null);
  }, [uid]);

  if (!member) {
    return failed?.notFound ? (
      <div className="page">
        <EmptyState title="Player not found">This player couldn&apos;t be found.</EmptyState>
      </div>
    ) : failed ? (
      <div className="page">
        <ErrorState
          onRetry={() => {
            setFailed(null);
            setAttempt((n) => n + 1);
          }}
        >
          {failed.text}
        </ErrorState>
      </div>
    ) : (
      <div className="page">
        <LoadingState />
      </div>
    );
  }
  return <PlayerView uid={uid} page={member} locked={member.locked} />;
}

/** The most posts the rules let one query list (capped(50)), so the most a count can say. */
const postCountCap = 50;

/**
 * How many posts this member may see of [uid]'s: a Firestore count of the same query the posts list reads
 * (no orderBy, so no index; the posts rule only lists up to 50, so the count stops there and the tile says "50+"), every post for their own page or a private profile they follow, else the
 * public ones. Null until it is known (or when it can't be counted): the tile is then left out.
 */
function usePostCount(uid: string, all: boolean, enabled: boolean, refetchOn: string): number | null {
  const [count, setCount] = useState<number | null>(null);
  useEffect(() => {
    const db = firestoreDb();
    if (!enabled || !db) {
      setCount(null);
      return;
    }
    let live = true;
    getCountFromServer(query(collection(db, "posts"), where("authorId", "==", uid), ...(all ? [] : [where("private", "==", false)]), limit(postCountCap))).then(
      (snap) => live && setCount(snap.data().count),
      () => live && setCount(null),
    );
    return () => {
      live = false;
    };
  }, [uid, all, enabled, refetchOn]);
  return count;
}

/** The page for one player once loaded (exported for the component tests). */
export function PlayerView({ uid, page, locked }: { uid: string; page: ProfilePage; locked: boolean }) {
  const askConfirm = useConfirm();
  const { profile, posts } = page;
  const name = profile.name || "Player";
  const first = name.split(" ")[0];
  // The Team filter (the app's too): one team's numbers, kept in ?team=.
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const choice = profileStatsChoice(profile, params.get("team"));
  const pickTeam = (team: string) => {
    const next = new URLSearchParams(params.toString());
    if (team) next.set("team", team);
    else next.delete("team");
    const q = next.toString();
    router.replace(q ? `${pathname}?${q}` : pathname, { scroll: false });
  };
  const picked = choice.options.find((t) => t.id === choice.team);
  const seasons = Object.entries(choice.seasons).sort(([a], [b]) => b.localeCompare(a));
  const career = seasons.reduce<StatTotals>((sum, [, s]) => {
    const out: StatTotals = { ...sum };
    for (const [k] of statColumns) out[k] = (sum[k] ?? 0) + (s[k] ?? 0);
    return out;
  }, {});
  const { user } = useAuth();
  const blocks = useBlocks(user);
  // The "Stall 10 staff" badge (written only by firebase/scripts/set-staff.mjs).
  const staff = useLiveDoc(user ? `staff/${uid}` : null).data != null;
  const postCount = usePostCount(uid, user?.uid === uid || profile.private === true, !!user && !locked && !blocks.hides(uid), posts.map((p) => p.id).join(","));
  const follow = <FollowButton targetId={uid} isPrivate={profile.private === true} signUpNext={`/players/${uid}`} />;
  const someoneElse = !!user && user.uid !== uid;
  // Report and Block, for anyone else's profile (the app's ⋯ menu).
  const safety = someoneElse && (
    <span className="profile-safety">
      <ReportButton target={{ kind: "user", uid }} authorName={name} className="btn btn-ghost btn-small" />
      {!blocks.hides(uid) && <BlockButton uid={uid} name={name} label="Block" className="btn btn-ghost btn-small danger" />}
    </span>
  );
  // Follow and Message, as the app's profile header has them.
  const actions = (
    <>
      {follow}
      <MessageButton uid={uid} />
    </>
  );

  // Blocked either way: only the name, as in the app.
  if (someoneElse && blocks.hides(uid)) {
    const mine = blocks.blockedByMe(uid);
    return (
      <div className="page page-wide player-page">
        <ProfileCard profile={{ ...profile, bio: undefined, teams: [] }} secondary={safety} />
        <EmptyState
          title={mine ? `You blocked ${first}` : "You can't see this profile"}
          action={
            mine && user ? (
              <Button
                onClick={async () => {
                  if ((await askConfirm({ title: `Unblock ${first}?`, message: "You'll see each other's posts and can follow and message again.", confirmLabel: "Unblock" }))) {
                    void unblockPerson(user, uid).catch((e) => alert((e as Error).message));
                  }
                }}
              >
                Unblock
              </Button>
            ) : undefined
          }
        >
          {mine
            ? `You don't see each other's posts, comments or messages, and neither of you can follow or message the other.`
            : `${first}'s posts and details aren't available to you.`}
        </EmptyState>
      </div>
    );
  }

  if (locked) {
    return (
      <div className="page page-wide player-page">
        <ProfileCard profile={profile} actions={actions} secondary={safety} staff={staff} />
        <EmptyState title="This profile is private">
          {first} shares their stats, teams and posts with the people they approve. Ask to follow, and {first} can accept you.
        </EmptyState>
      </div>
    );
  }

  const side = (
    <>
      {profile.visibility?.stats !== false && <StatTiles stats={choice.seasons} teamName={picked?.name} />}
      {profile.visibility?.teams !== false && (
        <TeamList teams={(profile.teams ?? []).map((t) => ({ id: t.id, name: t.name, subtitle: t.subtitle }))} />
      )}
      {user?.uid === uid && <RosterSpots uid={uid} />}
    </>
  );

  return (
    <div className="page page-wide player-page">
      <ProfileCard
        profile={profile}
        actions={actions}
        secondary={safety}
        staff={staff}
        counts={postCount === null ? undefined : <SummaryTiles label="Activity" items={[{ id: "posts", label: postCount === 1 ? "Post" : "Posts", value: postCount >= postCountCap ? `${postCountCap}+` : postCount }]} />}
      />
      <DashboardLayout side={side}>
        {seasons.length > 0 && profile.visibility?.stats !== false && (
          <div className="card">
            <div className="card-head">
              <h2 className="card-title">{picked ? `Career · ${picked.name}` : "Career"}</h2>
              {choice.options.length > 0 && (
                <label className="stats-team-filter">
                  <span className="sr-only">Team</span>
                  <select value={choice.team ?? ""} onChange={(e) => pickTeam(e.target.value)}>
                    <option value="">All teams</option>
                    {choice.options.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.name}
                      </option>
                    ))}
                  </select>
                </label>
              )}
            </div>
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
                  {seasons.length > 1 && (
                    <tr className="stats-total">
                      <td>Career</td>
                      {statColumns.map(([k]) => (
                        <td key={k}>{career[k] ?? 0}</td>
                      ))}
                    </tr>
                  )}
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
          <EmptyState>No posts yet.</EmptyState>
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
