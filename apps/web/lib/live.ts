"use client";
import {
  collection,
  doc,
  type DocumentData,
  onSnapshot,
  query,
  type QueryConstraint,
  Timestamp,
} from "firebase/firestore";
import { useEffect, useState } from "react";
import { firestoreDb } from "./firebase";

// Live reads from Firestore for the member area, as the app reads them: the
// rules decide what a member may see. Writes go through the API
// (lib/client.ts). Timestamps come back as ISO strings, like the API's.

/** Firestore data with Timestamps as ISO strings, all the way down. */
export function plain(v: unknown): unknown {
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === "object") {
    return Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, plain(x)]));
  }
  return v;
}

/** A document with its id. */
export type Doc<T> = T & { id: string };

/** What a live read holds: undefined while loading, then the data, or an error. */
export interface Live<T> {
  data: T | undefined;
  error: string | null;
}

const denied = "You can't see this.";
const failed = "Couldn't load this. Check your connection and refresh.";

function message(e: { code?: string }) {
  return e.code === "permission-denied" ? denied : failed;
}

/**
 * The document at [path], kept up to date; null when it doesn't exist.
 * Pass null to read nothing (e.g. until the member is known).
 */
export function useLiveDoc<T = DocumentData>(path: string | null): Live<Doc<T> | null> {
  const [state, setState] = useState<Live<Doc<T> | null>>({ data: undefined, error: null });
  useEffect(() => {
    const db = firestoreDb();
    if (!path || !db) {
      setState({ data: path ? null : undefined, error: null });
      return;
    }
    setState({ data: undefined, error: null });
    return onSnapshot(
      doc(db, path),
      (snap) =>
        setState({
          data: snap.exists() ? ({ ...(plain(snap.data()) as T), id: snap.id } as Doc<T>) : null,
          error: null,
        }),
      (e) => setState({ data: undefined, error: message(e) }),
    );
  }, [path]);
  return state;
}

/**
 * The documents in collection [path] matching [constraints], kept up to
 * date. [key] names the query so it re-subscribes only when that changes
 * (constraints are rebuilt every render). Pass null to read nothing.
 */
export function useLiveQuery<T = DocumentData>(
  path: string | null,
  constraints: QueryConstraint[],
  key: string,
): Live<Doc<T>[]> {
  const [state, setState] = useState<Live<Doc<T>[]>>({ data: undefined, error: null });
  useEffect(() => {
    const db = firestoreDb();
    if (!path || !db) {
      setState({ data: path ? [] : undefined, error: null });
      return;
    }
    setState({ data: undefined, error: null });
    return onSnapshot(
      query(collection(db, path), ...constraints),
      (snap) =>
        setState({
          data: snap.docs.map((d) => ({ ...(plain(d.data()) as T), id: d.id }) as Doc<T>),
          error: null,
        }),
      (e) => setState({ data: undefined, error: message(e) }),
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps -- [key] stands for constraints.
  }, [path, key]);
  return state;
}

/** Something to watch for changes: a document, or a query on a collection. */
export type Signal = { doc: string } | { collection: string; constraints: QueryConstraint[] };

/**
 * A number that goes up each time any of [signals] changes (once on
 * subscribing too): a cue to refetch a view the API builds, for pages
 * whose privacy rules live in the API rather than firestore.rules. [key]
 * names the set, so it re-subscribes only when that changes. A signal the
 * rules refuse is just never heard from.
 */
export function useChangeSignal(signals: Signal[] | null, key: string): number {
  const [version, setVersion] = useState(0);
  useEffect(() => {
    const db = firestoreDb();
    if (!signals || !db) return;
    const bump = () => setVersion((v) => v + 1);
    const stops = signals.map((s) =>
      "doc" in s
        ? onSnapshot(doc(db, s.doc), bump, () => undefined)
        : onSnapshot(query(collection(db, s.collection), ...s.constraints), bump, () => undefined),
    );
    return () => stops.forEach((stop) => stop());
    // eslint-disable-next-line react-hooks/exhaustive-deps -- [key] stands for signals.
  }, [key]);
  return version;
}

/**
 * Several queries on collection [path], merged by id: for reads the rules
 * allow only one audience id at a time (chat rooms, a community's events),
 * as the app's mergeLatest does. Loading until every query has answered.
 */
export function useLiveQueries<T = DocumentData>(
  path: string | null,
  queries: QueryConstraint[][],
  key: string,
): Live<Doc<T>[]> {
  const [state, setState] = useState<Live<Doc<T>[]>>({ data: undefined, error: null });
  useEffect(() => {
    const db = firestoreDb();
    if (!path || !db) {
      setState({ data: path ? [] : undefined, error: null });
      return;
    }
    setState({ data: undefined, error: null });
    const results: Array<Doc<T>[] | undefined> = queries.map(() => undefined);
    const publish = () => {
      if (results.some((r) => r === undefined)) return;
      const byId = new Map<string, Doc<T>>();
      for (const r of results) for (const d of r!) byId.set(d.id, d);
      setState({ data: [...byId.values()], error: null });
    };
    const stops = queries.map((constraints, i) =>
      onSnapshot(
        query(collection(db, path), ...constraints),
        (snap) => {
          results[i] = snap.docs.map((d) => ({ ...(plain(d.data()) as T), id: d.id }) as Doc<T>);
          publish();
        },
        (e) => setState({ data: undefined, error: message(e) }),
      ),
    );
    return () => stops.forEach((stop) => stop());
    // eslint-disable-next-line react-hooks/exhaustive-deps -- [key] stands for queries.
  }, [path, key]);
  return state;
}
