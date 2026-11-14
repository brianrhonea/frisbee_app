"use client";
import type { MeHome, PostPage, PublicPost } from "@stall10/shared";
import type { User } from "firebase/auth";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { onHomeRefresh } from "@/lib/homeRefresh";
import { ApiError, callApi } from "@/lib/client";
import { Composer } from "./Composer";
import { EventItem } from "./EventItem";
import { LocalTime } from "./LocalTime";
import { BrandCard, LearnPromo, PickupCard } from "./HomeCards";
import { PostCard } from "./PostCard";
import { SideTeams } from "./SideTeams";
import { UsernameStep } from "./UsernameStep";

const rsvpLabels: Record<string, string> = { going: "Going", maybe: "Maybe", notGoing: "Not going" };

type Tab = "following" | "community";
type Feed = { posts: PublicPost[]; next: number | null; busy: boolean; error: boolean };
const emptyFeed: Feed = { posts: [], next: null, busy: false, error: false };

/** "Friday, November 14", in the member's time zone once in the browser. */
function useToday() {
  const [today, setToday] = useState("");
  useEffect(() => setToday(new Date().toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })), []);
  return today;
}

/**
 * A signed-in member's home: a composer and their feed (people they follow,
 * or the whole community), with what's coming up on their teams beside it.
 */
export function Dashboard({ user }: { user: User }) {
  const [home, setHome] = useState<MeHome | null>(null);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<Tab>("following");
  const [older, setOlder] = useState<Feed>(emptyFeed);
  const [community, setCommunity] = useState<Feed | null>(null);
  const today = useToday();

  const load = useCallback(async () => {
    setError("");
    try {
      const h = await callApi<MeHome>(user, "/v1/me/home");
      setHome(h);
      setOlder({ ...emptyFeed, next: h.feed.next });
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Couldn't load your home. Try again.");
    }
  }, [user]);

  const loadCommunity = useCallback(
    async (before?: number) => {
      setCommunity((c) => ({ ...(c ?? emptyFeed), busy: true, error: false }));
      try {
        const page = await callApi<PostPage>(user, before ? `/v1/feed?before=${before}` : "/v1/feed");
        setCommunity((c) => ({
          posts: before ? [...(c?.posts ?? []), ...page.posts.filter((p) => !c?.posts.some((x) => x.id === p.id))] : page.posts,
          next: page.next,
          busy: false,
          error: false,
        }));
      } catch {
        setCommunity((c) => ({ ...(c ?? emptyFeed), busy: false, error: true }));
      }
    },
    [user],
  );

  useEffect(() => {
    void load();
  }, [load]);

  const communityLoaded = community !== null;
  // Home clicked again: back to the top, with the newest posts.
  useEffect(
    () =>
      onHomeRefresh(() => {
        window.scrollTo({ top: 0, behavior: "smooth" });
        void load();
        if (communityLoaded) void loadCommunity();
      }),
    [load, loadCommunity, communityLoaded],
  );

  // "Create a post" from another page lands here with #compose.
  useEffect(() => {
    if (!home || window.location.hash !== "#compose") return;
    const box = document.querySelector<HTMLTextAreaElement>(".composer textarea");
    box?.scrollIntoView({ block: "center" });
    box?.focus({ preventScroll: true });
    history.replaceState(null, "", "/");
  }, [home]);

  function pickTab(t: Tab) {
    setTab(t);
    if (t === "community" && !community) void loadCommunity();
  }

  async function loadOlder() {
    if (older.next === null) return;
    setOlder((o) => ({ ...o, busy: true, error: false }));
    try {
      const h = await callApi<MeHome>(user, `/v1/me/home?before=${older.next}`);
      setOlder((o) => ({ ...o, posts: [...o.posts, ...h.feed.posts], next: h.feed.next, busy: false }));
    } catch {
      setOlder((o) => ({ ...o, busy: false, error: true }));
    }
  }

  if (error) {
    return (
      <div className="page">
        <div className="card">
          <p className="form-error">{error}</p>
          <button className="btn btn-small" type="button" onClick={() => void load()}>
            Try again
          </button>
        </div>
      </div>
    );
  }
  if (!home) return <div className="page dash-loading" aria-busy="true">Loading your home…</div>;

  const { profile, teams, events } = home;
  const following = [...home.feed.posts, ...older.posts];
  const shown: Feed =
    tab === "following" ? { ...older, posts: following } : (community ?? { ...emptyFeed, busy: true });
  const first = (user.displayName || profile.name || "").trim().split(/\s+/)[0];

  return (
    <div className="page huddle">
      <div className="huddle-main">
        <header className="huddle-head">
          <div>
            <h1>Your daily huddle.</h1>
            <p>{first ? `Welcome back, ${first}. ` : ""}Good throws. Great people. You&apos;re in the right place.</p>
          </div>
          {today && <span className="pill pill-date">{today}</span>}
        </header>

        {profile.needsUsername && <UsernameStep user={user} onDone={() => void load()} />}

        <div className="card composer-card">
          <Composer
            onSaved={() => {
              void load();
              if (community) void loadCommunity();
            }}
          />
        </div>

        <div className="feed-tabs" role="tablist" aria-label="Feed">
          {(
            [
              ["following", "Following"],
              ["community", "Community"],
            ] as const
          ).map(([t, label]) => (
            <button
              key={t}
              type="button"
              role="tab"
              aria-selected={tab === t}
              className={tab === t ? "on" : undefined}
              onClick={() => pickTab(t)}
            >
              {label}
            </button>
          ))}
        </div>

        <div role="tabpanel" aria-label={tab === "following" ? "Following" : "Community"}>
          {shown.posts.length === 0 ? (
            shown.busy ? (
              <p className="empty" aria-busy="true">
                Loading posts…
              </p>
            ) : shown.error ? (
              <p className="post-error">Couldn&apos;t load posts. Try again.</p>
            ) : (
              <div className="card">
                <p className="muted small">
                  {tab === "following" ? (
                    <>
                      Posts from you and the people you follow show up here.{" "}
                      <button type="button" className="link-button" onClick={() => pickTab("community")}>
                        See the community
                      </button>{" "}
                      or <Link href="/explore">find players to follow</Link>.
                    </>
                  ) : (
                    "No posts yet."
                  )}
                </p>
              </div>
            )
          ) : (
            <div className="stack">
              {shown.posts.map((p) => (
                <PostCard key={p.id} post={p} />
              ))}
            </div>
          )}
          {shown.posts.length > 0 && (
            <nav className="pager">
              {shown.next === null ? (
                <p className="empty">You&apos;re all caught up.</p>
              ) : (
                <button
                  className="btn"
                  type="button"
                  disabled={shown.busy}
                  onClick={() => void (tab === "following" ? loadOlder() : loadCommunity(shown.next ?? undefined))}
                >
                  {shown.busy ? "Loading…" : "Older posts"}
                </button>
              )}
              {shown.error && <p className="post-error">Couldn&apos;t load more posts. Try again.</p>}
            </nav>
          )}
        </div>
      </div>

      <aside className="huddle-side" aria-label="Coming up">
        <PickupCard />

        <div className="card">
          <div className="card-head">
            <h2 className="card-title">Upcoming events</h2>
            <Link className="see-all" href="/schedule">
              View all
            </Link>
          </div>
          {events.length === 0 ? (
            <p className="muted small">Nothing scheduled on your teams.</p>
          ) : (
            <div className="date-list">
              {events.map((e) => (
                <EventItem key={`${e.teamId}/${e.id}`} startsAt={e.startsAt} plain>
                  <b>{e.title || "Event"}</b>
                  <small>
                    <LocalTime iso={e.startsAt} style="dateTime" />
                    {e.location ? ` · ${e.location}` : ""}
                  </small>
                  <small>
                    <Link href={`/teams/${encodeURIComponent(e.teamId)}`}>{e.teamName}</Link>
                    {e.rsvp ? ` · ${rsvpLabels[e.rsvp] ?? e.rsvp}` : ""}
                  </small>
                </EventItem>
              ))}
            </div>
          )}
        </div>

        {teams.length === 0 && (
          <div className="card">
            <h2 className="card-title">Your teams</h2>
            <p className="muted small">
              Join a team with an invite link, or <Link href="/explore">find one near you</Link>.
            </p>
          </div>
        )}

        <LearnPromo />
        <p className="side-note">
          Made for the love of the game.
          <br />
          And the people who play it.
        </p>
      </aside>

      <div className="huddle-foot">
        <SideTeams inline />
        <BrandCard />
      </div>
    </div>
  );
}
