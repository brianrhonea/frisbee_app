// Small queries for services that would otherwise read a whole collection
// through DocStore.list, whose documents can be large (a stats game is up
// to ~900 KB): ids only, or only the fields a service reads. Equality
// filters only, so Firestore's single-field indexes serve them and no
// composite index is needed. FirestoreDocQueries is the real one;
// listDocQueries reads through a DocStore for tests (as listDraftQueries).
import { FieldPath, type Firestore, type Query } from "firebase-admin/firestore";
import { fromFirestore } from "./firestore_store.js";
import type { Data, DocStore } from "./store.js";

/** Field == value, every one of them. */
export type Where = Record<string, string | boolean>;

export interface DocQueries {
  /** Ids of up to [limit] documents of [collection] matching [where], in id order. */
  ids(collection: string, limit: number, where?: Where): Promise<string[]>;
  /** Up to [limit] documents of [collection] matching [where], in id order (after id [after], to page), with only [fields]. */
  fields(collection: string, fields: readonly string[], limit: number, where?: Where, after?: string): Promise<Array<{ id: string; data: Data }>>;
  /**
   * Up to [limit] documents of every collection named [collectionId]
   * matching [where], with their full paths (a collection group query;
   * each filtered field needs its collection-group index in
   * firestore.indexes.json), with only [fields] when given. Optional: without it the caller says so.
   */
  group?(collectionId: string, limit: number, where: Where, fields?: readonly string[]): Promise<Array<{ path: string; data: Data }>>;
}

export class FirestoreDocQueries implements DocQueries {
  constructor(private readonly db: Firestore) {}

  private query(collection: string, where: Where = {}): Query {
    let q: Query = this.db.collection(collection);
    for (const [field, value] of Object.entries(where)) q = q.where(field, "==", value);
    return q;
  }

  async ids(collection: string, limit: number, where?: Where): Promise<string[]> {
    // select() with no fields: document names only.
    const snap = await this.query(collection, where).select().limit(limit).get();
    return snap.docs.map((d) => d.id);
  }

  async fields(collection: string, fields: readonly string[], limit: number, where?: Where, after?: string) {
    let q = this.query(collection, where);
    // Document-id order is the default: no index.
    if (after !== undefined) q = q.orderBy(FieldPath.documentId()).startAfter(after);
    const snap = await q
      .select(...fields)
      .limit(limit)
      .get();
    return snap.docs.map((d) => ({ id: d.id, data: fromFirestore(d.data()) as Data }));
  }

  async group(collectionId: string, limit: number, where: Where, fields?: readonly string[]) {
    let q: Query = this.db.collectionGroup(collectionId);
    for (const [field, value] of Object.entries(where)) q = q.where(field, "==", value);
    if (fields) q = q.select(...fields);
    const snap = await q.limit(limit).get();
    return snap.docs.map((d) => ({ path: d.ref.path, data: fromFirestore(d.data()) as Data }));
  }
}

/** The same through [store]'s list (tests, and runs without Firestore). Reads at most [cap] documents. */
export function listDocQueries(store: DocStore, cap = 5000): DocQueries {
  const matches = (data: Data, where: Where) => Object.entries(where).every(([k, v]) => data[k] === v);
  return {
    async ids(collection, limit, where = {}) {
      const all = await store.list(collection, Object.keys(where).length ? cap : limit);
      return all
        .filter((d) => matches(d.data, where))
        .slice(0, limit)
        .map((d) => d.id);
    },
    async fields(collection, fields, limit, where = {}, after) {
      const all = await store.list(collection, Object.keys(where).length || after !== undefined ? cap : limit);
      return all
        .filter((d) => after === undefined || d.id > after)
        .filter((d) => matches(d.data, where))
        .slice(0, limit)
        .map((d) => ({ id: d.id, data: Object.fromEntries(fields.filter((f) => f in d.data).map((f) => [f, d.data[f]])) }));
    },
  };
}
