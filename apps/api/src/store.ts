// Document access for services that need transactions: read the documents
// a rule looked at, decide, then write, all atomically. Services see plain
// data (timestamps come back as Date) and stay free of Firebase imports;
// firestore_store.ts is the real implementation, tests use an in-memory
// one (test/fakes.ts).

/** A document's fields. Timestamps read back as Date. */
export type Data = Record<string, unknown>;

/**
 * Written as the server's clock (FieldValue.serverTimestamp()). Allowed as
 * a field value anywhere in written data.
 */
export const serverTime: unique symbol = Symbol("serverTime");

/** Reads and writes inside one transaction. Every read comes before any write. */
export interface Tx {
  get(path: string): Promise<Data | null>;
  /** Fails the transaction if the document exists. */
  create(path: string, data: Data): void;
  set(path: string, data: Data): void;
  /** Replaces the given top-level fields; the document must exist. */
  update(path: string, data: Data): void;
  delete(path: string): void;
}

export interface DocStore {
  get(path: string): Promise<Data | null>;
  /** A fresh auto id for a document in [collection]. */
  newId(collection: string): string;
  /** Runs [fn] in a transaction, retried on contention. */
  transact<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
}

/** Thrown by Tx.create when the document already exists. */
export class AlreadyExists extends Error {}
