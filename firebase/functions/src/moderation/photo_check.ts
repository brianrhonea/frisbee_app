// The photo checks' backstop for app builds that upload straight to
// Storage (the API checks every photo it saves, and marks it
// `stall10Checked`). Each other new image gets Cloud Vision SafeSearch; one
// it refuses (safe_search.ts) is deleted with its thumbnail, so it stops
// showing wherever it was posted. It fails CLOSED (#14): a photo that can't
// be screened (Vision down, an error, no answer, a timeout) is deleted too,
// never left showing unchecked. Exported in the `api` group.

import { getApp } from "firebase-admin/app";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { onObjectFinalized } from "firebase-functions/v2/storage";

import { isUnsafeImage, type SafeSearch } from "./safe_search";

/** Whether the object at [path] needs a look: an image no one checked yet. */
export function needsCheck(path: string, contentType: string | undefined, metadata: Record<string, string> | undefined): boolean {
  if (!contentType?.startsWith("image/")) return false;
  if (metadata?.stall10Checked) return false;
  // The API's raw uploads are checked when they're completed; thumbnails
  // go with their photo.
  if (path.startsWith("uploads/raw/")) return false;
  return !/_thumb\.[a-z]+$/i.test(path);
}

/** The thumbnail beside a photo, as the app and the API name it. */
export const thumbOf = (path: string) => path.replace(/\.[a-z]+$/i, "_thumb.jpg");

/** Vision gets this long; the function's own limit is above it. */
export const visionTimeoutMs = 30_000;

async function safeSearch(bucket: string, path: string): Promise<SafeSearch | null> {
  const token = (await getApp().options.credential!.getAccessToken()).access_token;
  const res = await fetch("https://vision.googleapis.com/v1/images:annotate", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    signal: AbortSignal.timeout(visionTimeoutMs),
    body: JSON.stringify({
      requests: [
        { image: { source: { imageUri: `gs://${bucket}/${path}` } }, features: [{ type: "SAFE_SEARCH_DETECTION" }] },
      ],
    }),
  });
  if (!res.ok) throw new Error(`Vision ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const body = (await res.json()) as {
    responses?: Array<{ safeSearchAnnotation?: SafeSearch; error?: { message?: string } }>;
  };
  const r = body.responses?.[0];
  if (r?.error) throw new Error(`Vision: ${r.error.message ?? "error"}`);
  return r?.safeSearchAnnotation ?? null;
}

/** What [screenPhoto] did with the object. */
export type ScreenResult = "skipped" | "kept" | "removed_unsafe" | "removed_unchecked";

export interface ScreenDeps {
  /** SafeSearch's answer; throws on any failure. */
  safeSearch(bucket: string, path: string): Promise<SafeSearch | null>;
  /** Deletes the object and its thumbnail. */
  remove(bucket: string, path: string): Promise<void>;
}

/**
 * Screens one new object. Only an answer that says the photo is fine keeps
 * it: a refusal, an error, a timeout or no answer all delete it (fail closed).
 */
export async function screenPhoto(
  e: { bucket: string; name?: string; contentType?: string; metadata?: Record<string, string> },
  deps: ScreenDeps,
): Promise<ScreenResult> {
  const { bucket, name, contentType, metadata } = e;
  if (!name || !needsCheck(name, contentType, metadata)) return "skipped";
  let s: SafeSearch | null;
  try {
    s = await deps.safeSearch(bucket, name);
    if (s == null) throw new Error("SafeSearch gave no answer");
  } catch (err) {
    logger.error("SafeSearch failed; photo removed (fail closed)", { path: name, error: String(err) });
    await deps.remove(bucket, name);
    return "removed_unchecked";
  }
  if (!isUnsafeImage(s)) return "kept";
  logger.warn("Photo removed by SafeSearch", { path: name, safeSearch: s });
  await deps.remove(bucket, name);
  return "removed_unsafe";
}

const removeObject: ScreenDeps["remove"] = async (bucket, name) => {
  const files = getStorage().bucket(bucket);
  await Promise.all([name, thumbOf(name)].map((p) => files.file(p).delete({ ignoreNotFound: true })));
};

// A Storage trigger runs in its bucket's region: both projects' default
// buckets are in us-east1 (the other functions stay in us-central1).
export const photoCheck = onObjectFinalized({ memory: "256MiB", region: "us-east1", timeoutSeconds: 60 }, async (e) => {
  await screenPhoto(e.data, { safeSearch, remove: removeObject });
});
