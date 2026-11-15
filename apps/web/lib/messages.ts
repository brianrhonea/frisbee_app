"use client";
import {
  collection,
  getDocs,
  limit as take,
  onSnapshot,
  orderBy,
  query,
  type QueryDocumentSnapshot,
  startAfter,
} from "firebase/firestore";
import { type RefObject, useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { firestoreDb } from "./firebase";
import { type Doc, plain } from "./live";

// A chat thread's messages as the app's MessageThreadViewModel keeps them:
// the newest page live, and older pages loaded on request with a query
// that starts after the oldest message loaded (fetchOlderMessages).

interface Row<T> {
  doc: Doc<T & { createdAt?: string | null }>;
  snap: QueryDocumentSnapshot;
}

const ms = (iso?: string | null) => (iso ? Date.parse(iso) : Number.NaN);

function rows<T>(docs: QueryDocumentSnapshot[]): Row<T>[] {
  return docs.map((snap) => ({ snap, doc: { ...(plain(snap.data()) as T), id: snap.id } }));
}

/**
 * A new message pushes the oldest out of the live page: keep it with the
 * older pages unless it was deleted (the app's _keepPushedOut). A
 * pushed-out message is older than everything still in a full page; a
 * deleted one isn't, or the page wasn't full.
 */
function pushedOut<T extends { createdAt?: string | null }>(
  before: Doc<T>[] | null,
  after: Doc<T>[],
  pageLimit: number,
): Doc<T>[] {
  if (!before || after.length === 0 || after.length < pageLimit) return [];
  const oldest = Math.min(...after.map((m) => ms(m.createdAt)).filter((t) => !Number.isNaN(t)));
  if (!Number.isFinite(oldest)) return [];
  const ids = new Set(after.map((m) => m.id));
  return before.filter((m) => !ids.has(m.id) && ms(m.createdAt) < oldest);
}

export interface PagedMessages<T> {
  /** Oldest first; undefined while the first page loads. */
  list: Doc<T>[] | undefined;
  error: string | null;
  /** More messages may be on the server than those loaded. */
  hasMore: boolean;
  loadingMore: boolean;
  /** Whether scrolling to the top should load the next page by itself (off once paging fails). */
  autoLoad: boolean;
  loadOlder: () => Promise<void>;
  /** Drops a deleted message from the older pages (they aren't live). */
  removed: (id: string) => void;
}

/**
 * The messages in collection [path], ordered by createdAt: the newest
 * [pageSize] live, and older pages of [pageSize] from [loadOlder]. Paging
 * stops at [hiddenBefore] (ms; a DM the member cleared). If a page query
 * fails, it falls back to listening to a bigger live page, as the app does.
 */
export function usePagedMessages<T extends { createdAt?: string | null }>(
  path: string | null,
  pageSize: number,
  hiddenBefore = Number.NaN,
): PagedMessages<T> {
  const [limit, setLimit] = useState(pageSize);
  const [live, setLive] = useState<Row<T>[] | undefined>(undefined);
  const [older, setOlder] = useState<Row<T>[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [exhausted, setExhausted] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [pagingFailed, setPagingFailed] = useState(false);
  const liveRef = useRef<Row<T>[] | null>(null);

  // A new thread starts over.
  useEffect(() => {
    setLimit(pageSize);
    setLive(undefined);
    setOlder([]);
    setExhausted(false);
    setPagingFailed(false);
    liveRef.current = null;
  }, [path, pageSize]);

  useEffect(() => {
    const db = firestoreDb();
    if (!path || !db) return;
    return onSnapshot(
      query(collection(db, path), orderBy("createdAt", "desc"), take(limit)),
      (snap) => {
        const next = rows<T>(snap.docs);
        const before = liveRef.current;
        const pushed = before ? pushedOut(before.map((r) => r.doc), next.map((r) => r.doc), limit) : [];
        const pushedRows = before?.filter((r) => pushed.some((p) => p.id === r.doc.id)) ?? [];
        const ids = new Set(next.map((r) => r.doc.id));
        setOlder((o) => {
          // A deletion pulls an older message back into the live page.
          const kept = o.filter((r) => !ids.has(r.doc.id));
          const known = new Set(kept.map((r) => r.doc.id));
          // Pushed-out messages are newer than every older page: oldest first, at the end.
          return [...kept, ...pushedRows.filter((r) => !known.has(r.doc.id)).reverse()];
        });
        liveRef.current = next;
        setLive(next);
        setError(null);
      },
      (e) => {
        setError(e.code === "permission-denied" ? "You can't see this." : "Couldn't load messages. Check your connection and refresh.");
        setLive((l) => l ?? []);
      },
    );
  }, [path, limit]);

  const oldestRow = older[0] ?? live?.[live.length - 1];
  const oldestAt = ms(oldestRow?.doc.createdAt);
  const reachedHidden = !Number.isNaN(hiddenBefore) && !Number.isNaN(oldestAt) && oldestAt <= hiddenBefore;
  const hasMore = !exhausted && !reachedHidden && (live?.length ?? 0) >= limit;

  const loadOlder = useCallback(async () => {
    const db = firestoreDb();
    if (!path || !db || loadingMore || !hasMore || !oldestRow) return;
    if (pagingFailed) {
      setLimit((l) => l + pageSize);
      return;
    }
    setLoadingMore(true);
    try {
      const snap = await getDocs(query(collection(db, path), orderBy("createdAt", "desc"), startAfter(oldestRow.snap), take(pageSize)));
      const page = rows<T>(snap.docs).reverse();
      setOlder((o) => {
        const known = new Set(o.map((r) => r.doc.id));
        return [...page.filter((r) => !known.has(r.doc.id)), ...o];
      });
      if (page.length < pageSize) setExhausted(true);
    } catch {
      setPagingFailed(true);
      setOlder([]);
      setLimit((l) => l + pageSize);
    } finally {
      setLoadingMore(false);
    }
  }, [path, pageSize, loadingMore, hasMore, oldestRow, pagingFailed]);

  const removed = useCallback((id: string) => setOlder((o) => o.filter((r) => r.doc.id !== id)), []);

  const list = live === undefined ? undefined : [...older.map((r) => r.doc), ...live.slice().reverse().map((r) => r.doc)];
  return { list, error, hasMore, loadingMore, autoLoad: !pagingFailed && !loadingMore, loadOlder, removed };
}

/**
 * Keeps a thread's scroll where it belongs: at the bottom when a newer
 * message arrives (and on opening), and where the reader was when older
 * messages are added above. Pass the oldest and newest ids shown.
 */
export function useThreadScroll(body: RefObject<HTMLElement | null>, firstId: string | undefined, lastId: string | undefined) {
  const prev = useRef<{ first?: string; last?: string; height: number }>({ height: 0 });
  useLayoutEffect(() => {
    const el = body.current;
    if (!el) return;
    const p = prev.current;
    if (lastId !== p.last) el.scrollTop = el.scrollHeight;
    else if (firstId !== p.first) el.scrollTop += el.scrollHeight - p.height;
    prev.current = { first: firstId, last: lastId, height: el.scrollHeight };
  });
}
