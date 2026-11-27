import type {
  EventsPage,
  PostPage,
  ProfilePage,
  PublicImage,
  PublicListing,
  PublicPost,
  PublicProfile,
  PublicTournament,
  SearchPage,
  TeamPage,
  TeamSearchPage,
} from "@stall10/shared";
import { arrangeTeamFeed, publicPageOn, searchWords } from "@stall10/shared";
import type { AdultVisibility } from "../account/adult_visibility.js";
import { ApiError } from "../errors.js";
import { searchKey } from "../limits/model.js";
import {
  eventView,
  isPrivateProfile,
  isPublicTeamPost,
  listingView,
  parseBefore,
  postAuthors,
  postView,
  profileView,
  searchProfileView,
  teamPostView,
  validId,
} from "./model.js";
import type { BrowseRepository, Data, Doc } from "./repository.js";
import { draftedLeagueTeamName, isDraftedLeagueTeam, isPrivateHost, isYouthHost, pinnedImageUrl } from "./visibility.js";
import { nextCursor, originalsOf, withOriginal } from "./reposts.js";

/** A group tournament's directory listing as anyone sees it (the fields firestore.rules lets organizers write). */
const tournamentFields = ["groupId", "tournamentId", "name", "startsAt", "endsOn", "status", "format"] as const;

function tournamentView(d: Doc): PublicTournament {
  const out: Data = { id: d.id };
  for (const k of tournamentFields) if (d.data[k] !== undefined) out[k] = d.data[k];
  return out as unknown as PublicTournament;
}

/** The search key for [query]: its longest word, as the app searches; null for nothing to search. */
function queryKey(query: unknown): string | null {
  const words = typeof query === "string" ? searchWords(query) : [];
  const longest = words.reduce((a, b) => (b.length > a.length ? b : a), "");
  return searchKey(longest.slice(0, 20));
}

/**
 * What anyone may see, signed in or not: the same allow-lists and privacy
 * checks as the `browse` Cloud Functions (model.ts). Answers never depend
 * on who asks, so they can be cached publicly.
 */
export class BrowseService {
  constructor(
    private readonly repo: BrowseRepository,
    /** Turns a stored path into a URL Storage's rules let visitors read. */
    private readonly imageUrl: (path: string) => string,
    private readonly now: () => number = Date.now,
    /** The Storage buckets profile photos may come from (visibility.ts photoBuckets). */
    private readonly buckets: readonly string[] = [],
    /** D-1317: accounts without `ageOk` are left out when enforcing (account/adult_visibility.ts). */
    private readonly adults?: AdultVisibility,
  ) {}

  /**
   * Of [uids], those D-1317 leaves out (no `ageOk`, when enforcing). A
   * profile already carrying the server-set `adult: true` marker (in
   * [profiles], when the caller has them) is known to be an adult and costs
   * no claim lookup; everyone else is asked of the claims, the source of truth.
   */
  private async hiddenAdults(uids: string[], profiles?: ReadonlyMap<string, Data | undefined>): Promise<Set<string>> {
    if (!this.adults) return new Set();
    const ask = profiles ? uids.filter((u) => profiles.get(u)?.adult !== true) : uids;
    return ask.length > 0 ? this.adults.hidden(ask) : new Set();
  }

  /** [view]'s photo and header, dropped unless pinnedImageUrl allows them. */
  private pinPhotos(view: Data): Data {
    for (const k of ["photoUrl", "headerUrl"]) {
      if (!(k in view)) continue;
      const url = pinnedImageUrl(view[k], this.buckets);
      if (url) view[k] = url;
      else delete view[k];
    }
    return view;
  }

  /** Listings and (masked) team docs of [ids], read together. */
  private async hosts(ids: string[]): Promise<{ listings: Map<string, Data>; teams: Map<string, Data> }> {
    const unique = [...new Set(ids.filter((id) => validId(id)))];
    const [listings, teams] = await Promise.all([this.repo.listings(unique), this.repo.teams(unique)]);
    return { listings, teams };
  }

  /**
   * A listing as visitors see it: a youth team's without its location
   * (and marked youth when only its team doc says so), a drafted league
   * team's without its name.
   */
  private listing(id: string, data: Data, team: Data | undefined): PublicListing {
    const view = { ...listingView(data), id } as PublicListing;
    if (isYouthHost(data, team)) {
      delete view.location;
      view.level = "youth";
    }
    if (isDraftedLeagueTeam(id)) view.name = draftedLeagueTeamName;
    // The page is off by either document: the website shows its card only.
    if (!publicPageOn(data) || !publicPageOn(team)) view.publicPage = false;
    return view;
  }

  private images(raw: unknown): PublicImage[] | undefined {
    if (!Array.isArray(raw)) return undefined;
    return raw.flatMap((i) => {
      const path = (i as Data | null)?.path;
      return typeof path === "string" && path ? [{ ...(i as Data), path, url: this.imageUrl(path) } as PublicImage] : [];
    });
  }

  private post(d: Doc): PublicPost {
    const view = postView(d.data);
    return { ...view, id: d.id, images: this.images(view.images) } as PublicPost;
  }

  /**
   * [docs] as public posts: those whose authors (and reposts' originals')
   * aren't private. A repost carries its original as it is now, or null
   * once that's deleted.
   */
  private async publicPosts(docs: Doc[]): Promise<PublicPost[]> {
    const authors = docs.flatMap((d) => postAuthors(d.data));
    const people = await this.repo.profiles(authors);
    const hidden = await this.hiddenAdults(authors, people);
    const shown = docs.filter((d) => postAuthors(d.data).every((id) => !isPrivateProfile(people.get(id)) && !hidden.has(id)));
    const originals = await originalsOf(shown, (id) => this.repo.post(id));
    return shown.map((d) => withOriginal(this.post(d), d, originals, (o) => this.post(o)));
  }



  /**
   * The community feed: the newest page of posts from public profiles.
   * Visitors get one page; members read further in their own feed
   * (`/v1/me/home`), so there's no cursor here.
   */
  async feed(): Promise<PostPage> {
    const docs = await this.repo.posts(null);
    return { posts: await this.publicPosts(docs), next: null };
  }

  /**
   * The community feed for a signed-in member (`GET /v1/feed`): the same
   * posts, a page at a time, as the app's community feed reads them.
   */
  async feedPage(before: unknown): Promise<PostPage> {
    const docs = await this.repo.posts(parseBefore(before));
    return { posts: await this.publicPosts(docs), next: nextCursor(docs) };
  }

  /** One post, unless its author is private. */
  async onePost(id: unknown): Promise<PublicPost> {
    if (!validId(id)) throw new ApiError("not_found", "No such post.");
    const d = await this.repo.post(id);
    const [shown] = d ? await this.publicPosts([d]) : [];
    if (!shown) throw new ApiError("not_found", "This post isn't public.");
    return shown;
  }

  /** A player's profile and, unless it's private, their newest posts. */
  /** A player's profile and, unless it's private, their newest page of posts (one page, as the feed). */
  async profile(uid: unknown): Promise<ProfilePage> {
    if (!validId(uid)) throw new ApiError("not_found", "No such player.");
    const data = (await this.repo.profiles([uid])).get(uid);
    if (!data || (await this.hiddenAdults([uid], new Map([[uid, data]]))).has(uid)) throw new ApiError("not_found", "No such player.");
    const profile = { ...this.pinPhotos(profileView(data)), id: uid } as PublicProfile;
    if (data.private === true) return { profile, posts: [], next: null };
    const docs = await this.repo.posts(null, uid);
    return { profile, posts: await this.publicPosts(docs), next: null };
  }

  /**
   * A team or group's page: its listing and, unless it's a private group
   * (by listing or team doc, isPrivateHost) or a youth team (its card
   * only, without a location), public posts and upcoming events. A post
   * names its author only when the author's profile is public, and never
   * by uid.
   */
  async team(id: unknown): Promise<TeamPage> {
    const isoOf = (v: unknown) => (typeof v === "string" ? v : undefined);
    if (!validId(id)) throw new ApiError("not_found", "No such team.");
    const { listings, teams } = await this.hosts([id]);
    const data = listings.get(id);
    if (!data) throw new ApiError("not_found", "No such team.");
    const teamDoc = teams.get(id);
    const team = this.listing(id, data, teamDoc);
    if (isPrivateHost(data, teamDoc) || isYouthHost(data, teamDoc)) return { team, posts: [], events: [] };
    const [posts, events] = await Promise.all([
      this.repo.publicTeamPosts(id),
      this.repo.upcomingTeamEvents(id, this.now()),
    ]);
    // Pinned posts first (F24), then the newest.
    const { pinned, rest } = arrangeTeamFeed(
      [],
      posts.filter((d) => isPublicTeamPost(d.data)).map((d) => ({ ...d, pinnedAt: isoOf(d.data.pinnedAt), createdAt: isoOf(d.data.createdAt) })),
    );
    const shown = [...pinned, ...rest];
    const authorOf = (d: Doc) => (typeof d.data.authorId === "string" && d.data.authorId ? d.data.authorId : null);
    const authors = shown.flatMap((d) => authorOf(d) ?? []);
    const people = await this.repo.profiles(authors);
    const hidden = await this.hiddenAdults(authors, people);
    return {
      team,
      posts: shown.map((d) => {
        const view = teamPostView(d.data);
        delete view.public;
        delete view.authorId;
        const author = authorOf(d);
        if (!author || isPrivateProfile(people.get(author)) || hidden.has(author)) delete view.authorName;
        return { ...view, id: d.id, images: this.images(view.images) } as TeamPage["posts"][number];
      }),
      events: events.map((d) => ({ ...eventView(d.data), id: d.id })),
    };
  }

  /**
   * Public team events across teams that aren't private groups or youth
   * teams, and group tournaments of groups that aren't private.
   */
  async events(): Promise<EventsPage> {
    const now = this.now();
    const [events, tournaments] = await Promise.all([this.repo.upcomingEvents(now), this.repo.upcomingTournaments(now)]);
    const groupOf = (d: Doc) => d.data.groupId;
    const teamIds = new Set<string>(events.map((e) => e.teamId).filter((id) => id));
    for (const t of tournaments) {
      const g = groupOf(t);
      if (validId(g)) teamIds.add(g);
    }
    const { listings, teams } = await this.hosts([...teamIds]);
    const hidden = (id: string) => isPrivateHost(listings.get(id), teams.get(id));
    return {
      events: events.flatMap((d) => {
        if (hidden(d.teamId) || isYouthHost(listings.get(d.teamId), teams.get(d.teamId))) return [];
        const name = isDraftedLeagueTeam(d.teamId) ? draftedLeagueTeamName : String(listings.get(d.teamId)?.name ?? "");
        return [{ ...eventView(d.data), id: d.id, teamId: d.teamId, teamName: name }];
      }),
      tournaments: tournaments.filter((d) => validId(groupOf(d)) && !hidden(groupOf(d) as string)).map(tournamentView),
    };
  }

  /**
   * Players and teams by the query's longest word, as the app searches.
   * Private profiles show only their card.
   */
  async search(query: unknown): Promise<SearchPage> {
    const key = queryKey(query);
    if (!key) return { players: [], teams: [] };
    const [found, listings] = await Promise.all([this.repo.searchProfiles(key), this.repo.searchListings(key)]);
    const hidden = await this.hiddenAdults(found.map((d) => d.id), new Map(found.map((d) => [d.id, d.data])));
    const profiles = found.filter((d) => !hidden.has(d.id));
    return {
      players: profiles.map((d) => ({ ...this.pinPhotos(searchProfileView(d.data)), id: d.id }) as PublicProfile),
      teams: listings.map((d) => ({ ...listingView(d.data), id: d.id }) as PublicListing),
    };
  }

  /**
   * The team finder (`GET /v1/public/teams?q=`), for anyone: teams,
   * groups and schools or clubs by the query's longest word, as their
   * public pages list them (a private group's listing too, as its page
   * shows it; a youth team's without its location). Never players, and
   * never a league's drafted teams.
   */
  async teams(query: unknown): Promise<TeamSearchPage> {
    const key = queryKey(query);
    if (!key) return { teams: [] };
    // Drafted league teams are named after their players: not for visitors.
    const listings = (await this.repo.searchListings(key)).filter((d) => !isDraftedLeagueTeam(d.id));
    const teams = await this.repo.teams(listings.map((d) => d.id));
    return { teams: listings.map((d) => this.listing(d.id, d.data, teams.get(d.id))) };
  }
}
