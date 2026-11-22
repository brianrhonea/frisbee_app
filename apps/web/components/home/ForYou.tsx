"use client";
// Home's "Following" (once For you) and "Your teams" feeds (the app's
// HomeScreen tabs), and the new-member checklist they show while empty.
import { limit } from "firebase/firestore";
import Link from "next/link";
import { PostCard } from "@/components/PostCard";
import { TeamPostCard } from "@/components/team/TeamPostCard";
import { useLiveQuery } from "@/lib/live";
import { useMyTeams } from "../useMyTeams";
import { StartOrJoinButton } from "./StartOrJoin";
import { FeedPager } from "./useInfiniteFeed";
import { noUserPages, type UserPages, useForYou } from "./useForYou";
import "./home_feed.css";

type Feed = ReturnType<typeof useForYou>;

/** The feed's posts, newest first, ending in the pager. */
function FeedList({ feed, busy, error }: { feed: Feed; busy: boolean; error: boolean }) {
  return (
    <>
      <div className="stack">
        {feed.items.map((item) =>
          item.kind === "user" ? (
            <PostCard key={item.id} post={item.post} />
          ) : (
            <div key={item.id} className="feed-team-post">
              <Link className="feed-team-link" href={`/teams/${encodeURIComponent(item.teamId)}`}>
                {item.teamName}
              </Link>
              <TeamPostCard post={item.post} teamName={item.teamName} showAudience={item.member} />
            </div>
          ),
        )}
      </div>
      <FeedPager hasMore={feed.hasMore} busy={feed.loadingMore || busy} error={error} count={feed.items.length} loadMore={feed.loadMore} />
    </>
  );
}

const loading = (
  <p className="empty" aria-busy="true">
    Loading posts…
  </p>
);

export function ForYouFeed({
  uid,
  users,
  needsUsername,
  onCommunity,
}: {
  uid: string;
  users: UserPages & { busy: boolean; error: boolean };
  /** The member hasn't picked a username yet (Home shows that step above). */
  needsUsername: boolean;
  onCommunity: () => void;
}) {
  const teams = useMyTeams(uid);
  const feed = useForYou(uid, teams.data ?? (teams.error ? [] : undefined), users);

  if (feed.items.length > 0) {
    return (
      <>
        {/* No team yet (as the app's For you): the checklist covers it on an empty feed. */}
        {teams.data?.length === 0 && <JoinCard />}
        <FeedList feed={feed} busy={users.busy} error={users.error} />
      </>
    );
  }
  if (!feed.loaded || users.busy) return loading;
  if (users.error) return <p className="post-error">Couldn&apos;t load posts. Try again.</p>;
  const steps = onboardingSteps({ needsUsername, onTeam: (teams.data ?? []).length > 0, followsAnything: feed.followsAnything });
  if (steps.some((s) => !s.done)) return <GetStarted steps={steps} />;
  return (
    <div className="card">
      <p className="muted small">
        No posts yet. News you follow shows up here.{" "}
        <button type="button" className="link-button" onClick={onCommunity}>
          See everyone&apos;s posts
        </button>{" "}
        or <Link href="/explore">find people and teams to follow</Link>.
      </p>
    </div>
  );
}

/**
 * Every post of the member's teams and groups, newest first (the app's
 * "Your teams" tab, Home's first). Without a team yet, the new-member
 * checklist, as this is the tab a new member lands on.
 */
export function TeamsFeed({ uid, needsUsername }: { uid: string; needsUsername: boolean }) {
  const teams = useMyTeams(uid);
  const feed = useForYou(uid, teams.data ?? (teams.error ? [] : undefined), noUserPages, { teamsOnly: true });
  const noTeam = teams.data?.length === 0;
  // Whether they follow anything yet, for the checklist (one document is enough).
  const follows = useLiveQuery(noTeam ? `users/${uid}/follows` : null, [limit(1)], `${uid}:any`);

  if (feed.items.length > 0) return <FeedList feed={feed} busy={false} error={false} />;
  if (!feed.loaded) return loading;
  if (noTeam) {
    if (follows.data === undefined && !follows.error) return loading;
    const steps = onboardingSteps({ needsUsername, onTeam: false, followsAnything: (follows.data ?? []).length > 0 });
    return <GetStarted steps={steps} />;
  }
  return (
    <div className="card">
      <p className="muted small">No team posts yet. News your teams and communities post shows up here.</p>
    </div>
  );
}

/** No team yet: join with a code, find a group, or start one (the app's _JoinCard). */
function JoinCard() {
  return (
    <div className="card promo-card join-card">
      <small>No team yet</small>
      <b>Join your team.</b>
      <p>Get the schedule, playbook and stats your team shares. Ask a coach for the invite code, find a pickup community, or start your own.</p>
      <div className="join-card-actions">
        <StartOrJoinButton className="btn btn-primary btn-small" join>
          Join with code
        </StartOrJoinButton>
        <Link className="btn btn-small" href="/explore?only=groups">
          Find a group
        </Link>
        <Link className="btn btn-small" href="/teams/new">
          Create team
        </Link>
      </div>
    </div>
  );
}

export interface OnboardingStep {
  id: "username" | "join" | "find" | "follow";
  label: string;
  done: boolean;
}

/**
 * The new-member checklist's steps (the app's onboardingSteps, same order
 * and rules): a username; joining or creating a team and finding one are
 * done once they're on any team (by code, by finding it or by creating it);
 * following once they follow anything.
 */
export function onboardingSteps({ needsUsername, onTeam, followsAnything }: { needsUsername: boolean; onTeam: boolean; followsAnything: boolean }): OnboardingStep[] {
  return [
    { id: "username", label: "Pick a username", done: !needsUsername },
    { id: "join", label: "Join or create a team", done: onTeam },
    { id: "find", label: "Find a team or community near you", done: onTeam },
    { id: "follow", label: "Follow people", done: followsAnything },
  ];
}

/** "Get started": the checklist on an empty For you feed. */
function GetStarted({ steps }: { steps: OnboardingStep[] }) {
  const done = steps.filter((s) => s.done).length;
  const action = (s: OnboardingStep) => {
    if (s.done) return null;
    switch (s.id) {
      case "username":
        return (
          <a className="btn btn-small" href="#username">
            Pick one
          </a>
        );
      case "join":
        return (
          <StartOrJoinButton className="btn btn-small">Join or create</StartOrJoinButton>
        );
      case "find":
        return (
          <Link className="btn btn-small" href="/explore?only=teams">
            Find
          </Link>
        );
      case "follow":
        return (
          <Link className="btn btn-small" href="/explore?only=players">
            Find people
          </Link>
        );
    }
  };
  return (
    <section className="card get-started" aria-labelledby="get-started-title">
      <div className="card-head">
        <h2 className="card-title" id="get-started-title">
          Get started
        </h2>
        <span className="muted small">
          {done} of {steps.length} done
        </span>
      </div>
      <p className="muted small">Your feed fills up with news from your teams and the people you follow.</p>
      <ol className="get-started-list">
        {steps.map((s) => (
          <li key={s.id} className={s.done ? "done" : undefined}>
            <span className="get-started-check" aria-hidden="true">
              {s.done ? "✓" : ""}
            </span>
            <span className="get-started-label">
              {s.label}
              {s.done && <span className="sr-only"> (done)</span>}
            </span>
            {action(s)}
          </li>
        ))}
      </ol>
    </section>
  );
}
