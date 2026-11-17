// Post privacy (security review S1): every person's post carries
// `private`, its author's profile's `private` when it was posted, and the
// rules let only the author and accepted followers read a private one
// (canSeePost in firestore.rules). These keep the flag in step.

import type { Data } from "../notifications/model";

/** Whether a profile is private (profiles/{uid}.private). */
export const isPrivateProfile = (profile: Data | undefined): boolean => profile?.private === true;

/**
 * The profile's privacy after a write to it, when it changed: what to stamp
 * on its posts. Null when it didn't change, or the profile was deleted
 * (its posts go with the account).
 */
export function privacyChange(before: Data | undefined, after: Data | undefined): boolean | null {
  if (!after) return null;
  const now = isPrivateProfile(after);
  return now === isPrivateProfile(before) ? null : now;
}

/**
 * What a new post needs stamped: `private` from its author's profile, when
 * the writer (an app before 0.0.29) left it out. Null when it's right.
 */
export function stampFor(post: Data | undefined, profile: Data | undefined): boolean | null {
  if (!post || typeof post.authorId !== "string") return null;
  const want = isPrivateProfile(profile);
  return post.private === want ? null : want;
}
