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
    ["IMG_0001.HEIC", "image/heic"],
    ["photo.heif", "image/heif"],
    ["photo.webp", "image/webp"],
    ["anim.gif", "image/gif"],
    ["IMG_0002.MOV", "video/quicktime"],
    ["clip.m4v", "video/x-m4v"],
    ["screen.webm", "video/webm"],
    ["old.3gp", "video/3gpp"],
    ["doc.pdf", null],
    ["clip.avi", null],
    ["noext", null],
  ])("%s → %s", (name, type) => {
    expect(mediaTypeFor(name)).toBe(type);
  });
});

describe("createUploadRequestSchema", () => {
  const ok = (body: object) => createUploadRequestSchema.safeParse(body);

  it("accepts the native types within limits", () => {
    expect(ok({ purpose: "post", itemId: "i1", contentType: "image/png", size: 5 * MB }).success).toBe(true);
    expect(ok({ purpose: "teamVideo", itemId: "i1", contentType: "video/x-matroska", size: 400 * MB, targetId: "t1" }).success).toBe(true);
  });

  it("accepts iPhone photos and video", () => {
    expect(ok({ purpose: "post", itemId: "i1", contentType: "image/heic", size: MB }).success).toBe(true);
    expect(ok({ purpose: "post", itemId: "i1", contentType: "video/quicktime", size: 50 * MB }).success).toBe(true);
  });

  it("refuses other types", () => {
    expect(ok({ purpose: "post", itemId: "i1", contentType: "application/pdf", size: 1 }).success).toBe(false);
    expect(ok({ purpose: "post", itemId: "i1", contentType: "video/x-msvideo", size: 1 }).success).toBe(false);
  });

  it("needs the post, video or message (itemId) for every purpose but avatar", () => {
    const r = ok({ purpose: "post", contentType: "image/jpeg", size: MB });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0].path).toEqual(["itemId"]);
    expect(ok({ purpose: "avatar", contentType: "image/jpeg", size: MB }).success).toBe(true);
    expect(ok({ purpose: "post", itemId: "../x", contentType: "image/jpeg", size: MB }).success).toBe(false);
  });

  it("refuses files over the purpose's limit", () => {
    const r = ok({ purpose: "chat", itemId: "i1", contentType: "video/mp4", size: 101 * MB });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0].message).toBe("That file is too big. The most is 100 MB.");
    expect(ok({ purpose: "teamVideo", itemId: "i1", contentType: "video/mp4", size: 501 * MB }).success).toBe(false);
  });

  it("refuses video where only images go", () => {
    const r = ok({ purpose: "avatar", contentType: "video/mp4", size: MB });
    expect(r.error?.issues[0].message).toBe("Videos can't be uploaded here.");
  });
});
