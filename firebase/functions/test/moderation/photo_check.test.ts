// The photo backstop: which objects it looks at, and that its copy of the
// SafeSearch policy matches packages/shared's.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { needsCheck, thumbOf } from "../../src/moderation/photo_check";

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
