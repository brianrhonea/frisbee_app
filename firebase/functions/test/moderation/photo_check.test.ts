// The photo backstop: which objects it looks at, and that its copy of the
// SafeSearch policy matches packages/shared's.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";

// Declaring the Storage trigger needs a default bucket; give it a synthetic one.
vi.hoisted(() => {
  process.env.FIREBASE_CONFIG ??= JSON.stringify({ storageBucket: "demo-frisbee.appspot.com" });
});

import { needsCheck, screenPhoto, thumbOf } from "../../src/moderation/photo_check";

describe("needsCheck", () => {
  it("looks at an app-uploaded photo", () => {
    expect(needsCheck("users/u1/posts/p1/a.jpg", "image/jpeg", undefined)).toBe(true);
  });
  it.each([
    ["the API checked it", "teams/t/chat/x.jpg", "image/jpeg", { stall10Checked: "api" }],
    ["a raw upload (checked on complete)", "uploads/raw/u1/x", "image/jpeg", undefined],
    ["a thumbnail", "users/u1/posts/p1/a_thumb.jpg", "image/jpeg", undefined],
    ["a video", "teams/t/videos/v.mp4", "video/mp4", undefined],
    ["a file", "conversations/c/f.pdf", "application/pdf", undefined],
  ])("skips %s", (_, path, type, meta) => {
    expect(needsCheck(path, type, meta)).toBe(false);
  });
  it("finds the thumbnail", () => {
    expect(thumbOf("users/u1/posts/p1/a.png")).toBe("users/u1/posts/p1/a_thumb.jpg");
  });
});

describe("the SafeSearch policy", () => {
  it("is packages/shared's", () => {
    const body = (f: string) => readFileSync(f, "utf8").replace(/^[\s\S]*?(?=\/\*\* SafeSearch's likelihoods)/, "");
    expect(body(join(__dirname, "../../src/moderation/safe_search.ts"))).toBe(
      body(join(__dirname, "../../../../packages/shared/src/safe_search.ts")),
    );
  });
});

describe("screenPhoto (fails closed)", () => {
  const photo = { bucket: "b", name: "users/u1/posts/p1/a.jpg", contentType: "image/jpeg" };
  const run = (safeSearch: () => Promise<unknown>, e: Parameters<typeof screenPhoto>[0] = photo) => {
    const removed: string[] = [];
    const result = screenPhoto(e, {
      safeSearch: safeSearch as never,
      remove: async (_b, p) => void removed.push(p),
    });
    return { result, removed };
  };

  it("keeps a photo SafeSearch says is fine", async () => {
    const { result, removed } = run(async () => ({ adult: "VERY_UNLIKELY", racy: "POSSIBLE" }));
    expect(await result).toBe("kept");
    expect(removed).toEqual([]);
  });
  it("removes an unsafe photo", async () => {
    const { result, removed } = run(async () => ({ adult: "VERY_LIKELY" }));
    expect(await result).toBe("removed_unsafe");
    expect(removed).toEqual([photo.name]);
  });
  it.each([
    ["Vision errors", async () => { throw new Error("Vision 503"); }],
    ["Vision times out", async () => { throw new DOMException("timed out", "TimeoutError"); }],
    ["Vision gives no answer", async () => null],
  ])("removes the photo when %s", async (_, answer) => {
    const { result, removed } = run(answer);
    expect(await result).toBe("removed_unchecked");
    expect(removed).toEqual([photo.name]);
  });
  it("leaves alone what it doesn't check (the API's photos, thumbnails, videos)", async () => {
    for (const e of [
      { ...photo, metadata: { stall10Checked: "api" } },
      { ...photo, name: "users/u1/posts/p1/a_thumb.jpg" },
      { ...photo, name: "teams/t/videos/v/a.mp4", contentType: "video/mp4" },
      { ...photo, name: undefined },
    ]) {
      const { result, removed } = run(async () => { throw new Error("must not be called"); }, e);
      expect(await result).toBe("skipped");
      expect(removed).toEqual([]);
    }
  });
});
