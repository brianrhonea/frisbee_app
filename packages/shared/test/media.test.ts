import { describe, expect, it } from "vitest";
import { createUploadRequestSchema, mediaTypeFor } from "../src/index.js";

const MB = 1024 * 1024;

describe("mediaTypeFor", () => {
  it.each([
    ["photo.PNG", "image/png"],
    ["photo.jpg", "image/jpeg"],
    ["photo.jpeg", "image/jpeg"],
    ["clip.mp4", "video/mp4"],
    ["game.MKV", "video/x-matroska"],
    ["photo.heic", null],
    ["clip.mov", null],
    ["noext", null],
  ])("%s → %s", (name, type) => {
    expect(mediaTypeFor(name)).toBe(type);
  });
});

describe("createUploadRequestSchema", () => {
  const ok = (body: object) => createUploadRequestSchema.safeParse(body);

  it("accepts the native types within limits", () => {
    expect(ok({ purpose: "post", contentType: "image/png", size: 5 * MB }).success).toBe(true);
    expect(ok({ purpose: "teamVideo", contentType: "video/x-matroska", size: 400 * MB, targetId: "t1" }).success).toBe(true);
  });

  it("refuses other types", () => {
    expect(ok({ purpose: "post", contentType: "image/heic", size: 1 }).success).toBe(false);
    expect(ok({ purpose: "post", contentType: "video/quicktime", size: 1 }).success).toBe(false);
  });

  it("refuses files over the purpose's limit", () => {
    const r = ok({ purpose: "chat", contentType: "video/mp4", size: 101 * MB });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0].message).toBe("That file is too big. The most is 100 MB.");
    expect(ok({ purpose: "teamVideo", contentType: "video/mp4", size: 501 * MB }).success).toBe(false);
  });

  it("refuses video where only images go", () => {
    const r = ok({ purpose: "avatar", contentType: "video/mp4", size: MB });
    expect(r.error?.issues[0].message).toBe("Videos can't be uploaded here.");
  });
});
