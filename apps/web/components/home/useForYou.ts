"use client";
// The home feed's "For you" tab, gathered as the app's HomeFeed does
// (apps/mobile/lib/ui/posts/view_models/home_feed.dart): players' posts
// come a page at a time from /v1/me/home (the caller's and followed
// people's, tagged with followed tournaments, events shared from their
// teams; the API keeps the privacy filter), and team posts are live
// Firestore listeners, as the rules allow: every post of the member's
// teams, public posts of followed teams they're not on, and news of
// followed tournaments whose host they're not on. Each source keeps its
// newest page live; "Older posts" fetches the next page of the sources
// holding the feed back. Below the newest of the sources' oldest loaded
// posts a source might be missing posts, so the feed stops there.
import type { PublicPost } from "@stall10/shared";
import {
  collection,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
  type QueryConstraint,
  startAfter,
  Timestamp,
  where,
} from "firebase/firestore";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { TeamPostView } from "@/components/team/TeamPostCard";
import { firestoreDb } from "@/lib/firebase";
import { type Doc, plain, useLiveQuery } from "@/lib/live";

const feedPageSize = 20;

type FeedItem =
  | { kind: "user"; id: string; createdAt: string | undefined; post: PublicPost }
  | { kind: "team"; id: string; createdAt: string | undefined; teamId: string; teamName: string; member: boolean; post: Doc<TeamPostView> };

interface FollowDoc {
  type?: string;
  key?: string;
  targetId?: string;
  groupId?: string;
  name?: string;
}

/** A team-post source: a path, its filters, whether it pages, and how to label it. */
interface TeamSource {
  key: string;
  teamId: string;
  teamName: string;
  member: boolean;
  constraints: QueryConstraint[];
  /** Few posts per tournament: the whole set is live, nothing to page. */
  pages: boolean;
}

interface SourceState {
  live: Doc<TeamPostView>[] | undefined;
  older: Doc<TeamPostView>[];
  fetchedAll: boolean;
}

/** Newest first; unsaved timestamps (pending writes) count as now. */
const at = (iso: string | undefined) => (iso ? Date.parse(iso) : Number.POSITIVE_INFINITY);

/** The newest follows the feed reads (each followed team is a listener). */
const followsCap = 500;

/** The players' posts page source: what /v1/me/home returned so far. */
export interface UserPages {
  posts: PublicPost[];
  /** Cursor for the next page; null when there are no more. */
  next: number | null;
  loadMore: () => Promise<void>;
}

export function useForYou(uid: string | undefined, myTeams: Array<{ id: string; name?: string }> | undefined, users: UserPages) {
  // The newest follows (one listener each for teams): bounded like the app's feed sources should be.
  const follows = useLiveQuery<FollowDoc>(uid ? `users/${uid}/follows` : null, [orderBy("createdAt", "desc"), limit(followsCap)], uid ?? "");
  const mine = useMemo(() => new Map((myTeams ?? []).map((t) => [t.id, t.name ?? "Team"])), [myTeams]);

  // The sources wanted now, by key (HomeFeed._sync).
  const sources = useMemo<TeamSource[]>(() => {
    const out: TeamSource[] = [];
    for (const [id, name] of mine) {
      out.push({ key: `team:${id}`, teamId: id, teamName: name, member: true, constraints: [orderBy("createdAt", "desc")], pages: true });
    }
    for (const f of follows.data ?? []) {
      if (f.type === "team" && f.targetId && !mine.has(f.targetId)) {
        out.push({
          key: `public:${f.targetId}`,
          teamId: f.targetId,
          teamName: f.name ?? "Team",
          member: false,
          constraints: [where("public", "==", true), orderBy("createdAt", "desc")],
          pages: true,
        });
      }
      const key = f.key ?? f.id;
      if (f.type === "tournament" && f.groupId && !mine.has(f.groupId) && key.startsWith("tournament_")) {
        out.push({
          key: `tournament:${key}`,
          teamId: f.groupId,
          teamName: f.name ?? "Tournament",
          member: false,
          constraints: [where("public", "==", true), where("tournamentKey", "==", key)],
          pages: false,
        });
      }
    }
    return out;
  }, [mine, follows.data]);
  const sourceKey = sources.map((s) => s.key).join("|");

  const [state, setState] = useState<Record<string, SourceState>>({});
  const sourcesRef = useRef(sources);
  sourcesRef.current = sources;

  // One listener per source, added and dropped as follows and teams change.
  useEffect(() => {
    const db = firestoreDb();
    if (!db) return;
    const stops = sourcesRef.current.map((s) =>
      onSnapshot(
        query(collection(db, `teams/${s.teamId}/posts`), ...s.constraints, ...(s.pages ? [limit(feedPageSize)] : [])),
        (snap) => {
          const next = snap.docs.map((d) => ({ ...(plain(d.data()) as TeamPostView), id: d.id }) as Doc<TeamPostView>);
          setState((all) => {
            const prev = all[s.key] ?? { live: undefined, older: [], fetchedAll: false };
            // A new post pushes the oldest out of a full live page: keep it.
            const older = new Map(prev.older.map((p) => [p.id, p]));
            if (prev.live && next.length >= feedPageSize) {
              const ids = new Set(next.map((p) => p.id));
              const newest = Math.min(...next.map((p) => at(p.createdAt)));
              for (const p of prev.live) if (!ids.has(p.id) && at(p.createdAt) < newest) older.set(p.id, p);
            }
            for (const p of next) older.delete(p.id);
            return { ...all, [s.key]: { live: next, older: [...older.values()], fetchedAll: prev.fetchedAll } };
          });
        },
        () => setState((all) => ({ ...all, [s.key]: { live: [], older: [], fetchedAll: true } })),
      ),
    );
    return () => {
      stops.forEach((stop) => stop());
      setState((all) => Object.fromEntries(Object.entries(all).filter(([k]) => sourcesRef.current.some((s) => s.key === k))));
    };
  }, [sourceKey]);

  const exhausted = useCallback(
    (s: TeamSource) => {
      const st = state[s.key];
      return !st?.live || !s.pages || st.fetchedAll || (st.older.length === 0 && st.live.length < feedPageSize);
    },
    [state],
  );
  const oldestOf = (posts: Array<{ createdAt?: string }>) => {
    let oldest: number | null = null;
    for (const p of posts) {
      const t = at(p.createdAt);
      if (Number.isFinite(t) && (oldest === null || t < oldest)) oldest = t;
    }
    return oldest;
  };
  // The API filters a page after setting its cursor, so the cursor is how far it has read.
  const usersOldest = users.next;

  const cutoff = useMemo(() => {
    let c: number | null = usersOldest;
    for (const s of sources) {
      if (exhausted(s)) continue;
      const st = state[s.key]!;
      const o = oldestOf([...st.older, ...(st.live ?? [])]);
      if (o !== null && (c === null || o > c)) c = o;
    }
    return c;
  }, [sources, state, exhausted, usersOldest]);

  const items = useMemo<FeedItem[]>(() => {
    const byId = new Map<string, FeedItem>();
    for (const p of users.posts) byId.set(`u:${p.id}`, { kind: "user", id: `u:${p.id}`, createdAt: p.createdAt, post: p });
    for (const s of sources) {
      const st = state[s.key];
      if (!st) continue;
      for (const p of [...st.older, ...(st.live ?? [])]) {
        const id = `t:${s.teamId}/${p.id}`;
        // A team the member is on shows its own label over a follow's.
        if (!byId.has(id) || s.member) byId.set(id, { kind: "team", id, createdAt: p.createdAt, teamId: s.teamId, teamName: s.teamName, member: s.member, post: p });
      }
    }
    return [...byId.values()]
      .filter((i) => cutoff === null || at(i.createdAt) >= cutoff)
      .sort((a, b) => at(b.createdAt) - at(a.createdAt));
  }, [users.posts, sources, state, cutoff]);

  const [loadingMore, setLoadingMore] = useState(false);
  const hasMore = users.next !== null || sources.some((s) => !exhausted(s));
  // A follows read that failed still lets the feed show (the member's teams and the players' posts).
  const loaded = (follows.data !== undefined || !!follows.error) && myTeams !== undefined && sources.every((s) => state[s.key]?.live !== undefined);

  /**
   * Fetches the next page of the sources holding the feed back (those whose
   * oldest loaded post is the cutoff), so the cutoff moves down.
   */
  const loadMore = useCallback(async () => {
    const db = firestoreDb();
    if (loadingMore || !hasMore || !db || cutoff === null) return;
    setLoadingMore(true);
    try {
      const tasks: Promise<unknown>[] = [];
      if (usersOldest !== null && usersOldest === cutoff) tasks.push(users.loadMore());
      for (const s of sources) {
        if (exhausted(s)) continue;
        const st = state[s.key]!;
        if (oldestOf([...st.older, ...(st.live ?? [])]) !== cutoff) continue;
        tasks.push(
          getDocs(query(collection(db, `teams/${s.teamId}/posts`), ...s.constraints, startAfter(Timestamp.fromMillis(cutoff)), limit(feedPageSize))).then(
            (snap) => {
              const page = snap.docs.map((d) => ({ ...(plain(d.data()) as TeamPostView), id: d.id }) as Doc<TeamPostView>);
              setState((all) => {
                const prev = all[s.key];
                if (!prev) return all;
                // A failed or short page stops paging this source.
                return { ...all, [s.key]: { ...prev, older: [...prev.older, ...page], fetchedAll: page.length < feedPageSize } };
              });
            },
            () => setState((all) => (all[s.key] ? { ...all, [s.key]: { ...all[s.key]!, fetchedAll: true } } : all)),
          ),
        );
      }
      await Promise.all(tasks);
    } finally {
      setLoadingMore(false);
    }
  }, [loadingMore, hasMore, cutoff, usersOldest, users, sources, state, exhausted]);

  return { items, loaded, hasMore, loadingMore, loadMore, followsAnything: (follows.data ?? []).length > 0 };
}
