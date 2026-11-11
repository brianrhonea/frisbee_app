"use client";
import { type PostState, type PostStates, postStateLimit } from "@stall10/shared";
import type { User } from "firebase/auth";
import { callApi } from "./client";

// The signed-in member's likes and reposts of the posts on a page. Every
// card asks for its own post; the asks made together go to the API as one
// `GET /v1/posts/state` (up to 50 ids each), so a page of posts is one call.

type Waiter = { resolve: (s: PostState | undefined) => void; reject: (e: unknown) => void };

let queue = new Map<string, Waiter[]>();
let queuedFor: User | null = null;
let timer: ReturnType<typeof setTimeout> | null = null;

/** [user]'s state for post [id] (undefined when it's gone). */
export function postState(user: User, id: string): Promise<PostState | undefined> {
  return new Promise((resolve, reject) => {
    if (queuedFor && queuedFor.uid !== user.uid) flush();
    queuedFor = user;
    queue.set(id, [...(queue.get(id) ?? []), { resolve, reject }]);
    timer ??= setTimeout(flush, 0);
  });
}

function flush() {
  if (timer) clearTimeout(timer);
  timer = null;
  const batch = queue;
  const user = queuedFor;
  queue = new Map();
  queuedFor = null;
  if (!user || batch.size === 0) return;
  const ids = [...batch.keys()];
  for (let i = 0; i < ids.length; i += postStateLimit) {
    const chunk = ids.slice(i, i + postStateLimit);
    const settle = (fn: (w: Waiter) => void) => chunk.forEach((id) => batch.get(id)?.forEach(fn));
    callApi<PostStates>(user, `/v1/posts/state?ids=${chunk.map(encodeURIComponent).join(",")}`).then(
      (states) => chunk.forEach((id) => batch.get(id)?.forEach((w) => w.resolve(states[id]))),
      (e) => settle((w) => w.reject(e)),
    );
  }
}
