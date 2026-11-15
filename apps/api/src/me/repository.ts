import { type Firestore, Timestamp } from "firebase-admin/firestore";
import { type Data, type Doc, plain } from "../browse/repository.js";

/** Firestore's limit on values in one `in` query. */
const inLimit = 30;

/**
 * Follows read per feed: the follows rule has no count cap, so a feed
 * never reads more than this many of each kind (and so runs at most
 * followReadLimit / 30 queries a source).
 */
export const followReadLimit = 300;

/**
 * Raw reads for the caller's own dashboard. Every read is one the caller
 * may make under firestore.rules (the service checks the rest); values come
 * back with Timestamps as ISO strings.
 */
export interface MeRepository {
  profile(uid: string): Promise<Data | null>;
  /** profiles/{uid}/private/details: a private profile's details. */
  privateDetails(uid: string): Promise<Data | null>;
  /** Teams listing [uid] in memberIds (rules: members read their teams). */
  teamsOf(uid: string, limit: number): Promise<Doc[]>;
  /** A team's events starting at or after [from] ms, soonest first. */
  upcomingEvents(teamId: string, now: number, limit: number): Promise<Doc[]>;
  /** Ids of the people [uid] follows (users/{uid}/follows, type user). */
  followedUsers(uid: string): Promise<string[]>;
  /** Newest posts by [authors] before [before] ms if given, merged. */
  postsBy(authors: string[], before: number | null, limit: number): Promise<Doc[]>;
  /** One post (a repost's original); readable by anyone signed in. */
  post(id: string): Promise<Doc | null>;
  /** Several profiles by uid (missing ones left out). */
  profiles(ids: string[]): Promise<Map<string, Data>>;
  /**
   * The follow keys of the tournaments [uid] follows (users/{uid}/follows,
   * type tournament). Optional: without it the home feed leaves out posts
   * tagged with followed tournaments.
   */
  followedTournaments?(uid: string): Promise<string[]>;
  /**
   * Newest posts whose [field] is one of [values] (the app's HomeFeed
   * sources: tournamentKey, or event.teamId for events shared from the
   * caller's teams), before [before] ms if given, merged.
   */
  postsWhereIn?(field: "tournamentKey" | "event.teamId", values: string[], before: number | null, limit: number): Promise<Doc[]>;
}

const doc = (d: { id: string; data: () => Data | undefined }): Doc => ({ id: d.id, data: plain(d.data() ?? {}) as Data });

export class FirestoreMeRepository implements MeRepository {
  constructor(private readonly db: Firestore) {}

  private async data(path: string): Promise<Data | null> {
    const snap = await this.db.doc(path).get();
    return snap.exists ? (plain(snap.data()) as Data) : null;
  }

  profile(uid: string) {
    return this.data(`profiles/${uid}`);
  }

  privateDetails(uid: string) {
    return this.data(`profiles/${uid}/private/details`);
  }

  async teamsOf(uid: string, limit: number) {
    const snap = await this.db.collection("teams").where("memberIds", "array-contains", uid).limit(limit).get();
    return snap.docs.map(doc);
  }

  async upcomingEvents(teamId: string, from: number, limit: number) {
    const snap = await this.db
      .collection(`teams/${teamId}/events`)
      .where("startsAt", ">=", Timestamp.fromMillis(from))
      .orderBy("startsAt")
      .limit(limit)
      .get();
    return snap.docs.map(doc);
  }

  async followedUsers(uid: string) {
    const snap = await this.db.collection(`users/${uid}/follows`).where("type", "==", "user").limit(followReadLimit).get();
    return snap.docs.map((d) => d.get("targetId")).filter((id): id is string => typeof id === "string" && id !== "");
  }

  async post(id: string): Promise<Doc | null> {
    const snap = await this.db.doc(`posts/${id}`).get();
    return snap.exists ? { id: snap.id, data: plain(snap.data() ?? {}) as Data } : null;
  }

  async profiles(ids: string[]) {
    const unique = [...new Set(ids)];
    if (unique.length === 0) return new Map<string, Data>();
    const snaps = await this.db.getAll(...unique.map((id) => this.db.doc(`profiles/${id}`)));
    return new Map(snaps.filter((s) => s.exists).map((s) => [s.id, plain(s.data()) as Data]));
  }

  async followedTournaments(uid: string) {
    const snap = await this.db.collection(`users/${uid}/follows`).where("type", "==", "tournament").limit(followReadLimit).get();
    return snap.docs.map((d) => d.get("key") ?? d.id).filter((k): k is string => typeof k === "string" && k.startsWith("tournament_"));
  }

  postsBy(authors: string[], before: number | null, limit: number) {
    return this.postsWhereIn("authorId", authors, before, limit);
  }

  // Indexes: posts (authorId | tournamentKey | event.teamId, createdAt desc), as the app's feed uses.
  async postsWhereIn(field: "authorId" | "tournamentKey" | "event.teamId", values: string[], before: number | null, limit: number) {
    const unique = [...new Set(values)];
    const chunks: string[][] = [];
    for (let i = 0; i < unique.length; i += inLimit) chunks.push(unique.slice(i, i + inLimit));
    const snaps = await Promise.all(
      chunks.map((ids) => {
        let q = this.db.collection("posts").where(field, "in", ids).orderBy("createdAt", "desc");
        if (before) q = q.startAfter(Timestamp.fromMillis(before));
        return q.limit(limit).get();
      }),
    );
    return snaps
      .flatMap((s) => s.docs.map(doc))
      .sort((a, b) => String(b.data.createdAt ?? "").localeCompare(String(a.data.createdAt ?? "")))
      .slice(0, limit);
  }
}
