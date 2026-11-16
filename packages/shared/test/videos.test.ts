import { describe, expect, it } from "vitest";
import { createVideoRequestSchema, editVideoRequestSchema, formatVideoBytes, saveVideoFolderRequestSchema, videoFileFormat, youtubeIdFrom } from "../src/videos.js";

const id = "dQw4w9WgXcQ";

describe("youtubeIdFrom (TeamVideo.youtubeIdFrom)", () => {
  it("reads every kind of YouTube link", () => {
    for (const link of [
      id,
      ` ${id} `,
      `https://www.youtube.com/watch?v=${id}`,
      `https://youtube.com/watch?feature=share&v=${id}&t=10`,
      `youtube.com/watch?v=${id}`,
      `http://m.youtube.com/watch?v=${id}`,
      `https://music.youtube.com/watch?v=${id}`,
      `https://youtu.be/${id}?si=abc`,
      `https://www.youtube.com/shorts/${id}`,
      `https://www.youtube.com/live/${id}`,
      `https://www.youtube.com/embed/${id}`,
      `https://www.youtube-nocookie.com/embed/${id}`,
      `https://www.youtube.com/v/${id}`,
    ]) {
      expect(youtubeIdFrom(link), link).toBe(id);
    }
  });

  it("refuses everything else", () => {
    for (const link of [
      "",
      "hello",
      `https://vimeo.com/${id}`,
      `https://evil.com/watch?v=${id}`,
      `ftp://youtube.com/watch?v=${id}`,
      "https://www.youtube.com/watch?v=short",
      `https://www.youtube.com/channel/${id}`,
      "https://youtu.be/",
    ]) {
      expect(youtubeIdFrom(link), link).toBeNull();
    }
  });
});

describe("video requests", () => {
  it("trim titles and descriptions and hold the rules' limits", () => {
    expect(createVideoRequestSchema.parse({ youtubeId: id, title: "  Film  ", description: " x " })).toEqual({ youtubeId: id, folderId: "", title: "Film", description: "x" });
    expect(createVideoRequestSchema.safeParse({ youtubeId: id, title: "   " }).success).toBe(false);
    expect(createVideoRequestSchema.safeParse({ youtubeId: id, title: "a".repeat(101) }).success).toBe(false);
    expect(createVideoRequestSchema.safeParse({ youtubeId: id, title: "a", description: "a".repeat(2001) }).success).toBe(false);
    expect(createVideoRequestSchema.safeParse({ youtubeId: `https://youtu.be/${id}`, title: "a" }).success).toBe(false);
    expect(createVideoRequestSchema.safeParse({ youtubeId: id, title: "a", file: {} }).success).toBe(false);
    expect(editVideoRequestSchema.safeParse({}).success).toBe(false);
    expect(editVideoRequestSchema.safeParse({ folderId: "" }).success).toBe(true);
    expect(saveVideoFolderRequestSchema.safeParse({ name: "a".repeat(41) }).success).toBe(false);
  });

  it("format sizes and file kinds like the app", () => {
    expect(formatVideoBytes(340 * 1024 * 1024)).toBe("340 MB");
    expect(formatVideoBytes(1.25 * 1024 * 1024 * 1024)).toBe("1.3 GB");
    expect(videoFileFormat("game.mkv")).toBe("MKV");
    expect(videoFileFormat("game")).toBe("Video");
  });
});
