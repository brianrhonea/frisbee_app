"use client";
import type { MeHome, PublicPost } from "@stall10/shared";
import type { User } from "firebase/auth";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { listingSubtitle } from "@/lib/site";
import { EventItem } from "./EventItem";
import { LocalTime } from "./LocalTime";
import { PostCard } from "./PostCard";
import { DashboardLayout, ProfileCard, roleLabel, StatTiles, TeamList } from "./ProfileDashboard";
import { UsernameStep } from "./UsernameStep";

const rsvpLabels: Record<string, string> = { going: "Going", maybe: "Maybe", notGoing: "Not going" };

/** A signed-in member's home: their own profile dashboard, schedule and feed. */
export function Dashboard({ user }: { user: User }) {
  const [home, setHome] = useState<MeHome | null>(null);
  const [error, setError] = useState("");
  const [older, setOlder] = useState<{ posts: PublicPost[]; next: number | null; busy: boolean }>({
    posts: [],
    next: null,
    busy: false,
  });

  const load = useCallback(async () => {
    setError("");
    try {
      const h = await callApi<MeHome>(user, "/v1/me/home");
      setHome(h);
      setOlder({ posts: [], next: h.feed.next, busy: false });
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Couldn't load your home. Try again.");
    }
  }, [user]);

  useEffect(() => {
    void load();
  }, [load]);

  async function loadOlder() {
    if (older.next === null) return;
    setOlder((o) => ({ ...o, busy: true }));
    try {
      const h = await callApi<MeHome>(user, `/v1/me/home?before=${older.next}`);
      setOlder((o) => ({ posts: [...o.posts, ...h.feed.posts], next: h.feed.next, busy: false }));
    } catch {
      setOlder((o) => ({ ...o, busy: false }));
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

  const { profile, teams, events, feed } = home;
  const posts = [...feed.posts, ...older.posts];
  const side = (
    <>
      <ProfileCard
        profile={profile}
        actions={
          profile.username ? (
            <Link className="btn btn-small" href={`/players/${encodeURIComponent(profile.id)}`}>
              View public profile
            </Link>
          ) : null
        }
      />
      <StatTiles stats={profile.stats} />
      <TeamList
        title="Your teams"
        teams={teams.map((t) => ({
          id: t.id,
          name: t.name,
          subtitle: [roleLabel(t.role, t.kind), listingSubtitle(t)].filter(Boolean).join(" · "),
        }))}
        empty={
          <p className="muted small">
            Join a team with an invite link, or <Link href="/explore">find one near you</Link>.
          </p>
        }
      />
    </>
  );

  return (
    <div className="page page-wide">
      <DashboardLayout side={side}>
        {profile.needsUsername && <UsernameStep user={user} onDone={() => void load()} />}

        <div className="card">
          <h2 className="card-title">Coming up</h2>
          {events.length === 0 ? (
            <p className="muted small">Nothing scheduled on your teams.</p>
          ) : (
            <div className="stack">
              {events.map((e) => (
                <EventItem key={`${e.teamId}/${e.id}`} startsAt={e.startsAt}>
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

        <h2 className="section-title">Your feed</h2>
        {posts.length === 0 ? (
          <div className="card">
            <p className="muted small">
              Posts from you and the people you follow show up here. <Link href="/community">See the community</Link> or{" "}
              <Link href="/explore">find players to follow</Link>.
            </p>
          </div>
        ) : (
          <div className="stack">
            {posts.map((p) => (
              <PostCard key={p.id} post={p} />
            ))}
          </div>
        )}
        {older.next !== null && (
          <nav className="pager">
            <button className="btn" type="button" disabled={older.busy} onClick={() => void loadOlder()}>
              {older.busy ? "Loading…" : "Older posts"}
            </button>
          </nav>
        )}
      </DashboardLayout>
    </div>
  );
}
