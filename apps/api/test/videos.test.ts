// Team videos and folders, following the videos and videoFolders rules:
// one test per conjunct of each allow expression (and validVideo/validFile).
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { folderScanLimit, unsortChunk } from "../src/videos/service.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
const yt = "dQw4w9WgXcQ";
const MB = 1024 * 1024;
let store: FakeStore;
let media: FakeMediaStorage;
let users: FakeUsers;
type Res = { status: number; json: () => any };
let call: (method: "POST" | "PATCH" | "DELETE", url: string, body?: object, uid?: string | null) => Promise<Res>;

const goodFile = (path = "teams/t1/videos/v2/game.mp4") => ({ path, name: "game.mp4", size: 10 * MB, contentType: "video/mp4" });
const youTubeVideo = { youtubeId: yt, file: null, folderId: "", title: "Film", description: "", authorId: "coach", authorName: "Coach", createdAt: new Date(0), updatedAt: new Date(0) };
const fileVideo = { ...youTubeVideo, youtubeId: "", file: goodFile() };

beforeEach(() => {
  store = new FakeStore(() => now);
  media = new FakeMediaStorage();
  users = new FakeUsers();
  users.records.set("coach", { name: "Coach Carter" });
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media, now: () => now });
  call = async (method, url, body, uid = "coach") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
    return { status: res.statusCode, json: () => res.json() };
  };
  store.put("teams/t1", {
    ownerId: "owner",
    memberIds: ["owner", "coach", "player", "granted"],
    members: { owner: "owner", coach: "coach", player: "player", granted: "player", ghost: "coach" },
    memberPerms: { granted: ["manageTeam"], player: ["manageEvents"] },
  });
  store.put("teams/t1/videos/v1", youTubeVideo);
  store.put("teams/t1/videos/v2", fileVideo);
  store.put("teams/t1/videoFolders/f1", { name: "Game film", createdAt: new Date(0) });
  media.files.set("teams/t1/videos/v2/game.mp4", { data: Buffer.from("x"), contentType: "video/mp4" });
});

const add = (body: object, uid?: string) => call("POST", "/v1/teams/t1/videos", { youtubeId: yt, title: "Pull plays", ...body }, uid);
const edit = (id: string, body: object, uid?: string) => call("PATCH", `/v1/teams/t1/videos/${id}`, body, uid);

describe("adding a video (create rule)", () => {
  it("writes exactly the rule's keys, as the app's _created does", async () => {
    const res = await add({ description: "  Watch the cutters ", folderId: "f1" });
    expect(res.status).toBe(201);
    expect(store.doc(`teams/t1/videos/${res.json().id}`)).toEqual({
      youtubeId: yt,
      file: null,
      folderId: "f1",
      title: "Pull plays",
      description: "Watch the cutters",
      authorId: "coach",
      authorName: "Coach Carter",
      createdAt: new Date(now),
      updatedAt: new Date(now),
    });
  });

  it("signedIn()", async () => {
    expect((await add({}, null as unknown as string)).status).toBe(401);
  });

  it("can(team(), 'manageTeam'): owners, coaches, captains and members granted it", async () => {
    expect((await add({}, "owner")).status).toBe(201);
    expect((await add({}, "granted")).status).toBe(201);
    expect((await add({}, "player")).status).toBe(403);
    expect((await add({}, "stranger")).status).toBe(403);
    // A tier without membership (memberIds) isn't enough here, as in the playbook.
    expect((await add({}, "ghost")).status).toBe(403);
    expect((await call("POST", "/v1/teams/nope/videos", { youtubeId: yt, title: "a" })).status).toBe(404);
  });

  it("keys().hasOnly(...): no other fields, and no file from the client", async () => {
    expect((await add({ authorId: "owner" })).status).toBe(400);
    expect((await add({ file: goodFile() })).status).toBe(400);
    expect((await add({ createdAt: "2020-01-01" })).status).toBe(400);
  });

  it("authorId == uid() and validString(authorName, 80)", async () => {
    users.records.set("coach", { name: "N".repeat(120) });
    const res = await add({});
    const doc = store.doc(`teams/t1/videos/${res.json().id}`)!;
    expect(doc.authorId).toBe("coach");
    expect(doc.authorName).toBe("N".repeat(80));
  });

  it("createdAt and updatedAt == request.time", async () => {
    const doc = store.doc(`teams/t1/videos/${(await add({})).json().id}`)!;
    expect(doc.createdAt).toEqual(new Date(now));
    expect(doc.updatedAt).toEqual(new Date(now));
  });

  it("validVideo: folderId a string of at most 40", async () => {
    expect((await add({ folderId: "f".repeat(41) })).status).toBe(400);
    expect((await add({ folderId: 3 })).status).toBe(400);
  });

  it("validVideo: title 1–100", async () => {
    expect((await add({ title: "" })).status).toBe(400);
    expect((await add({ title: "t".repeat(101) })).status).toBe(400);
    expect((await add({ title: "t".repeat(100) })).status).toBe(201);
  });

  it("validVideo: description a string of at most 2000", async () => {
    expect((await add({ description: "d".repeat(2001) })).status).toBe(400);
    expect((await add({ description: 5 })).status).toBe(400);
  });

  it("validVideo: no file means an 11-character YouTube id", async () => {
    expect((await add({ youtubeId: "short" })).status).toBe(400);
    expect((await add({ youtubeId: "dQw4w9WgXc!" })).status).toBe(400);
    expect((await add({ youtubeId: `https://youtu.be/${yt}` })).status).toBe(400);
  });

  it("files a video only in a folder that exists (stricter than the rule)", async () => {
    expect((await add({ folderId: "gone" })).status).toBe(404);
  });
});

describe("editing a video (update rule)", () => {
  it("changes the editable fields and updatedAt", async () => {
    expect((await edit("v1", { title: " New ", description: "d", folderId: "f1", youtubeId: "abcdefghijk" })).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1")).toEqual({ ...youTubeVideo, title: "New", description: "d", folderId: "f1", youtubeId: "abcdefghijk", updatedAt: new Date(now) });
  });

  it("moves a video between folders, and back to none", async () => {
    expect((await edit("v1", { folderId: "f1" })).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1")?.folderId).toBe("f1");
    expect((await edit("v1", { folderId: "" })).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1")?.folderId).toBe("");
    expect((await edit("v1", { folderId: "gone" })).status).toBe(404);
  });

  it("signedIn() and can(team(), 'manageTeam')", async () => {
    expect((await edit("v1", { title: "x" }, null as unknown as string)).status).toBe(401);
    expect((await edit("v1", { title: "x" }, "player")).status).toBe(403);
    expect((await edit("v1", { title: "x" }, "granted")).status).toBe(204);
  });

  it("changed().hasOnly(...): the file, author and createdAt never change", async () => {
    expect((await edit("v2", { file: goodFile("teams/t1/videos/v2/other.mp4") })).status).toBe(400);
    expect((await edit("v1", { authorId: "owner" })).status).toBe(400);
    expect((await edit("v1", { createdAt: "2020" })).status).toBe(400);
    await edit("v2", { title: "Edited" });
    const doc = store.doc("teams/t1/videos/v2")!;
    expect(doc.file).toEqual(goodFile());
    expect(doc.authorId).toBe("coach");
    expect(doc.createdAt).toEqual(new Date(0));
  });

  it("updatedAt == request.time", async () => {
    await edit("v1", { title: "x" });
    expect(store.doc("teams/t1/videos/v1")?.updatedAt).toEqual(new Date(now));
  });

  it("validVideo runs on the whole result: limits", async () => {
    expect((await edit("v1", { title: "" })).status).toBe(400);
    expect((await edit("v1", { title: "t".repeat(101) })).status).toBe(400);
    expect((await edit("v1", { description: "d".repeat(2001) })).status).toBe(400);
    expect((await edit("v1", { folderId: "f".repeat(41) })).status).toBe(400);
    store.put("teams/t1/videos/v3", { ...youTubeVideo, description: 7 });
    expect((await edit("v3", { folderId: "f1" })).status).toBe(400);
    store.put("teams/t1/videos/v4", { ...youTubeVideo, title: "" });
    expect((await edit("v4", { folderId: "f1" })).status).toBe(400);
  });

  it("validVideo: a YouTube video keeps a valid id", async () => {
    expect((await edit("v1", { youtubeId: "" })).status).toBe(400);
    expect((await edit("v1", { youtubeId: "bad" })).status).toBe(400);
  });

  it("validVideo: an upload keeps youtubeId empty", async () => {
    expect((await edit("v2", { youtubeId: yt })).status).toBe(400);
    expect((await edit("v2", { youtubeId: "", title: "Upload" })).status).toBe(204);
  });

  describe("validFile on the stored upload", () => {
    const seeded = async (file: unknown) => {
      store.put("teams/t1/videos/v2", { ...fileVideo, file });
      return (await edit("v2", { title: "x" })).status;
    };
    it("is a map", async () => expect(await seeded("teams/t1/videos/v2/game.mp4")).toBe(400));
    it("keys().hasOnly(['path', 'name', 'size', 'contentType'])", async () => expect(await seeded({ ...goodFile(), url: "x" })).toBe(400));
    it("path is a string under teams/{teamId}/videos/{videoId}/", async () => {
      expect(await seeded({ ...goodFile(), path: 5 })).toBe(400);
      expect(await seeded(goodFile("teams/t2/videos/v2/game.mp4"))).toBe(400);
      expect(await seeded(goodFile("teams/t1/videos/v1/game.mp4"))).toBe(400);
      expect(await seeded(goodFile("teams/t1/videos/v2/a/game.mp4"))).toBe(400);
      expect(await seeded(goodFile("teams/t1/videos/v2/"))).toBe(400);
    });
    it("name is 1–200 characters", async () => {
      expect(await seeded({ ...goodFile(), name: "" })).toBe(400);
      expect(await seeded({ ...goodFile(), name: "n".repeat(201) })).toBe(400);
    });
    it("size is an int, over 0 and at most 500 MB", async () => {
      expect(await seeded({ ...goodFile(), size: 0 })).toBe(400);
      expect(await seeded({ ...goodFile(), size: 1.5 })).toBe(400);
      expect(await seeded({ ...goodFile(), size: 500 * MB + 1 })).toBe(400);
      expect(await seeded({ ...goodFile(), size: 500 * MB })).toBe(204);
    });
    it("contentType is one of the rule's video types", async () => {
      expect(await seeded({ ...goodFile(), contentType: "image/png" })).toBe(400);
      expect(await seeded({ ...goodFile(), contentType: "video/x-ms-wmv" })).toBe(204);
    });
  });

  it("refuses a missing video and bad ids", async () => {
    expect((await edit("ghost", { title: "x" })).status).toBe(404);
    expect((await edit("__x__", { title: "x" })).status).toBe(400);
    expect((await edit("v1", {})).status).toBe(400);
  });
});

describe("removing a video (delete rule)", () => {
  it("signedIn() and can(team(), 'manageTeam')", async () => {
    expect((await call("DELETE", "/v1/teams/t1/videos/v1", undefined, null)).status).toBe(401);
    expect((await call("DELETE", "/v1/teams/t1/videos/v1", undefined, "player")).status).toBe(403);
    expect(store.doc("teams/t1/videos/v1")).toBeDefined();
    expect((await call("DELETE", "/v1/teams/t1/videos/v1")).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1")).toBeUndefined();
  });

  it("deletes an upload's file too, as the app does", async () => {
    expect((await call("DELETE", "/v1/teams/t1/videos/v2")).status).toBe(204);
    expect(store.doc("teams/t1/videos/v2")).toBeUndefined();
    expect(media.files.has("teams/t1/videos/v2/game.mp4")).toBe(false);
  });

  it("never deletes a stored path outside the video's own folder", async () => {
    media.files.set("users/owner/profile/me.jpg", { data: Buffer.from("x") });
    store.put("teams/t1/videos/v2", { ...fileVideo, file: goodFile("users/owner/profile/me.jpg") });
    expect((await call("DELETE", "/v1/teams/t1/videos/v2")).status).toBe(204);
    expect(media.files.has("users/owner/profile/me.jpg")).toBe(true);
  });

  it("is done when the video is already gone", async () => {
    expect((await call("DELETE", "/v1/teams/t1/videos/ghost")).status).toBe(204);
  });
});

describe("folders (videoFolders rules)", () => {
  it("create: can(manageTeam), keys name and createdAt only, createdAt == request.time", async () => {
    expect((await call("POST", "/v1/teams/t1/video-folders", { name: "Highlights" }, null)).status).toBe(401);
    expect((await call("POST", "/v1/teams/t1/video-folders", { name: "Highlights" }, "player")).status).toBe(403);
    expect((await call("POST", "/v1/teams/t1/video-folders", { name: "Highlights", position: 1 })).status).toBe(400);
    const res = await call("POST", "/v1/teams/t1/video-folders", { name: "  Highlights " }, "granted");
    expect(res.status).toBe(201);
    expect(res.json().id.length).toBeLessThanOrEqual(40);
    expect(store.doc(`teams/t1/videoFolders/${res.json().id}`)).toEqual({ name: "Highlights", createdAt: new Date(now) });
  });

  it("validFolder: name 1–40", async () => {
    expect((await call("POST", "/v1/teams/t1/video-folders", { name: " " })).status).toBe(400);
    expect((await call("POST", "/v1/teams/t1/video-folders", { name: "n".repeat(41) })).status).toBe(400);
    expect((await call("PATCH", "/v1/teams/t1/video-folders/f1", { name: "n".repeat(41) })).status).toBe(400);
  });

  it("update: can(manageTeam), changes only the name", async () => {
    expect((await call("PATCH", "/v1/teams/t1/video-folders/f1", { name: "Film" }, "player")).status).toBe(403);
    expect((await call("PATCH", "/v1/teams/t1/video-folders/f1", { name: "Film", createdAt: "x" })).status).toBe(400);
    expect((await call("PATCH", "/v1/teams/t1/video-folders/f1", { name: "Film" })).status).toBe(204);
    expect(store.doc("teams/t1/videoFolders/f1")).toEqual({ name: "Film", createdAt: new Date(0) });
    expect((await call("PATCH", "/v1/teams/t1/video-folders/ghost", { name: "Film" })).status).toBe(404);
  });

  it("delete: can(manageTeam); its videos are unsorted first, as the app's batch does", async () => {
    store.put("teams/t1/videos/v1", { ...youTubeVideo, folderId: "f1" });
    store.put("teams/t1/videos/v2", { ...fileVideo, folderId: "f1" });
    store.put("teams/t1/videos/v3", { ...youTubeVideo, folderId: "other" });
    expect((await call("DELETE", "/v1/teams/t1/video-folders/f1", undefined, "player")).status).toBe(403);
    expect(store.doc("teams/t1/videos/v1")?.folderId).toBe("f1");
    expect((await call("DELETE", "/v1/teams/t1/video-folders/f1")).status).toBe(204);
    expect(store.doc("teams/t1/videoFolders/f1")).toBeUndefined();
    expect(store.doc("teams/t1/videos/v1")).toMatchObject({ folderId: "", updatedAt: new Date(now) });
    expect(store.doc("teams/t1/videos/v2")).toMatchObject({ folderId: "", updatedAt: new Date(now), file: goodFile() });
    expect(store.doc("teams/t1/videos/v3")).toMatchObject({ folderId: "other", updatedAt: new Date(0) });
  });

  it("delete unsorts more videos than one chunk", async () => {
    const n = unsortChunk + 5;
    for (let i = 0; i < n; i++) store.put(`teams/t1/videos/m${String(i).padStart(4, "0")}`, { ...youTubeVideo, folderId: "f1" });
    expect((await call("DELETE", "/v1/teams/t1/video-folders/f1")).status).toBe(204);
    const left = (await store.list("teams/t1/videos", folderScanLimit)).filter((v) => v.data.folderId === "f1");
    expect(left).toHaveLength(0);
  });

  it("delete refuses if a filed video couldn't pass the update rule", async () => {
    store.put("teams/t1/videos/v1", { ...youTubeVideo, folderId: "f1", title: "" });
    expect((await call("DELETE", "/v1/teams/t1/video-folders/f1")).status).toBe(412);
    expect(store.doc("teams/t1/videoFolders/f1")).toBeDefined();
  });

  it("delete is done when the folder is already gone", async () => {
    expect((await call("DELETE", "/v1/teams/t1/video-folders/ghost")).status).toBe(204);
  });
});

describe("write limit", () => {
  it("uses the hub's write bucket", async () => {
    let last = 0;
    for (let i = 0; i < 200 && last !== 429; i++) last = (await edit("v1", { title: `t${i}` })).status;
    expect(last).toBe(429);
  });
});
