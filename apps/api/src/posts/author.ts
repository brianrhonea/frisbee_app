// Who the caller is on what they write (posts, comments, follow requests),
// and the flood mute every write checks.
import type { Caller, UserLookup } from "../auth.js";
import { ApiError } from "../errors.js";
import type { DocStore } from "../store.js";
import { tooFastMessage } from "../teams/service.js";

/** Longest author name on a post or comment (validString(authorName, 80)). */
export const nameMax = 80;
/** Longest author photo URL (validString(authorPhotoUrl, 2000)). */
export const photoMax = 2000;

export const clip = (s: string, max: number) => (s.length > max ? s.substring(0, max) : s);
export const text = (v: unknown) => (typeof v === "string" ? v.trim() : "");

export interface Author {
  name: string;
  photoUrl: string | null;
  username: string | null;
}

/**
 * The name and photo shown for [caller]: their Auth display name, else their
 * profile's name or username. Never their email (the app's AppUser.label
 * falls back to it; posts are public).
 */
export async function authorOf(store: DocStore, users: UserLookup, caller: Caller): Promise<Author> {
  const [user, profile] = await Promise.all([users.lookup(caller.uid), store.get(`profiles/${caller.uid}`)]);
  const username = text(profile?.username);
  const name = text(user?.name) || text(profile?.name) || (username ? `@${username}` : "") || "Player";
  const photo = user?.photoUrl ?? (typeof profile?.photoUrl === "string" ? profile.photoUrl : null);
  return {
    name: clip(name, nameMax),
    photoUrl: photo && photo.length <= photoMax ? photo : null,
    username: username || null,
  };
}

/** notMuted(): the flood mute the functions set on limits/{uid}. */
export async function checkNotMuted(store: DocStore, uid: string, now: number) {
  const until = (await store.get(`limits/${uid}`))?.mutedUntil;
  if (until instanceof Date && until.getTime() > now) {
    throw new ApiError("resource_exhausted", tooFastMessage(until.getTime(), now));
  }
}
