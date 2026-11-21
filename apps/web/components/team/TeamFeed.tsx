"use client";
import { arrangeTeamFeed, isPinnedPost, type PublicEvent, type PublicTeamPost, teamPostPinsMax } from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import Link from "next/link";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { LocalTime } from "../LocalTime";
import { roleLabel } from "../ProfileDashboard";
import { useLiveQuery } from "@/lib/live";
import { EmptyState, ErrorNote, Loading } from "../StatusViews";
import { Avatar } from "../Avatar";
import { InviteButton } from "./InviteDialog";
import { membersInOrder } from "./TeamBanner";
import { type TeamViewer, useTeamHub } from "./TeamContext";
import { type TeamPostView, TeamPostCard } from "./TeamPostCard";
import { TeamPostComposer } from "./TeamPostComposer";
import { TeamPostComments } from "./TeamPostComments";
import { Dialog } from "../Dialog";
import { SectionsHint } from "./SectionsHint";
import { TeamStatTiles, useTeamChatRooms } from "./TeamStatTiles";
import { CommunityChat, CommunityOrganizers, NextPickupCard } from "./CommunitySections";
import { DateTile } from "./DateTile";
import { needsRsvp, RsvpPill } from "../RsvpPill";
import { useTeamEvents, useYouthOutsiderPublic, youthVisitorNote } from "./TeamSchedule";
import { TournamentDayCard } from "../tournaments/TournamentDayCard";
import { useTournamentDays } from "../tournaments/useTournamentDays";
import { ReportButton } from "../Report";

const postLimit = 30;
const leads = new Set(["owner", "coach", "captain"]);

/**
 * The hub's front page: posts in the middle (every post, live, for
 * members; the public ones for everyone else), what's coming up beside
 * them.
 */
export function TeamFeed({ publicPosts, publicEvents }: { publicPosts: PublicTeamPost[]; publicEvents: PublicEvent[] }) {
  const { teamId, name, kind, privateGroup, privatePage, youth, viewer } = useTeamHub();
  const member = viewer.state === "member";
  // A youth team's public posts and events, live, for someone signed in who isn't on it (not while its page is off).
  const outsiderYouth = youth && !privatePage && viewer.state === "outsider";
  const outsider = useYouthOutsiderPublic(teamId, outsiderYouth, { posts: true, eventLimit: 4 });
  const live = useLiveQuery<TeamPostView>(
    member ? `teams/${teamId}/posts` : null,
    [orderBy("createdAt", "desc"), limit(postLimit)],
    "feed",
  );
  // Pinned posts can be older than the newest [postLimit] (redesign F24).
  const pins = useLiveQuery<TeamPostView>(
    member ? `teams/${teamId}/posts` : null,
    [orderBy("pinnedAt", "desc"), limit(teamPostPinsMax)],
    "feed-pins",
  );
  const events = useTeamEvents(teamId, viewer);
  const { user } = useAuth();
  const tournamentDay = useTournamentDays(member ? user?.uid : null, teamId)[0];
  const loaded: TeamPostView[] = member ? (live.data ?? []) : outsiderYouth ? (outsider.posts.data ?? []) : publicPosts;
  // Pinned first: members' from their own query; others' among those loaded (the API sends visitors theirs).
  const feed = arrangeTeamFeed(member ? (pins.data ?? []) : [], loaded);
  const posts: TeamPostView[] = [...feed.pinned, ...feed.rest];
  const ahead = member ? (events.data ?? []) : outsiderYouth ? (outsider.events.data ?? []) : publicEvents;
  const hidden = !member && (privateGroup || privatePage);
  // A community leads with its next event, RSVP and all (F27); Coming up lists the rest.
  const community = kind !== "team" && !hidden;
  const pickup = community && (!member || events.data !== undefined);
  const upcoming = ahead.slice(community ? 1 : 0, community ? 5 : 4);
  const chat = useTeamChatRooms();
  // Signed out: a youth team's card only.
  const youthHidden = youth && viewer.state === "visitor";
  const admin = viewer.state === "member" && viewer.can("manageTeam");
  const [editing, setEditing] = useState<string | null>(null);

  return (
    <div className="hub-feed">
      <section className="stack">
        <SectionsHint />
        {pickup && <NextPickupCard event={ahead[0]} />}
        {member && <TeamStatTiles next={events.data?.[0]} chat={chat} />}
        {admin && <TeamPostComposer teamId={teamId} prompt={kind === "team" ? "Post to the team…" : "Post to the community…"} />}
        {viewer.state === "loading" || (member && !live.data && !live.error) ? (
          <Loading label="Loading posts…" />
        ) : live.error ? (
          <ErrorNote>{live.error}</ErrorNote>
        ) : hidden ? (
          <EmptyState>
            {privatePage
              ? "This team's page is private. Its events, posts and roster are only visible to members."
              : "Only members see this community's posts and events."}
          </EmptyState>
        ) : youthHidden ? (
          <EmptyState>{youthVisitorNote}</EmptyState>
        ) : outsiderYouth && outsider.posts.error ? (
          <ErrorNote>{outsider.posts.error}</ErrorNote>
        ) : outsiderYouth && !outsider.posts.data ? (
          <Loading label="Loading posts…" />
        ) : posts.length === 0 ? (
          <EmptyState>{member ? "No posts yet." : "No public posts yet."}</EmptyState>
        ) : (
          posts.map((p) =>
            editing === p.id ? (
              <TeamPostComposer key={p.id} teamId={teamId} post={p} onDone={() => setEditing(null)} />
            ) : (
              <TeamPostCard
                key={p.id}
                post={p}
                teamName={name}
                showAudience={member}
                pinned={isPinnedPost(p)}
                actions={
                  admin ? (
                    <PostAdminActions teamId={teamId} post={p} pinned={feed.pinned} onEdit={() => setEditing(p.id)} />
                  ) : user && p.authorId !== user.uid ? (
                    <ReportButton target={{ kind: "teamPost", teamId, postId: p.id }} authorName={p.authorName || name} />
                  ) : undefined
                }
                comments={member ? () => <TeamPostComments teamId={teamId} postId={p.id} moderator={admin} /> : undefined}
              />
            ),
          )
        )}
      </section>
      <aside className="stack">
        {/* On a tournament day the card comes before what's coming up. */}
        {tournamentDay && <TournamentDayCard day={tournamentDay} showTeam={false} />}
        {community && <CommunityChat chat={chat} />}
        {community && <CommunityOrganizers />}
        {!hidden && !youthHidden && !(community && upcoming.length === 0) && (
          <div className="card coming-up">
            <div className="card-head">
              <h2 className="card-title">Coming up</h2>
              <Link className="small" href={`/teams/${teamId}/schedule`}>
                Full schedule
              </Link>
            </div>
            {upcoming.length === 0 ? (
              <p className="muted small">Nothing scheduled.</p>
            ) : (
              <div className="coming-list">
                {upcoming.map((e) => {
                  const mine = viewer.state === "member" ? (e as { rsvps?: Record<string, string> }).rsvps?.[viewer.uid] : undefined;
                  return (
                    <Link key={e.id} href={`/teams/${teamId}/schedule?event=${e.id}`} className="hub-event-link coming-row">
                      <DateTile startsAt={e.startsAt} />
                      <span className="sched-main">
                        <b>
                          <span className="type-dot" aria-hidden="true" />
                          {e.title || "Event"}
                        </b>
                        <small>
                          <LocalTime iso={e.startsAt} style="dateTime" />
                        </small>
                      </span>
                      {member && <RsvpPill answer={mine} type={e.type} needs={needsRsvp(mine, e.startsAt, e.endsAt)} />}
                    </Link>
                  );
                })}
              </div>
            )}
          </div>
        )}
        <MemberPreview />
      </aside>
    </div>
  );
}

/**
 * What the roster card says to someone not on the team, or null when they
 * can't open it: visitors see only an adult team's roster (rosterIsPublic),
 * without links to profiles; signed-in outsiders see any roster but a
 * private group's or a youth team's (the API refuses those), with links.
 */
export function rosterCardText(v: {
  state: TeamViewer["state"];
  privateGroup: boolean;
  /** The team's public page is off: like a private group, members only. */
  privatePage?: boolean;
  youth: boolean;
  publicRoster: boolean;
}): string | null {
  switch (v.state) {
    case "visitor":
      return v.publicRoster ? "See who's on the team." : null;
    case "outsider":
    case "error":
      return v.privateGroup || v.privatePage || v.youth ? null : "See who's on it and open their profiles.";
    default:
      return null;
  }
}

/**
 * The side column's people: for members, the first few with their role,
 * all of them on the roster, and Invite for member managers; for everyone
 * else who may open it, a link to the roster (rosterCardText).
 */
function MemberPreview() {
  const { teamId, kind, privateGroup, privatePage, youth, publicRoster, viewer } = useTeamHub();
  const roster = `/teams/${teamId}/roster`;
  if (viewer.state !== "member") {
    const text = rosterCardText({ state: viewer.state, privateGroup, privatePage, youth, publicRoster });
    if (!text) return null;
    return (
      <div className="card">
        <h2 className="card-title">{kind === "team" ? "Roster" : "Members"}</h2>
        <p className="muted small">{text}</p>
        <Link className="btn btn-small" href={roster}>
          Open the {kind === "team" ? "roster" : "members"}
        </Link>
      </div>
    );
  }
  const people = membersInOrder(viewer.team);
  return (
    <div className="card member-preview">
      <div className="card-head">
        <h2 className="card-title">{kind === "team" ? "The team" : "Members"}</h2>
        <Link href={roster} className="small">
          All {people.length} {people.length === 1 ? "member" : "members"}
        </Link>
      </div>
      <ul className="member-preview-list">
        {people.slice(0, 6).map((p) => (
          <li key={p.uid}>
            <Link className="person" href={`/players/${p.uid}`}>
              <Avatar name={p.name} size={32} />
              <span>
                {p.name}
                {p.uid === viewer.uid && <small className="muted"> (you)</small>}
              </span>
            </Link>
            <span className={`role-pill${leads.has(p.tier) ? " lead" : ""}`}>{roleLabel(p.tier, kind)}</span>
          </li>
        ))}
      </ul>
      <div className="member-preview-actions">
        <InviteButton />
      </div>
    </div>
  );
}

/** Pin, edit and delete on a team post, for its admins. Pinning into a full feed asks which pin to take down. */
function PostAdminActions({
  teamId,
  post,
  pinned,
  onEdit,
}: {
  teamId: string;
  post: TeamPostView & { id: string };
  pinned: Array<TeamPostView & { id: string }>;
  onEdit: () => void;
}) {
  const postId = post.id;
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [choosing, setChoosing] = useState(false);
  const isPinned = isPinnedPost(post);
  const pinPath = `/v1/teams/${encodeURIComponent(teamId)}/posts/${encodeURIComponent(postId)}/pin`;
  async function pin(unpin?: string) {
    if (!user) return;
    if (!isPinned && unpin === undefined && pinned.length >= teamPostPinsMax) return setChoosing(true);
    setChoosing(false);
    setBusy(true);
    setError(null);
    try {
      await callApi(user, pinPath, isPinned ? { method: "DELETE" } : { method: "PUT", body: unpin ? { unpin } : {} });
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function remove() {
    if (!user || !window.confirm("Delete this post? This can't be undone.")) return;
    setBusy(true);
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/posts/${encodeURIComponent(postId)}`, { method: "DELETE" });
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }
  return (
    <span className="post-admin">
      <button type="button" className="text-btn" onClick={() => void pin()} disabled={busy}>
        {isPinned ? "Unpin" : "Pin"}
      </button>
      <button type="button" className="text-btn" onClick={onEdit} disabled={busy}>
        Edit
      </button>
      <button type="button" className="text-btn" onClick={() => void remove()} disabled={busy}>
        Delete
      </button>
      {error && <span className="form-error">{error}</span>}
      {choosing && (
        <Dialog label="Unpin one to pin this" onClose={() => setChoosing(false)} className="card pins-dialog" dismissOnBackdrop>
          <h2 className="card-title">Unpin one to pin this</h2>
          <p className="muted small">A team keeps up to {teamPostPinsMax} pinned posts.</p>
          <div className="unpin-choices">
            {pinned.map((p) => (
              <button key={p.id} type="button" className="btn" onClick={() => void pin(p.id)}>
                {(p.title || p.body || "Photo post").slice(0, 80)}
              </button>
            ))}
          </div>
          <button type="button" className="btn btn-small" onClick={() => setChoosing(false)}>
            Cancel
          </button>
        </Dialog>
      )}
    </span>
  );
}
