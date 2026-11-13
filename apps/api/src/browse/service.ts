import type {
  EventsPage,
  PostPage,
  ProfilePage,
  PublicImage,
  PublicListing,
  PublicPost,
  PublicProfile,
  SearchPage,
  TeamPage,
} from "@stall10/shared";
import { searchWords } from "@stall10/shared";
import { ApiError } from "../errors.js";
import { searchKey } from "../limits/model.js";
import {
  eventView,
  isPrivateGroup,
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
import { nextCursor, originalsOf, withOriginal } from "./reposts.js";

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
  ) {}

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
    const people = await this.repo.profiles(docs.flatMap((d) => postAuthors(d.data)));
    const shown = docs.filter((d) => postAuthors(d.data).every((id) => !isPrivateProfile(people.get(id))));
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
    if (!data) throw new ApiError("not_found", "No such player.");
    const profile = { ...profileView(data), id: uid } as PublicProfile;
    if (data.private === true) return { profile, posts: [], next: null };
    const docs = await this.repo.posts(null, uid);
    return { profile, posts: await this.publicPosts(docs), next: null };
  }

  /** A team or group's page: its listing and, unless it's a private group, public posts and upcoming events. */
  async team(id: unknown): Promise<TeamPage> {
    if (!validId(id)) throw new ApiError("not_found", "No such team.");
    const data = await this.repo.listing(id);
    if (!data) throw new ApiError("not_found", "No such team.");
    const team = { ...listingView(data), id } as PublicListing;
    if (isPrivateGroup(data)) return { team, posts: [], events: [] };
    const [posts, events] = await Promise.all([
      this.repo.publicTeamPosts(id),
      this.repo.upcomingTeamEvents(id, this.now()),
    ]);
    return {
      team,
      posts: posts
        .filter((d) => isPublicTeamPost(d.data))
        .map((d) => {
          const view = teamPostView(d.data);
          delete view.public;
          return { ...view, id: d.id, images: this.images(view.images) } as TeamPage["posts"][number];
        }),
      events: events.map((d) => ({ ...eventView(d.data), id: d.id })),
    };
  }

  /** Public team events across teams that aren't private groups, and group tournaments. */
  async events(): Promise<EventsPage> {
    const now = this.now();
    const [events, tournaments] = await Promise.all([this.repo.upcomingEvents(now), this.repo.upcomingTournaments(now)]);
    const groupOf = (d: Doc) => d.data.groupId;
    const teamIds = new Set<string>(events.map((e) => e.teamId).filter((id) => id));
    for (const t of tournaments) {
      const g = groupOf(t);
      if (validId(g)) teamIds.add(g);
    }
    const listings = await this.repo.listings([...teamIds]);
    return {
      events: events.flatMap((d) => {
        const listing = listings.get(d.teamId);
        if (isPrivateGroup(listing)) return [];
        return [{ ...eventView(d.data), id: d.id, teamId: d.teamId, teamName: String(listing?.name ?? "") }];
      }),
      tournaments: tournaments
        .filter((d) => !isPrivateGroup(listings.get(groupOf(d) as string)))
        .map((d) => ({ ...d.data, id: d.id })),
    };
  }

  /**
   * Players and teams by the query's longest word, as the app searches.
   * Private profiles show only their card.
   */
  async search(query: unknown): Promise<SearchPage> {
    const words = typeof query === "string" ? searchWords(query) : [];
    const longest = words.reduce((a, b) => (b.length > a.length ? b : a), "");
    const key = searchKey(longest.slice(0, 20));
    if (!key) return { players: [], teams: [] };
    const [profiles, listings] = await Promise.all([this.repo.searchProfiles(key), this.repo.searchListings(key)]);
    return {
      players: profiles.map((d) => ({ ...searchProfileView(d.data), id: d.id }) as PublicProfile),
      teams: listings.map((d) => ({ ...listingView(d.data), id: d.id }) as PublicListing),
    };
  }
}
