// Which profile picture URLs the API will copy into a profile (account gate
// review, F5). A signed-in client can set its own Firebase Auth `photoURL`
// to anything, and the API copies the Auth record's photo into
// `profiles/{uid}` and onto posts with Admin access, past the rules, so an
// address someone controls (a tracking pixel) would be shown to everyone who
// opens the profile. Only this app's own Storage download URL for the
// person's own `users/{uid}/profile/` folder, or the Google account photo
// that sign-in copies, is trusted; anything else is treated as no picture.

/**
 * The URL as the parser writes it (what a browser would fetch), so a value
 * with stripped whitespace or odd escapes is never passed on as typed; null
 * when it doesn't parse.
 */
function normal(url: string): string | null {
  try {
    return new URL(url).href;
  } catch {
    return null;
  }
}

/** A file name that smuggles in a folder or a traversal. */
const unsafeName = /[/\\]|%2f|%5c|%2e%2e|^\.|[^A-Za-z0-9._%-]/i;

/** Google account photos, as Firebase copies them at sign-in. */
const googlePhotoHost = "https://lh3.googleusercontent.com/";

/**
 * [url] when it is a picture the API trusts for [uid]: [buckets] are the
 * Storage buckets this deployment serves (`<project>.firebasestorage.app`,
 * `<project>.appspot.com`, STORAGE_BUCKET); [emulatorHost] the Storage
 * emulator (host:port) when running against it. Otherwise null.
 */
export function trustedPhotoUrl(url: string | null | undefined, uid: string, buckets: readonly string[], emulatorHost?: string): string | null {
  if (!url || url.length > 2000) return null;
  if (url.startsWith(googlePhotoHost)) return normal(url);
  const hosts = ["https://firebasestorage.googleapis.com", ...(emulatorHost ? [`http://${emulatorHost}`] : [])];
  const own = `users%2F${encodeURIComponent(uid)}%2Fprofile%2F`;
  for (const host of hosts) {
    for (const bucket of buckets) {
      const prefix = `${host}/v0/b/${bucket}/o/${own}`;
      if (!url.startsWith(prefix)) continue;
      // What follows is one file name (no further folders), with an optional query.
      const rest = url.slice(prefix.length).split("?")[0]!;
      if (rest.length > 0 && !unsafeName.test(rest)) return normal(url);
    }
  }
  return null;
}

// The deployment's trusted buckets, set once at startup (server.ts) so every
// service that copies a picture out of `profiles/{uid}` (account gate
// re-check, N2) judges it the same way as the Auth photoURL. Until it is
// set, only Google account photos are trusted.
let configuredBuckets: readonly string[] = [];
let configuredEmulatorHost: string | undefined;

export function configurePhotoTrust(buckets: readonly string[], emulatorHost?: string): void {
  configuredBuckets = buckets;
  configuredEmulatorHost = emulatorHost;
}

/**
 * A picture read from `profiles/{uid}` (a document a client can write, in
 * old data or past a rules gap), passed on only when trusted for [uid];
 * anything else is null. Never migrated, just not shown.
 */
export function trustedProfilePhoto(url: unknown, uid: string): string | null {
  return typeof url === "string" ? trustedPhotoUrl(url, uid, configuredBuckets, configuredEmulatorHost) : null;
}
