import type { MeHome, MemberProfilePage, MyEvent, MyTeam, PublicImage, PublicPost, PublicProfile } from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError } from "../errors.js";
import { eventView, isPrivateProfile, parseBefore, postAuthors, postView, profileView, validId } from "../browse/model.js";
import type { Data, Doc } from "../browse/repository.js";
import { nextCursor, originalsOf, withOriginal } from "../browse/reposts.js";
import { can, isOrg, kindOf, mapOf, roleIn, strings } from "../teams/access.js";
import type { MeRepository } from "./repository.js";

/** Teams read for the dashboard (the app's home shows them all; few have more). */
export const teamLimit = 30;
/**
 * Events shown per team and in all. Each team's events are over-read
 * (eventReadPerTeam started recently, and as many upcoming) because the
 * audience filter and the end check apply after the reads: a community
 * member may see only a few of a team's events.
 */
export const eventsPerTeam = 5;
export const eventReadPerTeam = 25;
export const eventLimit = 10;
/**
 * How far back events are read so ones under way still show (a
 * tournament can run for days). An event is under way until its end, or
 * its start when it has none, as the app's My schedule (`upcoming`).
 */
export const eventLookbackMs = 3 * 86_400_000;
export const feedPageSize = 20;

/**
 * firestore.rules `sees(e)` for teams/{t}/events: a team's and a group's
 * events go to every member; a school or club community's go to its event
 * managers and to the event's audience ('everyone', the caller's role, one
 * of their custom roles; `inAudience` checks the first 10 custom roles).
 */
export function seesEvent(team: Data, uid: string, event: Data): boolean {
  if (!strings(team.memberIds).includes(uid)) return false;
  if (!isOrg(team) || can(team, uid, "manageEvents")) return true;
  const audience = strings(event.audience);
  const role = roleIn(team, uid) === "stats" ? "player" : roleIn(team, uid);
  const mine = strings(mapOf(team.memberRoles)[uid]).slice(0, 10);
  return audience.includes("everyone") || audience.includes(role) || mine.some((r) => audience.includes(r));
}

/** The event hasn't ended at [now]: its end (or start, without one) is not before it. */
export function notEnded(event: Data, now: number): boolean {
  const end = Date.parse(String(event.endsAt ?? event.startsAt ?? ""));
  return Number.isFinite(end) && end >= now;
}

/** The caller's own dashboard: profile, teams, upcoming events and feed. */
export class MeService {
  constructor(
    private readonly repo: MeRepository,
    /** A stored path's URL (members' views fetch their own when it's private). */
    private readonly imageUrl: (path: string) => string,
    private readonly now: () => number = Date.now,
  ) {}

  async home(caller: Caller, before: unknown): Promise<MeHome> {
    const uid = caller.uid;
    const [profile, hidden, teams, followed, tournaments] = await Promise.all([
      this.repo.profile(uid),
      this.repo.privateDetails(uid),
      this.repo.teamsOf(uid, teamLimit),
      this.repo.followedUsers(uid),
      this.repo.followedTournaments?.(uid) ?? Promise.resolve([] as string[]),
    ]);
    const sources = { authors: [uid, ...followed], tournaments, teamIds: teams.map((t) => t.id), followed };
    const [events, feed] = await Promise.all([this.events(uid, teams), this.feed(uid, sources, parseBefore(before))]);
    return {
      profile: this.ownProfile(uid, caller, profile, hidden),
      teams: teams.map((t) => this.team(t, uid)).sort((a, b) => a.name.localeCompare(b.name)),
      events,
      feed,
    };
  }

  /** Their own profile as others would see it if public, private details merged in. */
  private ownProfile(uid: string, caller: Caller, profile: Data | null, hidden: Data | null) {
    const p = profile ?? {};
    // profileView keeps only the card of a private profile; the owner sees it all.
    const view = profileView({ ...p, ...(hidden ?? {}), private: false });
    return {
      ...view,
      id: uid,
      name: (view.name as string | undefined) || caller.name,
      private: p.private === true,
      needsUsername: typeof p.username !== "string" || p.username === "",
    } as PublicProfile & { needsUsername: boolean };
  }

  private team(t: Doc, uid: string): MyTeam {
    const d = t.data;
    const out: MyTeam = { id: t.id, name: String(d.name ?? "Team"), kind: kindOf(d), role: roleIn(d, uid) || "player" };
    for (const k of ["division", "level", "city"] as const) if (typeof d[k] === "string" && d[k]) out[k] = d[k] as string;
    return out;
  }

  private async events(uid: string, teams: Doc[]): Promise<MyEvent[]> {
    const now = this.now();
    const lists = await Promise.all(
      teams.map(async (t) => {
        // Two reads, so events that ended recently can't use up the upcoming ones' share.
        const [started, upcoming] = await Promise.all([
          this.repo.startedEvents(t.id, now - eventLookbackMs, now, eventReadPerTeam),
          this.repo.upcomingEvents(t.id, now, eventReadPerTeam),
        ]);
        return [...started.reverse(), ...upcoming]
          .filter((e) => notEnded(e.data, now) && seesEvent(t.data, uid, e.data))
          .slice(0, eventsPerTeam)
          .map((e) => {
            const rsvp = mapOf(e.data.rsvps)[uid];
            return {
              ...(eventView(e.data) as Partial<MyEvent>),
              id: e.id,
              teamId: t.id,
              teamName: String(t.data.name ?? "Team"),
              ...(typeof rsvp === "string" ? { rsvp } : {}),
            } as MyEvent;
          });
      }),
    );
    return lists
      .flat()
      .sort((a, b) => String(a.startsAt ?? "").localeCompare(String(b.startsAt ?? "")))
      .slice(0, eventLimit);
  }

  private images(raw: unknown): PublicImage[] | undefined {
    if (!Array.isArray(raw)) return undefined;
    return raw.flatMap((i) => {
      const path = (i as Data | null)?.path;
      return typeof path === "string" && path ? [{ ...(i as Data), path, url: this.imageUrl(path) } as PublicImage] : [];
    });
  }

  /**
   * The players' posts in the app's home feed (HomeFeed): the caller's own
   * and those of people they follow, posts tagged with tournaments they
   * follow, and events shared from their teams' schedules by anyone
   * (reposts of those reach the reposter's followers, not the team again).
   * Team posts are read live by the website. The last two sources reach
   * strangers' posts, so the privacy filter applies (visiblePosts). Each
   * source reads a page after [before]; the merged page is exact.
   */
  private async feed(viewer: string, src: { authors: string[]; tournaments: string[]; teamIds: string[]; followed: string[] }, before: number | null) {
    const where = this.repo.postsWhereIn?.bind(this.repo);
    const [byAuthors, tagged, shared] = await Promise.all([
      this.repo.postsBy(src.authors, before, feedPageSize),
      where && src.tournaments.length ? where("tournamentKey", src.tournaments, before, feedPageSize) : Promise.resolve([] as Doc[]),
      where && src.teamIds.length ? where("event.teamId", src.teamIds, before, feedPageSize) : Promise.resolve([] as Doc[]),
    ]);
    const byId = new Map<string, Doc>();
    for (const d of [...byAuthors, ...tagged, ...shared.filter((d) => !d.data.repostOf)]) byId.set(d.id, d);
    const merged = [...byId.values()].sort((a, b) => String(b.data.createdAt ?? "").localeCompare(String(a.data.createdAt ?? "")));
    const docs = merged.slice(0, feedPageSize);
    // More follow when the merge was cut (short sources can add up past a
    // page), or when a source with a full page may hold more.
    const more = merged.length > feedPageSize || [byAuthors, tagged, shared].some((d) => d.length >= feedPageSize);
    // Every post is checked, the caller's and followed people's too: a
    // repost's original by a private author they don't follow stays hidden
    // (posts are readable by anyone signed in, so privacy is kept here).
    const views = new Map((await this.visiblePosts(viewer, docs, new Set(src.followed))).map((v) => [v.id, v]));
    const posts = docs.flatMap((d) => (views.has(d.id) ? [views.get(d.id)!] : []));
    return { posts, next: more ? nextCursor(docs, feedPageSize) : null };
  }

  /**
   * Whom [viewer] may see the posts and full profile of: themselves,
   * public profiles, and private ones they follow (a follow of a private
   * profile needs its owner's OK). Posts are readable by anyone signed in
   * (firestore.rules), so this is where privacy is kept for members.
   */
  private async visibility(viewer: string, authors: string[], known?: Set<string>) {
    const [followed, profiles] = await Promise.all([
      known ? [...known] : this.repo.followedUsers(viewer),
      this.repo.profiles(authors),
    ]);
    const follows = new Set(followed);
    return {
      follows,
      profiles,
      sees: (uid: string) => uid === viewer || follows.has(uid) || !isPrivateProfile(profiles.get(uid)),
    };
  }

  /** [docs] the viewer may see (every author, a repost's original's too), with originals. */
  private async visiblePosts(viewer: string, docs: Doc[], follows?: Set<string>): Promise<PublicPost[]> {
    const originals = await originalsOf(docs, (id) => this.repo.post(id));
    const authors = [...docs, ...[...originals.values()].filter((d): d is Doc => d !== null)].flatMap((d) =>
      postAuthors(d.data),
    );
    const { sees } = await this.visibility(viewer, authors, follows);
    const show = (d: Doc) => {
      const view = postView(d.data);
      return { ...view, id: d.id, images: this.images(view.images) } as PublicPost;
    };
    return docs
      .filter((d) => postAuthors(d.data).every(sees))
      .map((d) => withOriginal(show(d), d, originals, (o) => (postAuthors(o.data).every(sees) ? show(o) : null) as PublicPost));
  }

  /** A player's page for a signed-in member (`GET /v1/players/:uid`). Never cached. */
  async player(caller: Caller, uid: unknown, before?: unknown): Promise<MemberProfilePage> {
    if (!validId(uid)) throw new ApiError("not_found", "No such player.");
    const { follows, profiles, sees } = await this.visibility(caller.uid, [uid]);
    const data = profiles.get(uid);
    if (!data) throw new ApiError("not_found", "No such player.");
    const isPrivate = data.private === true;
    if (!sees(uid)) {
      return { profile: { ...profileView(data), id: uid } as PublicProfile, posts: [], next: null, locked: true };
    }
    const hidden = isPrivate ? await this.repo.privateDetails(uid) : null;
    const view = profileView({ ...data, ...(hidden ?? {}), private: false });
    const docs = await this.repo.postsBy([uid], parseBefore(before), feedPageSize);
    return {
      profile: { ...view, id: uid, private: isPrivate } as PublicProfile,
      posts: await this.visiblePosts(caller.uid, docs, follows),
      next: nextCursor(docs, feedPageSize),
      locked: false,
    };
  }

  /** One post for a signed-in member (`GET /v1/posts/:id`), if they may see it. Never cached. */
  async onePost(caller: Caller, id: unknown): Promise<PublicPost> {
    if (!validId(id)) throw new ApiError("not_found", "No such post.");
    const d = await this.repo.post(id);
    const [shown] = d ? await this.visiblePosts(caller.uid, [d]) : [];
    if (!shown) throw new ApiError("not_found", d ? "Only people they approve see this post." : "This post was deleted.");
    return shown;
  }
}
