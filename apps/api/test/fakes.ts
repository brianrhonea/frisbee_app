import type { CreateTeamInput, NameListing } from "@stall10/shared";
import type { Caller, TokenVerifier, UserLookup } from "../src/auth.js";
import type { Owner } from "../src/teams/documents.js";
import type { TeamRepository } from "../src/teams/repository.js";
import { AlreadyExists, type Data, type DocStore, deleteField, serverTime, type Tx } from "../src/store.js";

/** Accepts tokens "token:<uid>[:<name>]" and App Check token "good". */
export class FakeVerifier implements TokenVerifier {
  async verifyIdToken(token: string): Promise<Caller> {
    const [kind, uid, name] = token.split(":");
    if (kind !== "token" || !uid) throw new Error("bad token");
    return { uid, name, email: `${uid}@x.test` };
  }

  async verifyAppCheck(token: string): Promise<void> {
    if (token !== "good") throw new Error("bad app check");
  }
}

/** Auth user records by uid; unknown users fall back to the token. */
export class FakeUsers implements UserLookup {
  records = new Map<string, { name?: string; email?: string; photoUrl?: string }>();

  async lookup(uid: string) {
    return this.records.get(uid) ?? null;
  }
}

export class FakeTeamRepository implements TeamRepository {
  muted = new Map<string, number>();
  leagues = new Map<string, boolean>();
  listings: Array<NameListing & { keywords: string[] }> = [];
  created: Array<{ id: string; input: CreateTeamInput; owner: Owner }> = [];

  async mutedUntil(uid: string) {
    return this.muted.get(uid) ?? null;
  }

  async leagueTakesTeams(id: string) {
    return this.leagues.get(id) ?? false;
  }

  async listingsWithKeywords(keywords: string[], limit: number) {
    return this.listings.filter((l) => l.keywords.some((k) => keywords.includes(k))).slice(0, limit);
  }

  async createTeam(input: CreateTeamInput, owner: Owner) {
    const id = `team${this.created.length + 1}`;
    this.created.push({ id, input, owner });
    return id;
  }
}

/**
 * Documents in memory, with transactions applied all at once at the end
 * (like Firestore's: reads first, then writes). serverTime is written as
 * [now].
 */
export class FakeStore implements DocStore {
  docs = new Map<string, Data>();
  private ids = 0;

  constructor(private readonly now: () => number = Date.now) {}

  /** Seeds or reads a document. */
  put(path: string, data: Data) {
    this.docs.set(path, structuredClone(data));
  }
  doc(path: string): Data | undefined {
    return this.docs.get(path);
  }

  async get(path: string) {
    const d = this.docs.get(path);
    return d ? structuredClone(d) : null;
  }

  newId(collection: string) {
    return `${collection.split("/").pop()}-new${++this.ids}`;
  }

  private stamp(v: unknown): unknown {
    if (v === serverTime) return new Date(this.now());
    if (Array.isArray(v)) return v.map((x) => this.stamp(x));
    if (v && typeof v === "object" && !(v instanceof Date)) {
      return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, this.stamp(x)]));
    }
    return v;
  }

  /** Top-level fields of [data] onto [d]; deleteField removes one. */
  private apply(d: Data, data: Data): Data {
    const out = { ...d };
    for (const [k, v] of Object.entries(data)) {
      if (v === deleteField) delete out[k];
      else out[k] = this.stamp(v);
    }
    return out;
  }

  async transact<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    const writes: Array<() => void> = [];
    const tx: Tx = {
      get: (path) => this.get(path),
      create: (path, data) =>
        writes.push(() => {
          if (this.docs.has(path)) throw new AlreadyExists(path);
          this.docs.set(path, this.stamp(data) as Data);
        }),
      set: (path, data) => writes.push(() => this.docs.set(path, this.stamp(data) as Data)),
      update: (path, data) =>
        writes.push(() => {
          const d = this.docs.get(path);
          if (!d) throw new Error(`update of missing ${path}`);
          this.docs.set(path, this.apply(d, data));
        }),
      merge: (path, data) => writes.push(() => this.docs.set(path, this.apply(this.docs.get(path) ?? {}, data))),
      delete: (path) => writes.push(() => this.docs.delete(path)),
    };
    const result = await fn(tx);
    // All or nothing, like a commit.
    const before = new Map(this.docs);
    try {
      for (const w of writes) w();
    } catch (e) {
      this.docs = before;
      throw e;
    }
    return result;
  }
}
