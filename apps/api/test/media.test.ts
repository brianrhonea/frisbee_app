// Media: type sniffing, image compression (sharp), the transcode module
// (ffmpeg arguments, the status machine, the job runner with a fake
// ffmpeg), and the upload endpoints against fakes.
import { writeFile } from "node:fs/promises";
import { acceptedImageTypes, acceptedVideoTypes, mediaStandard } from "@stall10/shared";
import sharp from "sharp";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { compressImage, UnreadableImage } from "../src/media/image.js";
import { sniffMediaType } from "../src/media/sniff.js";
import { nextStatus, posterArgs, runTranscodeJob, transcodeArgs } from "../src/media/transcode.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const bytes = (...parts: Array<string | number[]>) =>
  Buffer.concat(parts.map((p) => (typeof p === "string" ? Buffer.from(p, "latin1") : Buffer.from(p))));
/** An ISO-BMFF ftyp box with [major] and [compatible] brands. */
const ftyp = (major: string, ...compatible: string[]) => {
  const body = bytes("ftyp", major.padEnd(4), [0, 0, 0, 0], ...compatible.map((c) => c.padEnd(4)));
  return Buffer.concat([Buffer.from([0, 0, 0, body.length + 4]), body, Buffer.alloc(32)]);
};

const samples: Record<string, Buffer> = {
  "image/jpeg": bytes([0xff, 0xd8, 0xff, 0xe0], "\0\x10JFIF"),
  "image/png": bytes([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  "image/heic": ftyp("heic", "mif1", "heic"),
  "image/heif": ftyp("mif1", "mif1", "avif"),
  "image/webp": bytes("RIFF", [0, 0, 0, 0], "WEBPVP8 "),
  "image/gif": bytes("GIF89a"),
  "video/mp4": ftyp("isom", "isom", "avc1"),
  "video/quicktime": ftyp("qt", "qt"),
  "video/x-m4v": ftyp("M4V", "M4V", "mp42"),
  "video/x-matroska": bytes([0x1a, 0x45, 0xdf, 0xa3], "\x9fB\x82\x88matroska"),
  "video/webm": bytes([0x1a, 0x45, 0xdf, 0xa3], "\x9fB\x82\x84webm"),
  "video/3gpp": ftyp("3gp4", "3gp4", "isom"),
};

describe("sniffMediaType", () => {
  it("covers every accepted type", () => {
    expect(Object.keys(samples).sort()).toEqual([...acceptedImageTypes, ...acceptedVideoTypes].sort());
  });

  it.each(Object.entries(samples))("knows %s by its bytes", (type, data) => {
    expect(sniffMediaType(data)).toBe(type);
  });

  it("knows an iPhone HEIC whose major brand is mif1", () => {
    expect(sniffMediaType(ftyp("mif1", "mif1", "heic"))).toBe("image/heic");
  });

  it.each([
    ["text", bytes("hello world, not media")],
    ["a PDF", bytes("%PDF-1.7")],
    ["an M4A (audio only)", ftyp("M4A", "M4A", "mp42")],
    ["nothing", Buffer.alloc(0)],
  ])("refuses %s", (_, data) => {
    expect(sniffMediaType(data)).toBeNull();
  });
});

describe("compressImage", () => {
  const solid = (w: number, h: number) => sharp({ create: { width: w, height: h, channels: 3, background: "#3366cc" } });

  it("shrinks to 1920 px as JPEG, with a 480 px thumbnail, and drops metadata", async () => {
    const input = await solid(4000, 3000).jpeg().withMetadata({ exif: { IFD0: { Copyright: "secret" } } }).toBuffer();
    expect((await sharp(input).metadata()).exif).toBeDefined();
    const { image, thumb } = await compressImage(input, "image/jpeg");
    expect(image).toMatchObject({ contentType: "image/jpeg", width: 1920, height: 1440 });
    const meta = await sharp(image.data).metadata();
    expect(meta.format).toBe("jpeg");
    expect(meta.exif).toBeUndefined();
    expect(thumb).toMatchObject({ contentType: "image/jpeg", width: 480, height: 360 });
  });

  it("turns it upright from EXIF orientation", async () => {
    // 200×100 stored, orientation 6 (rotate 90°): shows as 100×200.
    const input = await solid(200, 100).jpeg().withMetadata({ orientation: 6 }).toBuffer();
    const { image } = await compressImage(input, "image/jpeg");
    expect([image.width, image.height]).toEqual([100, 200]);
  });

  it("never enlarges a small image", async () => {
    const { image } = await compressImage(await solid(300, 200).png().toBuffer(), "image/png");
    expect([image.width, image.height]).toEqual([300, 200]);
  });

  it("keeps real transparency as PNG; an opaque PNG becomes JPEG", async () => {
    const clear = await sharp({ create: { width: 50, height: 50, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .png()
      .toBuffer();
    expect((await compressImage(clear, "image/png")).image.contentType).toBe("image/png");
    const opaqueWithAlpha = await sharp({ create: { width: 50, height: 50, channels: 4, background: { r: 9, g: 9, b: 9, alpha: 1 } } })
      .png()
      .toBuffer();
    expect((await compressImage(opaqueWithAlpha, "image/png")).image.contentType).toBe("image/jpeg");
  });

  it("reads WebP and GIF", async () => {
    expect((await compressImage(await solid(64, 64).webp().toBuffer(), "image/webp")).image.contentType).toBe("image/jpeg");
    const gif = await compressImage(await solid(64, 32).gif().toBuffer(), "image/gif");
    expect([gif.image.width, gif.image.height]).toEqual([64, 32]);
  });

  it("needs a decoder for HEIC that sharp can't read, and uses it", async () => {
    const heic = samples["image/heic"];
    await expect(compressImage(heic, "image/heic")).rejects.toBeInstanceOf(UnreadableImage);
    const png = await solid(100, 80).png().toBuffer();
    const { image } = await compressImage(heic, "image/heic", { heic: { toPng: async () => png } });
    expect([image.contentType, image.width, image.height]).toEqual(["image/jpeg", 100, 80]);
  });

  it("refuses bytes that aren't an image", async () => {
    await expect(compressImage(Buffer.from("nope"), "image/jpeg")).rejects.toBeInstanceOf(UnreadableImage);
  });
});

describe("transcode module", () => {
  it("builds ffmpeg arguments for the standard MP4", () => {
    const args = transcodeArgs("in.mov", "out.mp4");
    const after = (flag: string) => args[args.indexOf(flag) + 1];
    expect(args.slice(-1)).toEqual(["out.mp4"]);
    expect(after("-i")).toBe("in.mov");
    expect(after("-c:v")).toBe("libx264");
    expect(after("-profile:v")).toBe("high");
    expect(after("-crf")).toBe("23");
    expect(after("-maxrate")).toBe("5000k");
    expect(after("-fpsmax")).toBe("30");
    expect(after("-c:a")).toBe("aac");
    expect(after("-b:a")).toBe("128k");
    expect(after("-movflags")).toBe("+faststart");
    expect(after("-map_metadata")).toBe("-1");
    expect(after("-vf")).toContain("min(1920,iw)");
    expect(after("-vf")).toContain("force_divisible_by=2");
    expect(after("-vf")).toContain("format=yuv420p");
    // Silent videos stay valid: the audio stream is optional.
    expect(args).toContain("0:a:0?");
    expect(mediaStandard.video).toMatchObject({ crf: 23, maxFps: 30, maxVideoBitrateKbps: 5000 });
  });

  it("builds the poster's arguments", () => {
    const args = posterArgs("in.mp4", "p.jpg");
    expect(args).toEqual(expect.arrayContaining(["-frames:v", "1", "p.jpg"]));
    expect(args[args.indexOf("-vf") + 1]).toContain("min(480,iw)");
  });

  it("moves through the upload statuses", () => {
    expect(nextStatus("pending", "image_saved")).toBe("ready");
    expect(nextStatus("pending", "video_queued")).toBe("processing");
    expect(nextStatus("pending", "rejected")).toBe("failed");
    expect(nextStatus("processing", "transcoded")).toBe("ready");
    expect(nextStatus("processing", "failed")).toBe("failed");
    expect(() => nextStatus("ready", "transcoded")).toThrow();
    expect(() => nextStatus("pending", "transcoded")).toThrow();
    expect(() => nextStatus("failed", "image_saved")).toThrow();
  });

  describe("runTranscodeJob", () => {
    const job = { uploadId: "up1", input: "uploads/raw/u1/up1", output: "media/u1/up1.mp4", poster: "media/u1/up1_poster.jpg" };
    let store: FakeStore;
    let storage: FakeMediaStorage;
    beforeEach(() => {
      store = new FakeStore();
      storage = new FakeMediaStorage();
      store.put("uploads/up1", { uid: "u1", status: "processing" });
      store.put("transcodeJobs/up1", { status: "queued" });
      storage.files.set(job.input, { data: Buffer.from("raw video") });
    });
    /** Writes each command's output file, like ffmpeg would. */
    const fakeFfmpeg = async (args: string[]) => writeFile(args[args.length - 1], `made from ${args[args.indexOf("-i") + 1]}`);

    it("saves the video and poster, deletes the raw file, marks it ready", async () => {
      expect(await runTranscodeJob(job, { store, storage, ffmpeg: fakeFfmpeg })).toBe("ready");
      expect(storage.files.get(job.output)?.contentType).toBe("video/mp4");
      expect(storage.files.get(job.poster)?.contentType).toBe("image/jpeg");
      expect(storage.files.has(job.input)).toBe(false);
      expect(store.doc("uploads/up1")).toMatchObject({ status: "ready", path: job.output, thumbPath: job.poster });
      expect(store.doc("transcodeJobs/up1")).toMatchObject({ status: "done" });
    });

    it("marks it failed with the reason when ffmpeg fails, keeping the raw file", async () => {
      const broken = async () => {
        throw new Error("Invalid data found when processing input");
      };
      expect(await runTranscodeJob(job, { store, storage, ffmpeg: broken })).toBe("failed");
      expect(store.doc("uploads/up1")).toMatchObject({ status: "failed", error: "Invalid data found when processing input" });
      expect(store.doc("transcodeJobs/up1")).toMatchObject({ status: "failed" });
    });

    it("leaves an upload that isn't processing alone (runs twice safely)", async () => {
      store.put("uploads/up1", { uid: "u1", status: "ready" });
      let ran = false;
      expect(await runTranscodeJob(job, { store, storage, ffmpeg: async () => void (ran = true) })).toBe("ready");
      expect(ran).toBe(false);
    });
  });
});

describe("uploads API", () => {
  const now = Date.UTC(2026, 10, 11, 12);
  let store: FakeStore;
  let storage: FakeMediaStorage;
  let queued: string[];
  let app: ReturnType<typeof buildApp>;
  const call = (url: string, body: object = {}, uid = "u1") =>
    app.inject({ method: "POST", url, payload: body, headers: { authorization: `Bearer token:${uid}` } });
  const jpeg = () => sharp({ create: { width: 2400, height: 1200, channels: 3, background: "#123456" } }).jpeg().toBuffer();

  beforeEach(() => {
    store = new FakeStore(() => now);
    storage = new FakeMediaStorage();
    queued = [];
    app = buildApp({
      verifier: new FakeVerifier(),
      users: new FakeUsers(),
      teams: new FakeTeamRepository(),
      store,
      media: storage,
      transcodeQueue: { enqueue: async (id) => void queued.push(id) },
      now: () => now,
    });
    store.put("teams/t1", {
      ownerId: "owner",
      members: { owner: "owner", p1: "player", mgr: "player" },
      memberIds: ["owner", "p1", "mgr"],
      memberPerms: { mgr: ["manageTeam"] },
      memberRoles: { p1: ["chatter"] },
    });
    store.put("teams/t1/chats/c1", { writeRoles: ["chatter"], writeUsers: [] });
  });

  async function upload(body: object, data: Buffer | null, uid = "u1") {
    const res = await call("/v1/uploads", body, uid);
    if (res.statusCode !== 201) return { res, done: null };
    const { id } = res.json();
    if (data) storage.files.set(`uploads/raw/${uid}/${id}`, { data });
    return { res, id: id as string, done: await call(`/v1/uploads/${id}/complete`, {}, uid) };
  }

  it("signs a URL for the caller's raw path and records the upload", async () => {
    const res = await call("/v1/uploads", { purpose: "avatar", contentType: "image/heic", size: 2_000_000 });
    expect(res.statusCode).toBe(201);
    const { id, uploadUrl, headers, expiresAt } = res.json();
    expect(uploadUrl).toBe(`signed:uploads/raw/u1/${id}`);
    expect(headers).toEqual({ "content-type": "image/heic", "x-goog-content-length-range": "0,10485760" });
    expect(expiresAt).toBe(new Date(now + 15 * 60_000).toISOString());
    expect(store.doc(`uploads/${id}`)).toMatchObject({ uid: "u1", purpose: "avatar", status: "pending", rawPath: `uploads/raw/u1/${id}` });
  });

  it("checks size limits and types up front", async () => {
    expect((await call("/v1/uploads", { purpose: "avatar", contentType: "image/jpeg", size: 11 * 1024 * 1024 })).statusCode).toBe(400);
    expect((await call("/v1/uploads", { purpose: "avatar", contentType: "video/mp4", size: 1000 })).statusCode).toBe(400);
    expect((await call("/v1/uploads", { purpose: "post", contentType: "application/pdf", size: 1000 })).statusCode).toBe(400);
  });

  it("team photos and film need manageTeam (storage.rules)", async () => {
    const body = { purpose: "teamVideo", contentType: "video/quicktime", size: 1000, targetId: "t1" };
    expect((await call("/v1/uploads", body, "p1")).statusCode).toBe(403);
    expect((await call("/v1/uploads", body, "mgr")).statusCode).toBe(201);
    expect((await call("/v1/uploads", { ...body, targetId: "nope" }, "owner")).statusCode).toBe(404);
  });

  it("chat files need write access to the room, or a place in the conversation", async () => {
    const room = { purpose: "chat", contentType: "image/jpeg", size: 1000, targetId: "teams/t1/chats/c1" };
    expect((await call("/v1/uploads", room, "p1")).statusCode).toBe(201);
    expect((await call("/v1/uploads", room, "mgr")).statusCode).toBe(403);
    expect((await call("/v1/uploads", room, "owner")).statusCode).toBe(201);
    expect((await call("/v1/uploads", room, "stranger")).statusCode).toBe(403);
    const dm = { purpose: "chat", contentType: "image/jpeg", size: 1000, targetId: "conversations/u1_u2" };
    expect((await call("/v1/uploads", dm, "u1")).statusCode).toBe(201);
    expect((await call("/v1/uploads", dm, "u3")).statusCode).toBe(403);
    store.put("conversations/g-abc", { participants: ["u1", "u5"] });
    const group = { ...dm, targetId: "conversations/g-abc" };
    expect((await call("/v1/uploads", group, "u5")).statusCode).toBe(201);
    expect((await call("/v1/uploads", group, "u3")).statusCode).toBe(403);
    expect((await call("/v1/uploads", { ...dm, targetId: undefined }, "u1")).statusCode).toBe(400);
  });

  it("compresses a photo on complete and deletes the raw file", async () => {
    const data = await jpeg();
    const { id, done } = await upload({ purpose: "post", contentType: "image/jpeg", size: data.length }, data);
    expect(done!.statusCode).toBe(200);
    expect(done!.json()).toEqual({
      id,
      status: "ready",
      path: `media/u1/${id}.jpg`,
      thumbPath: `media/u1/${id}_thumb.jpg`,
      contentType: "image/jpeg",
      width: 1920,
      height: 960,
    });
    expect(storage.files.has(`uploads/raw/u1/${id}`)).toBe(false);
    expect(storage.files.get(`media/u1/${id}.jpg`)?.contentType).toBe("image/jpeg");
    expect(store.doc(`uploads/${id}`)).toMatchObject({ status: "ready", sniffedType: "image/jpeg" });
    // Completing again just answers.
    expect((await call(`/v1/uploads/${id}/complete`)).json().status).toBe("ready");
  });

  it("goes by the bytes, not the declared type", async () => {
    // Declared a photo, actually a video: an avatar can't be a video.
    const { done, id } = await upload({ purpose: "avatar", contentType: "image/jpeg", size: 100 }, samples["video/mp4"]);
    expect(done!.statusCode).toBe(400);
    expect(done!.json().error.message).toBe("Videos can't be uploaded here.");
    expect(store.doc(`uploads/${id}`)).toMatchObject({ status: "failed" });
    expect(storage.files.has(`uploads/raw/u1/${id}`)).toBe(false);
  });

  it("refuses files that aren't media, and checks the real size", async () => {
    const junk = await upload({ purpose: "post", contentType: "image/png", size: 10 }, Buffer.from("MZ executable"));
    expect(junk.done!.json().error.message).toBe("That file isn't a photo or video we can use.");
    const big = Buffer.concat([await jpeg(), Buffer.alloc(10 * 1024 * 1024)]);
    const tooBig = await upload({ purpose: "post", contentType: "image/jpeg", size: 1000 }, big);
    expect(tooBig.done!.json().error.message).toBe("That file is too big. The most is 10 MB.");
  });

  it("queues a video for transcoding", async () => {
    const { id, done } = await upload({ purpose: "post", contentType: "video/quicktime", size: 1000 }, samples["video/quicktime"]);
    expect(done!.json()).toEqual({ id, status: "processing" });
    expect(store.doc(`uploads/${id}`)).toMatchObject({ status: "processing", sniffedType: "video/quicktime" });
    expect(store.doc(`transcodeJobs/${id}`)).toMatchObject({
      input: `uploads/raw/u1/${id}`,
      output: `media/u1/${id}.mp4`,
      poster: `media/u1/${id}_poster.jpg`,
      status: "queued",
    });
    expect(queued).toEqual([id]);
  });

  it("only the uploader completes it, and only once it's there", async () => {
    const res = await call("/v1/uploads", { purpose: "post", contentType: "image/jpeg", size: 10 });
    const { id } = res.json();
    expect((await call(`/v1/uploads/${id}/complete`, {}, "u2")).statusCode).toBe(404);
    expect((await call(`/v1/uploads/${id}/complete`)).statusCode).toBe(412);
  });
});
