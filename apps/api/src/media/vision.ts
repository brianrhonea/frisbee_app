// Cloud Vision SafeSearch for uploaded photos (packages/shared safe_search.ts
// decides what's refused). Called with the API's own identity (Cloud Run's
// service account, or Application Default Credentials locally with
// GOOGLE_CLOUD_QUOTA_PROJECT); the Vision API must be on in the project.

import type { SafeSearch } from "@stall10/shared";

/** Looks at a photo: SafeSearch's answer, or null when it couldn't tell. */
export interface ImageChecker {
  safeSearch(image: Buffer): Promise<SafeSearch | null>;
}

/** An OAuth access token for Google APIs. */
export type AccessToken = () => Promise<string>;

export class VisionImageChecker implements ImageChecker {
  constructor(
    private readonly token: AccessToken,
    private readonly opts: { quotaProject?: string; fetch?: typeof fetch } = {},
  ) {}

  async safeSearch(image: Buffer): Promise<SafeSearch | null> {
    const res = await (this.opts.fetch ?? fetch)("https://vision.googleapis.com/v1/images:annotate", {
      method: "POST",
      headers: {
        authorization: `Bearer ${await this.token()}`,
        "content-type": "application/json",
        ...(this.opts.quotaProject && { "x-goog-user-project": this.opts.quotaProject }),
      },
      body: JSON.stringify({
        requests: [{ image: { content: image.toString("base64") }, features: [{ type: "SAFE_SEARCH_DETECTION" }] }],
      }),
    });
    if (!res.ok) throw new Error(`Vision ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const body = (await res.json()) as { responses?: Array<{ safeSearchAnnotation?: SafeSearch; error?: { message?: string } }> };
    const r = body.responses?.[0];
    if (r?.error) throw new Error(`Vision: ${r.error.message ?? "error"}`);
    return r?.safeSearchAnnotation ?? null;
  }
}
