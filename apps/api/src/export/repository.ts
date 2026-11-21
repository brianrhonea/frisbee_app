import { type DocumentSnapshot, FieldPath, type Firestore, type Query } from "firebase-admin/firestore";
import { type Data, plain } from "../browse/repository.js";

/** A document with its full path (where it lives says what it is: a DM, a team chat, …). */
export interface PathDoc {
  id: string;
  path: string;
  data: Data;
}

/**
 * The reads "Download your data" makes, all about one person ([uid]).
 * Each list method returns at most [limit] + 1 documents, so the service
 * can tell a capped section (`truncated`) from a complete one. Values come
 * back with Timestamps as ISO strings.
 */
export interface ExportRepository {
  /** One document of the caller's own (users/{uid}, profiles/{uid}, their settings…); null when missing. */
  own(path: string): Promise<Data | null>;
  /** Documents of one of the caller's own collections (users/{uid}/follows, users/{uid}/events). */
  ownCollection(path: string, limit: number): Promise<PathDoc[]>;
  /** Posts, comments or messages anywhere (collection groups) whose authorId is [uid]. */
  authored(group: "posts" | "comments" | "messages", uid: string, limit: number): Promise<PathDoc[]>;
  /** Conversations listing [uid] in participants. */
  conversationsOf(uid: string, limit: number): Promise<PathDoc[]>;
  /** Teams listing [uid] in memberIds. */
  teamsOf(uid: string, limit: number): Promise<PathDoc[]>;
  /**
   * A team's events or meetings with only [fields] and the caller's own
   * entry of each response map in [responseFields] (`rsvps.{uid}`, …).
   */
  answers(teamId: string, kind: "events" | "meetings", uid: string, fields: readonly string[], responseFields: readonly string[], limit: number): Promise<PathDoc[]>;
  /** Roster spots on any team linked to [uid] (roster userId). */
  rosterSpots(uid: string, limit: number): Promise<PathDoc[]>;
  /**
   * A team's chat messages carrying a poll [uid] voted in (F33), with only
   * the poll's question, options and the caller's own vote (`poll.votes.{uid}`).
   */
  pollVotes(teamId: string, uid: string, limit: number): Promise<PathDoc[]>;
  /**
   * [uid]'s waiting requests to join (teams/{t}/joinRequests/{uid}, F26),
   * each with its team's name and kind: looked up on the groups that
   * approve who joins and the teams that allow requests (only they hold
   * any, as account deletion finds them).
   */
  joinRequestsOf(uid: string, limit: number): Promise<Array<PathDoc & { team: Data }>>;
  /** Reports [uid] made (reports where reporterId). */
  reportsBy(uid: string, limit: number): Promise<PathDoc[]>;
}

/** Documents read per round trip while paging through a long list. */
const pageSize = 500;

const pathDoc = (d: DocumentSnapshot): PathDoc => ({ id: d.id, path: d.ref.path, data: plain(d.data() ?? {}) as Data });

export class FirestoreExportRepository implements ExportRepository {
  constructor(private readonly db: Firestore) {}

  /** Up to [max] documents of [query], [pageSize] at a time, in document order. */
  private async paged(query: Query, max: number): Promise<PathDoc[]> {
    const out: PathDoc[] = [];
    let last: DocumentSnapshot | undefined;
    while (out.length < max) {
      let q = query.limit(Math.min(pageSize, max - out.length));
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      out.push(...snap.docs.map(pathDoc));
      if (snap.size < pageSize) break;
      last = snap.docs[snap.docs.length - 1];
    }
    return out;
  }

  async own(path: string) {
    const snap = await this.db.doc(path).get();
    return snap.exists ? (plain(snap.data()) as Data) : null;
  }

  ownCollection(path: string, limit: number) {
    return this.paged(this.db.collection(path), limit + 1);
  }

  reportsBy(uid: string, limit: number) {
    return this.paged(this.db.collection("reports").where("reporterId", "==", uid), limit + 1);
  }

  // Indexes: single-field collection-group exemptions on authorId (posts,
  // comments, messages), as deleteAccount's queries use.
  authored(group: "posts" | "comments" | "messages", uid: string, limit: number) {
    return this.paged(this.db.collectionGroup(group).where("authorId", "==", uid), limit + 1);
  }

  conversationsOf(uid: string, limit: number) {
    return this.paged(this.db.collection("conversations").where("participants", "array-contains", uid), limit + 1);
  }

  teamsOf(uid: string, limit: number) {
    return this.paged(this.db.collection("teams").where("memberIds", "array-contains", uid), limit + 1);
  }

  answers(teamId: string, kind: "events" | "meetings", uid: string, fields: readonly string[], responseFields: readonly string[], limit: number) {
    const paths = [...fields.map((f) => new FieldPath(f)), ...responseFields.map((f) => new FieldPath(f, uid))];
    return this.paged(this.db.collection(`teams/${teamId}/${kind}`).select(...paths), limit + 1);
  }

  rosterSpots(uid: string, limit: number) {
    return this.paged(this.db.collectionGroup("roster").where("userId", "==", uid), limit + 1);
  }

  async joinRequestsOf(uid: string, limit: number) {
    const [groups, teams] = await Promise.all([
      this.db.collection("teams").where("kind", "in", ["community", "organization"]).where("requiresApproval", "==", true).select("name", "kind").get(),
      this.db.collection("teams").where("allowJoinRequests", "==", true).select("name", "kind").get(),
    ]);
    const hosts = [...groups.docs, ...teams.docs];
    const out: Array<PathDoc & { team: Data }> = [];
    for (let i = 0; i < hosts.length && out.length <= limit; i += 300) {
      const chunk = hosts.slice(i, i + 300);
      const found = await this.db.getAll(...chunk.map((h) => h.ref.collection("joinRequests").doc(uid)));
      found.forEach((r, j) => {
        if (r.exists) out.push({ ...pathDoc(r), team: plain(chunk[j]!.data()) as Data });
      });
    }
    return out.slice(0, limit + 1);
  }

  // Room by room (collection scope, poll.voterIds' automatic index): no
  // collection-group index needed.
  async pollVotes(teamId: string, uid: string, limit: number) {
    const rooms = await this.db.collection(`teams/${teamId}/chats`).select().get();
    const out: PathDoc[] = [];
    for (const room of rooms.docs) {
      if (out.length > limit) break;
      const q = room.ref
        .collection("messages")
        .where("poll.voterIds", "array-contains", uid)
        .select(new FieldPath("poll", "question"), new FieldPath("poll", "options"), new FieldPath("poll", "votes", uid));
      out.push(...(await this.paged(q, limit + 1 - out.length)));
    }
    return out;
  }
}
