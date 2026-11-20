"use client";
import type { MeHome, MyEvent, PostPage, PublicPost } from "@stall10/shared";
import type { User } from "firebase/auth";
import Link from "next/link";
import { type KeyboardEvent, useCallback, useEffect, useRef, useState } from "react";
import { newPostBox, onHomeRefresh } from "@/lib/homeRefresh";
import { callApi, problem } from "@/lib/client";
import { type Audience, Composer } from "./Composer";
import { EventItem } from "./EventItem";
import { LocalTime } from "./LocalTime";
import { LearnPromo, PickupCard } from "./HomeCards";
import { PostCard } from "./PostCard";
import { UsernameStep } from "./UsernameStep";
import { ForYouFeed, TeamsFeed } from "./home/ForYou";
import { NeedsYou } from "./home/NeedsYou";
import { TeamStrip } from "./home/TeamStrip";
import { FeedPager } from "./home/useInfiniteFeed";
import { TeamInvites } from "./TeamInvites";
import { canOn } from "./tournaments/useTournament";
import { TournamentDayCard } from "./tournaments/TournamentDayCard";
import { useTournamentDays } from "./tournaments/useTournamentDays";
import { useMyTeams } from "./useMyTeams";
import { needsRsvp, RsvpPill } from "./RsvpPill";
import "./member.css";

const rsvpLabels: Record<string, string> = { going: "Going", maybe: "Maybe", notGoing: "Can't go" };

/**
 * The feed's tabs, as the app's Home: the member's teams first (the
 * default), then what they follow (once For you: people, teams and
 * communities they follow, and their teams), then everyone's posts (once
 * Community).
 */
export type Tab = "teams" | "following" | "everyone";
const tabs: Array<[Tab, string]> = [
  ["teams", "Your teams"],
  ["following", "Following"],
  ["everyone", "Everyone"],
];
/** The default tab, which the address leaves out. */
const defaultTab: Tab = "teams";
/** Old `?tab=` names, from links made before the tabs were renamed. */
const oldTabs: Record<string, Tab> = { foryou: "following", community: "everyone" };

/** The tab a `?tab=` value names (old names too); the default for none or an unknown one. */
export function parseTab(value: string | null | undefined): Tab {
  if (value === "teams" || value === "following" || value === "everyone") return value;
  return (value && oldTabs[value]) || defaultTab;
}

/** The tab in the URL (?tab=), so it's linkable and survives a reload. */
function tabFromUrl(): Tab {
  if (typeof window === "undefined") return defaultTab;
  return parseTab(new URLSearchParams(window.location.search).get("tab"));
}
type Feed = { posts: PublicPost[]; next: number | null; busy: boolean; error: boolean };
const emptyFeed: Feed = { posts: [], next: null, busy: false, error: false };

/** "Good morning, Sam", by the member's clock once in the browser. */
function useGreeting(first: string) {
  const [hello, setHello] = useState("");
  useEffect(() => {
    const h = new Date().getHours();
    setHello(h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening");
  }, []);
  if (!hello) return first ? `Welcome back, ${first}` : "Welcome back";
  return first ? `${hello}, ${first}` : hello;
}

/** The teams the member may post on from Home: those they manage (the app's postableTeams), by name. */
function useAudiences(uid: string): Audience[] {
  const teams = useMyTeams(uid);
  return (teams.data ?? [])
    .filter((t) => canOn(t, uid, "manageTeam"))
    .map((t) => ({ id: t.id, name: t.name ?? "Team", privateGroup: (t.kind ?? "team") !== "team" && t.requiresApproval === true }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * A signed-in member's home, like a social feed: a greeting, their teams
 * in a strip (where the sidebar doesn't list them), then the feed (their
 * teams' posts, what they follow, or everyone's) under the composer (to
 * Everyone or a team they run), loading as it scrolls. Beside it: invitations, join requests waiting on them, what's
 * coming up and one promo; on phones the invitations and next event come
 * above the feed.
 */
export function Dashboard({ user }: { user: User }) {
  const [home, setHome] = useState<MeHome | null>(null);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<Tab>(defaultTab);
  const [older, setOlder] = useState<Feed>(emptyFeed);
  const [community, setCommunity] = useState<Feed | null>(null);
  const audiences = useAudiences(user.uid);
  const tournamentDays = useTournamentDays(user.uid);
  const tabRefs = useRef<Partial<Record<Tab, HTMLButtonElement | null>>>({});

  const load = useCallback(async () => {
    setError("");
    try {
      const h = await callApi<MeHome>(user, "/v1/me/home");
      setHome(h);
      setOlder({ ...emptyFeed, next: h.feed.next });
    } catch (e) {
      setError(problem(e, "Couldn't load your home. Try again."));
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
    const box = document.querySelector<HTMLTextAreaElement>(newPostBox);
    box?.scrollIntoView({ block: "center" });
    box?.focus({ preventScroll: true });
    history.replaceState(null, "", window.location.pathname + window.location.search); // Drops #compose, keeps ?tab=.
  }, [home]);

  function pickTab(t: Tab, push = true) {
    setTab(t);
    if (t === "everyone" && !community) void loadCommunity();
    if (push) {
      const url = new URL(window.location.href);
      if (t === defaultTab) url.searchParams.delete("tab");
      else url.searchParams.set("tab", t);
      history.replaceState(null, "", url.pathname + url.search + url.hash);
    }
  }

  // Open the tab the URL names (an old name is rewritten to the new one).
  useEffect(() => {
    const raw = new URLSearchParams(window.location.search).get("tab");
    const t = tabFromUrl();
    if (t !== defaultTab) pickTab(t, raw !== t);
    else if (raw) pickTab(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once, on load.
  }, []);

  /** Arrow keys, Home and End move along the tabs (the ARIA tabs pattern). */
  function onTabKey(e: KeyboardEvent<HTMLButtonElement>) {
    const i = tabs.findIndex(([t]) => t === tab);
    const to = ({ ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 } as Record<string, number>)[e.key];
    if (to === undefined) return;
    e.preventDefault();
    const [next] = tabs[(to + tabs.length) % tabs.length]!;
    pickTab(next);
    tabRefs.current[next]?.focus();
  }

  async function loadOlder() {
    if (older.next === null || older.busy) return;
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
  const shown: Feed = community ?? { ...emptyFeed, busy: true };
  const first = (user.displayName || profile.name || "").trim().split(/\s+/)[0] ?? "";

  return (
    <div className="page huddle">
      <div className="huddle-main">
        <Greeting first={first} />

        {profile.needsUsername && (
          <div id="username">
            <UsernameStep user={user} onDone={() => void load()} />
          </div>
        )}

        {/* Phones and tablets, where the sidebar's team list is hidden. */}
        <TeamStrip uid={user.uid} />

        {/* Phones: what needs an answer or is next, before the feed. */}
        <div className="huddle-phone">
          <TeamInvites />
          {/* On a tournament day the card takes the next event's place. */}
          {tournamentDays.length > 0
            ? tournamentDays.map((d) => <TournamentDayCard key={`${d.teamId}/${d.tournamentId}`} day={d} />)
            : events[0] && <NextEvent event={events[0]} />}
        </div>

        {/* What's the member's to do: join requests on groups they approve for. */}
        <NeedsYou uid={user.uid} />

        <div className="feed-tabs" role="tablist" aria-label="Feed">
          {tabs.map(([t, label]) => (
            <button
              key={t}
              ref={(el) => {
                tabRefs.current[t] = el;
              }}
              id={`feed-tab-${t}`}
              type="button"
              role="tab"
              aria-selected={tab === t}
              aria-controls={tab === t ? `feed-panel-${t}` : undefined}
              tabIndex={tab === t ? 0 : -1}
              className={tab === t ? "on" : undefined}
              onClick={() => pickTab(t)}
              onKeyDown={onTabKey}
            >
              {label}
            </button>
          ))}
        </div>

        {/* As in the app: post from Your teams and Following, not Everyone. */}
        {tab !== "everyone" && (
          <div className="card composer-card">
            <Composer
              audiences={audiences}
              onSaved={() => {
                void load();
                if (community) void loadCommunity();
              }}
            />
          </div>
        )}

        <div role="tabpanel" id={`feed-panel-${tab}`} aria-labelledby={`feed-tab-${tab}`} className="feed-panel">
          {tab === "following" && (
            <ForYouFeed
              uid={user.uid}
              users={{ posts: following, next: older.next, loadMore: loadOlder, busy: older.busy, error: older.error }}
              needsUsername={profile.needsUsername}
              onCommunity={() => pickTab("everyone")}
            />
          )}
          {tab === "teams" && <TeamsFeed uid={user.uid} needsUsername={profile.needsUsername} />}
          {tab === "everyone" &&
            (shown.posts.length === 0 ? (
              shown.busy ? (
                <p className="empty" aria-busy="true">
                  Loading posts…
                </p>
              ) : shown.error ? (
                <p className="post-error">Couldn&apos;t load posts. Try again.</p>
              ) : (
                <div className="card">
                  <p className="muted small">No posts yet.</p>
                </div>
              )
            ) : (
              <>
                <div className="stack">
                  {shown.posts.map((p) => (
                    <PostCard key={p.id} post={p} />
                  ))}
                </div>
                <FeedPager
                  hasMore={shown.next !== null}
                  busy={shown.busy}
                  error={shown.error}
                  count={shown.posts.length}
                  loadMore={() => loadCommunity(shown.next ?? undefined)}
                />
              </>
            ))}
        </div>
      </div>

      <aside className="huddle-side" aria-label="For you">
        <div className="huddle-side-invites">
          <TeamInvites />
        </div>
        {/* Phones show these above the feed (.huddle-phone). */}
        {tournamentDays.length > 0 && (
          <div className="huddle-side-days">
            {tournamentDays.map((d) => (
              <TournamentDayCard key={`${d.teamId}/${d.tournamentId}`} day={d} />
            ))}
          </div>
        )}

        <div className="card upcoming-card">
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
                  <span className="upcoming-title">
                    <b>{e.title || "Event"}</b>
                    <RsvpPill answer={e.rsvp} type={e.type} needs={needsRsvp(e.rsvp, e.startsAt, e.endsAt)} />
                  </span>
                  <small>
                    <LocalTime iso={e.startsAt} style="dateTime" />
                    {e.location ? ` · ${e.location}` : ""}
                  </small>
                  <small className="upcoming-team">
                    <span className="team-dot" aria-hidden="true" />
                    <Link href={`/teams/${encodeURIComponent(e.teamId)}`}>{e.teamName}</Link>
                  </small>
                </EventItem>
              ))}
            </div>
          )}
        </div>

        {/* One promo, last: pickup for someone without a team yet, else Learn. */}
        {teams.length === 0 ? <PickupCard /> : <LearnPromo />}
      </aside>
    </div>
  );
}

/** The page's heading: one line, "Good evening, Sam", and today's date beside it. */
function Greeting({ first }: { first: string }) {
  const text = useGreeting(first);
  const [today, setToday] = useState("");
  useEffect(() => setToday(new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })), []);
  return (
    <div className="huddle-head">
      <h1 className="huddle-greeting">{text}</h1>
      {today && <span className="huddle-date">{today}</span>}
    </div>
  );
}

/** The next event on the member's teams, for phones above the feed. */
function NextEvent({ event: e }: { event: MyEvent }) {
  return (
    <Link className="card next-event" href={`/teams/${encodeURIComponent(e.teamId)}/schedule?event=${encodeURIComponent(e.id)}`}>
      <small>Up next · {e.teamName}</small>
      <b>{e.title || "Event"}</b>
      <span className="muted small">
        <LocalTime iso={e.startsAt} style="dateTime" />
        {e.location ? ` · ${e.location}` : ""}
        {e.rsvp ? ` · ${rsvpLabels[e.rsvp] ?? e.rsvp}` : ""}
      </span>
      {needsRsvp(e.rsvp, e.startsAt, e.endsAt) && <RsvpPill needs />}
    </Link>
  );
}
