import { FieldValue, type Firestore, Timestamp, type Transaction } from "firebase-admin/firestore";
import { AlreadyExists, type Data, type DocStore, deleteField, serverTime, type Tx } from "./store.js";

/** Timestamps → Date, recursively, so services see plain data. */
export function fromFirestore(v: unknown): unknown {
  if (v instanceof Timestamp) return v.toDate();
  if (Array.isArray(v)) return v.map(fromFirestore);
  if (v && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype) {
    return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fromFirestore(x)]));
  }
  return v;
}

/** serverTime → FieldValue.serverTimestamp(), recursively. */
function toFirestore(v: unknown): unknown {
  if (v === serverTime) return FieldValue.serverTimestamp();
  if (v === deleteField) return FieldValue.delete();
  if (Array.isArray(v)) return v.map(toFirestore);
  if (v && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype) {
    return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toFirestore(x)]));
  }
  return v;
}

const toData = (d: Data) => toFirestore(d) as Data;

/** gRPC ALREADY_EXISTS, from a create() on an existing document. */
const alreadyExists = (e: unknown) => (e as { code?: unknown })?.code === 6;

export class FirestoreDocStore implements DocStore {
  constructor(private readonly db: Firestore) {}

  async get(path: string): Promise<Data | null> {
    const snap = await this.db.doc(path).get();
    return snap.exists ? (fromFirestore(snap.data()) as Data) : null;
  }

  async getAll(paths: string[], fields?: readonly string[]): Promise<Array<Data | null>> {
    const out: Array<Data | null> = [];
    // A few hundred documents a call keeps each request small.
    for (let i = 0; i < paths.length; i += 300) {
      const refs = paths.slice(i, i + 300).map((p) => this.db.doc(p));
      const snaps = await (fields ? this.db.getAll(...refs, { fieldMask: [...fields] }) : this.db.getAll(...refs));
      out.push(...snaps.map((s) => (s.exists ? (fromFirestore(s.data()) as Data) : null)));
    }
    return out;
  }

  async list(collection: string, limit: number): Promise<Array<{ id: string; data: Data }>> {
    const snap = await this.db.collection(collection).limit(limit).get();
    return snap.docs.map((d) => ({ id: d.id, data: fromFirestore(d.data()) as Data }));
  }

  newId(collection: string): string {
    return this.db.collection(collection).doc().id;
  }

  async transact<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    try {
      return await this.db.runTransaction((t: Transaction) => fn(this.wrap(t)));
    } catch (e) {
      if (alreadyExists(e)) throw new AlreadyExists(String(e));
      throw e;
    }
  }

  private wrap(t: Transaction): Tx {
    const db = this.db;
    return {
      async get(path) {
        const snap = await t.get(db.doc(path));
        return snap.exists ? (fromFirestore(snap.data()) as Data) : null;
      },
      create: (path, data) => void t.create(db.doc(path), toData(data)),
      set: (path, data) => void t.set(db.doc(path), toData(data)),
      update: (path, data) => void t.update(db.doc(path), toData(data)),
      merge: (path, data) => void t.set(db.doc(path), toData(data), { merge: true }),
      delete: (path) => void t.delete(db.doc(path)),
    };
  }
}
