// Which profile picture URLs the API will copy into a profile (account gate
// review, F5). A signed-in client can set its own Firebase Auth `photoURL`
// to anything, and the API copies the Auth record's photo into
// `profiles/{uid}` and onto posts with Admin access, past the rules, so an
// address someone controls (a tracking pixel) would be shown to everyone who
// opens the profile. Only this app's own Storage download URL for the
// person's own `users/{uid}/profile/` folder, or the Google account photo
// that sign-in copies, is trusted; anything else is treated as no picture.

/** A file name that smuggles in a folder or a traversal. */
const unsafeName = /[/\\]|%2f|%5c|%2e%2e/i;

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
  if (url.startsWith(googlePhotoHost)) return url;
  const hosts = ["https://firebasestorage.googleapis.com", ...(emulatorHost ? [`http://${emulatorHost}`] : [])];
  const own = `users%2F${encodeURIComponent(uid)}%2Fprofile%2F`;
  for (const host of hosts) {
    for (const bucket of buckets) {
      const prefix = `${host}/v0/b/${bucket}/o/${own}`;
      if (!url.startsWith(prefix)) continue;
      // What follows is one file name (no further folders), with an optional query.
      const rest = url.slice(prefix.length).split("?")[0]!;
      if (rest.length > 0 && !unsafeName.test(rest)) return url;
    }
  }
  return null;
}
