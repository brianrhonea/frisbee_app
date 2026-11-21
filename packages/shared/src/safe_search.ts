// Photo checks: what Cloud Vision's SafeSearch says about an uploaded
// image, and which answers refuse it. The API checks each photo as it's
// uploaded; the Cloud Functions backstop (firebase/functions/src/moderation,
// a copy of this) checks photos older app builds put in Storage directly.

/** SafeSearch's likelihoods, least to most likely. */
export const safeSearchLikelihoods = ["UNKNOWN", "VERY_UNLIKELY", "UNLIKELY", "POSSIBLE", "LIKELY", "VERY_LIKELY"] as const;
export type SafeSearchLikelihood = (typeof safeSearchLikelihoods)[number];

/** Vision's `safeSearchAnnotation`. */
export interface SafeSearch {
  adult?: SafeSearchLikelihood;
  racy?: SafeSearchLikelihood;
  violence?: SafeSearchLikelihood;
  medical?: SafeSearchLikelihood;
  spoof?: SafeSearchLikelihood;
}

/**
 * The least likelihood that refuses a photo, per category. Strict on
 * nudity and sexual content; only near-certain gore (sports photos are
 * full of bare legs and collisions, so racy and violence stop at very
 * likely). Medical and spoof don't refuse.
 */
export const safeSearchRefuses: Readonly<Partial<Record<keyof SafeSearch, SafeSearchLikelihood>>> = {
  adult: "LIKELY",
  racy: "VERY_LIKELY",
  violence: "VERY_LIKELY",
};

/** What the uploader is told about a refused photo. */
export const unsafeImageMessage = "That photo can't be posted on Stall 10. See the community guidelines.";

/** Whether SafeSearch's answer [s] refuses the photo. */
export function isUnsafeImage(s: SafeSearch | null | undefined): boolean {
  if (!s) return false;
  return Object.entries(safeSearchRefuses).some(([k, min]) => {
    const got = s[k as keyof SafeSearch];
    return got != null && safeSearchLikelihoods.indexOf(got) >= safeSearchLikelihoods.indexOf(min!);
  });
}
