// The photo checks' backstop for app builds that upload straight to
// Storage (the API checks every photo it saves, and marks it
// `stall10Checked`). Each other new image gets Cloud Vision SafeSearch; one
// it refuses (safe_search.ts) is deleted with its thumbnail, so it stops
// showing wherever it was posted. Exported in the `api` group.

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

async function safeSearch(bucket: string, path: string): Promise<SafeSearch | null> {
  const token = (await getApp().options.credential!.getAccessToken()).access_token;
  const res = await fetch("https://vision.googleapis.com/v1/images:annotate", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
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

export const photoCheck = onObjectFinalized({ memory: "256MiB" }, async (e) => {
  const { bucket, name, contentType, metadata } = e.data;
  if (!name || !needsCheck(name, contentType, metadata)) return;
  let s: SafeSearch | null;
  try {
    s = await safeSearch(bucket, name);
  } catch (err) {
    // Let it stay: an outage shouldn't delete photos.
    logger.error("SafeSearch failed; photo kept", { path: name, error: String(err) });
    return;
  }
  if (!isUnsafeImage(s)) return;
  logger.warn("Photo removed by SafeSearch", { path: name, safeSearch: s });
  const files = getStorage().bucket(bucket);
  await Promise.all([name, thumbOf(name)].map((p) => files.file(p).delete({ ignoreNotFound: true })));
});
