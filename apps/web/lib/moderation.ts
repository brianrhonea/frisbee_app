"use client";
import type { BlockInfo } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useEffect, useSyncExternalStore } from "react";
import { callApi } from "./client";

/**
 * Who the signed-in member blocked, and everyone hidden from them either
 * way (`GET /v1/me/blocks`), shared by every component on the page: posts,
 * comments and messages from a hidden person aren't shown, as in the app.
 */
interface BlockState {
  uid: string | null;
  blocked: BlockInfo[];
  hidden: ReadonlySet<string>;
  loaded: boolean;
}

const empty: BlockState = { uid: null, blocked: [], hidden: new Set(), loaded: false };
let state = empty;
let loading: Promise<void> | null = null;
const listeners = new Set<() => void>();

function set(next: BlockState) {
  state = next;
  for (const l of listeners) l();
}

/** Loads (or reloads) [user]'s blocks. */
export async function loadBlocks(user: User): Promise<void> {
  const r = await callApi<{ blocked: BlockInfo[]; hidden: string[] }>(user, "/v1/me/blocks");
  set({ uid: user.uid, blocked: r.blocked, hidden: new Set(r.hidden), loaded: true });
}

/** Blocks [uid]: their posts, comments and messages disappear at once. */
export async function blockPerson(user: User, uid: string): Promise<void> {
  await callApi(user, `/v1/me/blocks/${encodeURIComponent(uid)}`, { method: "PUT" });
  set({ ...state, hidden: new Set([...state.hidden, uid]) });
  await loadBlocks(user);
}

export async function unblockPerson(user: User, uid: string): Promise<void> {
  await callApi(user, `/v1/me/blocks/${encodeURIComponent(uid)}`, { method: "DELETE" });
  await loadBlocks(user);
}

/** The block list for [user] (null while signed out), loaded on first use. */
export function useBlocks(user: User | null | undefined) {
  const s = useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => state,
    () => empty,
  );
  useEffect(() => {
    if (!user) return;
    if (state.uid === user.uid && state.loaded) return;
    if (state.uid !== user.uid) set({ ...empty, uid: user.uid });
    loading ??= loadBlocks(user)
      .catch(() => undefined)
      .finally(() => {
        loading = null;
      });
  }, [user]);
  const mine = user && s.uid === user.uid ? s : empty;
  return {
    blocked: mine.blocked,
    loaded: mine.loaded,
    /** Whether [uid] is hidden from the member (they blocked them, or were blocked). */
    hides: (uid: string | null | undefined) => !!uid && mine.hidden.has(uid),
    /** Whether the member blocked [uid] themselves (they can unblock). */
    blockedByMe: (uid: string | null | undefined) => !!uid && mine.blocked.some((b) => b.uid === uid),
  };
}
