// Which profile picture URLs the functions pass on when they copy a photo out
// of `profiles/{uid}` (a document a client can write, so it can hold any
// address). The same rule as apps/api/src/media/photo_url.ts: only this
// app's own Storage download URL for the person's own `users/{uid}/profile/`
// folder, or the Google account photo (lh3) that sign-in copies, is
// trusted; anything else is treated as no picture. Never migrated, just not
// shown or copied.

const unsafeName = /[/\\]|%2f|%5c|%2e%2e|^\.|[^A-Za-z0-9._%-]/i;
const googlePhotoHost = "https://lh3.googleusercontent.com/";

/** The deployment's Storage buckets: the project's two defaults and the one in FIREBASE_CONFIG. */
export function projectBuckets(env: NodeJS.ProcessEnv = process.env): string[] {
  const project = env.GCLOUD_PROJECT;
  let configured: string | undefined;
  try {
    configured = (JSON.parse(env.FIREBASE_CONFIG ?? "{}") as { storageBucket?: string }).storageBucket;
  } catch {
    configured = undefined;
  }
  return [...new Set([configured, project && `${project}.firebasestorage.app`, project && `${project}.appspot.com`].filter((b): b is string => !!b))];
}

/** [url] when it is a picture trusted for [uid] (see the file comment), else null. */
export function trustedPhotoUrl(url: string | null | undefined, uid: string, buckets: readonly string[], emulatorHost?: string): string | null {
  if (!url || url.length > 2000) return null;
  if (url.startsWith(googlePhotoHost)) return url;
  const hosts = ["https://firebasestorage.googleapis.com", ...(emulatorHost ? [`http://${emulatorHost}`] : [])];
  const own = `users%2F${encodeURIComponent(uid)}%2Fprofile%2F`;
  for (const host of hosts) {
    for (const bucket of buckets) {
      const prefix = `${host}/v0/b/${bucket}/o/${own}`;
      if (!url.startsWith(prefix)) continue;
      const rest = url.slice(prefix.length).split("?")[0]!;
      if (rest.length > 0 && !unsafeName.test(rest)) return url;
    }
  }
  return null;
}

/** A picture read from `profiles/{uid}`, passed on only when trusted for [uid]; otherwise null. */
export function trustedProfilePhoto(url: unknown, uid: string): string | null {
  return typeof url === "string" ? trustedPhotoUrl(url, uid, projectBuckets(), process.env.FIREBASE_STORAGE_EMULATOR_HOST) : null;
}
