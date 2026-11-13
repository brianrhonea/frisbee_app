import { readFile, writeFile } from "node:fs/promises";
import type { CreateTeamInput, NameListing } from "@stall10/shared";
import type { Caller, TokenVerifier, UserLookup } from "../src/auth.js";
import type { MediaStorage } from "../src/media/storage.js";
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

  async list(collection: string, limit: number) {
    const prefix = `${collection}/`;
    return [...this.docs.entries()]
      .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
      .sort(([a], [b]) => a.localeCompare(b))
      .slice(0, limit)
      .map(([path, data]) => ({ id: path.slice(prefix.length), data: structuredClone(data) }));
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

/** Cloud Storage in memory. Signed URLs are fake ("signed:" + path). */
export class FakeMediaStorage implements MediaStorage {
  files = new Map<string, { data: Buffer; contentType?: string }>();
  signed: Array<{ path: string; contentType: string; maxBytes: number; expiresAt: Date }> = [];

  async signedUploadUrl(path: string, contentType: string, maxBytes: number, expiresAt: Date) {
    this.signed.push({ path, contentType, maxBytes, expiresAt });
    return { url: `signed:${path}`, headers: { "content-type": contentType, "x-goog-content-length-range": `0,${maxBytes}` } };
  }
  async size(path: string) {
    return this.files.get(path)?.data.length ?? null;
  }
  async read(path: string, bytes?: number) {
    const f = this.files.get(path);
    if (!f) throw new Error(`no ${path}`);
    return bytes ? f.data.subarray(0, bytes) : f.data;
  }
  async write(path: string, data: Buffer, contentType: string) {
    this.files.set(path, { data, contentType });
  }
  async downloadTo(path: string, file: string) {
    await writeFile(file, await this.read(path));
  }
  async uploadFrom(file: string, path: string, contentType: string) {
    this.files.set(path, { data: await readFile(file), contentType });
  }
  async delete(path: string) {
    this.files.delete(path);
  }
}
