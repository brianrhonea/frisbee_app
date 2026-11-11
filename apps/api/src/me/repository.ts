import { type Firestore, Timestamp } from "firebase-admin/firestore";
import { type Data, type Doc, plain } from "../browse/repository.js";

/** Firestore's limit on values in one `in` query. */
const inLimit = 30;

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
  /** A team's events from [now], soonest first. */
  upcomingEvents(teamId: string, now: number, limit: number): Promise<Doc[]>;
  /** Ids of the people [uid] follows (users/{uid}/follows, type user). */
  followedUsers(uid: string): Promise<string[]>;
  /** Newest posts by [authors] before [before] ms if given, merged. */
  postsBy(authors: string[], before: number | null, limit: number): Promise<Doc[]>;
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

  async upcomingEvents(teamId: string, now: number, limit: number) {
    const snap = await this.db
      .collection(`teams/${teamId}/events`)
      .where("startsAt", ">=", Timestamp.fromMillis(now))
      .orderBy("startsAt")
      .limit(limit)
      .get();
    return snap.docs.map(doc);
  }

  async followedUsers(uid: string) {
    const snap = await this.db.collection(`users/${uid}/follows`).where("type", "==", "user").get();
    return snap.docs.map((d) => d.get("targetId")).filter((id): id is string => typeof id === "string" && id !== "");
  }

  async postsBy(authors: string[], before: number | null, limit: number) {
    const unique = [...new Set(authors)];
    const chunks: string[][] = [];
    for (let i = 0; i < unique.length; i += inLimit) chunks.push(unique.slice(i, i + inLimit));
    // Index: posts (authorId, createdAt desc), as the app's feed uses.
    const snaps = await Promise.all(
      chunks.map((ids) => {
        let q = this.db.collection("posts").where("authorId", "in", ids).orderBy("createdAt", "desc");
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
