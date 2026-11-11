import type { MeHome, MyEvent, MyTeam, PublicImage, PublicPost, PublicProfile } from "@stall10/shared";
import type { Caller } from "../auth.js";
import { eventView, parseBefore, postView, profileView } from "../browse/model.js";
import type { Data, Doc } from "../browse/repository.js";
import { can, isOrg, kindOf, mapOf, roleIn, strings } from "../teams/access.js";
import type { MeRepository } from "./repository.js";

/** Teams read for the dashboard (the app's home shows them all; few have more). */
export const teamLimit = 30;
/** Events looked at per team, and shown in all. */
export const eventsPerTeam = 5;
export const eventLimit = 10;
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
    const [profile, hidden, teams, followed] = await Promise.all([
      this.repo.profile(uid),
      this.repo.privateDetails(uid),
      this.repo.teamsOf(uid, teamLimit),
      this.repo.followedUsers(uid),
    ]);
    const [events, feed] = await Promise.all([this.events(uid, teams), this.feed([uid, ...followed], parseBefore(before))]);
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
        const docs = await this.repo.upcomingEvents(t.id, now, eventsPerTeam);
        return docs
          .filter((e) => seesEvent(t.data, uid, e.data))
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

  /** Posts are readable by anyone signed in (firestore.rules), so no privacy filter here. */
  private async feed(authors: string[], before: number | null) {
    const docs = await this.repo.postsBy(authors, before, feedPageSize);
    const posts = docs.map((d) => {
      const view = postView(d.data);
      return { ...view, id: d.id, images: this.images(view.images) } as PublicPost;
    });
    const last = docs.at(-1)?.data.createdAt;
    const next = docs.length === feedPageSize && typeof last === "string" ? Date.parse(last) : null;
    return { posts, next };
  }
}
