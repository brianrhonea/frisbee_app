import { type DocumentData, type Firestore, type Query, Timestamp } from "firebase-admin/firestore";
import { pageSize, eventLimit } from "./model.js";
import { searchLimit } from "../limits/model.js";

export type Data = Record<string, unknown>;
export interface Doc {
  id: string;
  data: Data;
}

/**
 * Raw reads for the public pages. Values come back as stored except that
 * Timestamps become ISO strings; the service decides what's shown.
 */
export interface BrowseRepository {
  /** Newest posts (all authors), before [before] ms if given. */
  posts(before: number | null, authorId?: string): Promise<Doc[]>;
  post(id: string): Promise<Doc | null>;
  profiles(ids: string[]): Promise<Map<string, Data>>;
  listing(teamId: string): Promise<Data | null>;
  listings(teamIds: string[]): Promise<Map<string, Data>>;
  publicTeamPosts(teamId: string): Promise<Doc[]>;
  upcomingTeamEvents(teamId: string, now: number): Promise<Doc[]>;
  /** Upcoming public events across all teams, with their team's id. */
  upcomingEvents(now: number): Promise<Array<Doc & { teamId: string }>>;
  upcomingTournaments(now: number): Promise<Doc[]>;
  searchProfiles(key: string): Promise<Doc[]>;
  searchListings(key: string): Promise<Doc[]>;
}

/** Firestore values as JSON: Timestamps become ISO strings. */
export function plain(value: unknown): unknown {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
  }
  return value;
}

const doc = (d: { id: string; data: () => DocumentData | undefined }): Doc => ({
  id: d.id,
  data: plain(d.data() ?? {}) as Data,
});

export class FirestoreBrowseRepository implements BrowseRepository {
  constructor(private readonly db: Firestore) {}

  private page(query: Query, before: number | null): Query {
    const ordered = query.orderBy("createdAt", "desc");
    return (before ? ordered.startAfter(Timestamp.fromMillis(before)) : ordered).limit(pageSize);
  }

  async posts(before: number | null, authorId?: string): Promise<Doc[]> {
    const base = this.db.collection("posts");
    const q = authorId ? base.where("authorId", "==", authorId) : base;
    return (await this.page(q, before).get()).docs.map(doc);
  }

  async post(id: string): Promise<Doc | null> {
    const snap = await this.db.doc(`posts/${id}`).get();
    return snap.exists ? doc(snap) : null;
  }

  private async getAll(paths: string[]): Promise<Map<string, Data>> {
    const unique = [...new Set(paths)];
    if (unique.length === 0) return new Map();
    const snaps = await this.db.getAll(...unique.map((p) => this.db.doc(p)));
    return new Map(snaps.filter((s) => s.exists).map((s) => [s.id, plain(s.data()) as Data]));
  }

  profiles(ids: string[]) {
    return this.getAll(ids.map((id) => `profiles/${id}`));
  }

  async listing(teamId: string): Promise<Data | null> {
    const snap = await this.db.doc(`teamDirectory/${teamId}`).get();
    return snap.exists ? (plain(snap.data()) as Data) : null;
  }

  listings(teamIds: string[]) {
    return this.getAll(teamIds.map((id) => `teamDirectory/${id}`));
  }

  async publicTeamPosts(teamId: string): Promise<Doc[]> {
    const snap = await this.db
      .collection(`teams/${teamId}/posts`)
      .where("public", "==", true)
      .orderBy("createdAt", "desc")
      .limit(pageSize)
      .get();
    return snap.docs.map(doc);
  }

  async upcomingTeamEvents(teamId: string, now: number): Promise<Doc[]> {
    const snap = await this.db
      .collection(`teams/${teamId}/publicEvents`)
      .where("startsAt", ">=", Timestamp.fromMillis(now))
      .orderBy("startsAt")
      .limit(pageSize)
      .get();
    return snap.docs.map(doc);
  }

  async upcomingEvents(now: number) {
    const snap = await this.db
      .collectionGroup("publicEvents")
      .where("startsAt", ">=", Timestamp.fromMillis(now))
      .orderBy("startsAt")
      .limit(eventLimit)
      .get();
    return snap.docs.map((d) => ({ ...doc(d), teamId: d.ref.parent.parent?.id ?? "" }));
  }

  async upcomingTournaments(now: number): Promise<Doc[]> {
    const snap = await this.db
      .collection("tournamentDirectory")
      .where("startsAt", ">=", Timestamp.fromMillis(now))
      .orderBy("startsAt")
      .limit(eventLimit)
      .get();
    return snap.docs.map(doc);
  }

  async searchProfiles(key: string): Promise<Doc[]> {
    const snap = await this.db.collection("profiles").where("keywords", "array-contains", key).limit(searchLimit).get();
    return snap.docs.map(doc);
  }

  async searchListings(key: string): Promise<Doc[]> {
    const snap = await this.db.collection("teamDirectory").where("keywords", "array-contains", key).limit(searchLimit).get();
    return snap.docs.map(doc);
  }
}
