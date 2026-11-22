import { describe, expect, it } from "vitest";
import {
  createVideoRequestSchema,
  editVideoRequestSchema,
  formatVideoBytes,
  formatVideoTime,
  isVideoNote,
  saveVideoFolderRequestSchema,
  splitVideoComments,
  tagVideoEventRequestSchema,
  videoCommentRequestSchema,
  videoFileFormat,
  videoNoteTime,
  youtubeIdFrom,
} from "../src/videos.js";

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

describe("notes, clips and comments (F4, F5)", () => {
  it("takes a comment, a note at a time, or a clip with an end after its start", () => {
    expect(videoCommentRequestSchema.parse({ body: "  Nice huck " })).toEqual({ body: "Nice huck" });
    expect(videoCommentRequestSchema.parse({ body: "Mark", atMs: 83_000 })).toEqual({ body: "Mark", atMs: 83_000 });
    expect(videoCommentRequestSchema.parse({ body: "Zone", atMs: 1000, endMs: 9000 }).endMs).toBe(9000);
    expect(videoCommentRequestSchema.safeParse({ body: "   " }).success).toBe(false);
    expect(videoCommentRequestSchema.safeParse({ body: "x".repeat(1001) }).success).toBe(false);
    expect(videoCommentRequestSchema.safeParse({ body: "x", atMs: -1 }).success).toBe(false);
    expect(videoCommentRequestSchema.safeParse({ body: "x", atMs: 1.5 }).success).toBe(false);
    expect(videoCommentRequestSchema.safeParse({ body: "x", atMs: 24 * 3600 * 1000 + 1 }).success).toBe(false);
    expect(videoCommentRequestSchema.safeParse({ body: "x", endMs: 5 }).success).toBe(false);
    expect(videoCommentRequestSchema.safeParse({ body: "x", atMs: 5, endMs: 5 }).success).toBe(false);
    expect(videoCommentRequestSchema.safeParse({ body: "x", authorId: "me" }).success).toBe(false);
  });

  it("tags an event, or untags with null", () => {
    expect(tagVideoEventRequestSchema.parse({ eventId: "e1" })).toEqual({ eventId: "e1" });
    expect(tagVideoEventRequestSchema.parse({ eventId: null })).toEqual({ eventId: null });
    expect(tagVideoEventRequestSchema.safeParse({ eventId: "" }).success).toBe(false);
    expect(tagVideoEventRequestSchema.safeParse({}).success).toBe(false);
  });

  it("formats times as the app does", () => {
    expect(formatVideoTime(0)).toBe("0:00");
    expect(formatVideoTime(7_900)).toBe("0:07");
    expect(formatVideoTime(83_000)).toBe("1:23");
    expect(formatVideoTime(3_723_000)).toBe("1:02:03");
    expect(videoNoteTime({ atMs: 83_000 })).toBe("1:23");
    expect(videoNoteTime({ atMs: 83_000, endMs: 100_000 })).toBe("1:23–1:40");
  });

  it("lists notes by time and comments oldest first", () => {
    const all = [
      { id: "c2", body: "b", createdAt: "2026-11-02T00:00:00Z" },
      { id: "n2", body: "late", atMs: 9000, createdAt: "2026-11-01T00:00:00Z" },
      { id: "c1", body: "a", createdAt: "2026-11-01T00:00:00Z" },
      { id: "n1", body: "early", atMs: 1000, createdAt: "2026-11-03T00:00:00Z" },
      { id: "c3", body: "unsaved" },
    ];
    const { notes, comments } = splitVideoComments(all);
    expect(notes.map((c) => c.id)).toEqual(["n1", "n2"]);
    expect(comments.map((c) => c.id)).toEqual(["c1", "c2", "c3"]);
    expect(isVideoNote({ atMs: 0 })).toBe(true);
  });
});
