// Chat rooms and folders, following the chats and chatFolders rules.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
let store: FakeStore;
let media: FakeMediaStorage;
let call: (method: "POST" | "PATCH" | "PUT" | "DELETE", url: string, body?: object, uid?: string) => Promise<{ status: number; json: () => any }>;
const everyone = { readRoles: ["everyone"], writeRoles: ["everyone"] };

beforeEach(() => {
  store = new FakeStore(() => now);
  const teams = new FakeTeamRepository();
  teams.store = store;
  media = new FakeMediaStorage();
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams, store, media, now: () => now });
  call = async (method, url, body, uid = "coach") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
  store.put("teams/t1", {
    ownerId: "owner",
    memberIds: ["owner", "coach", "player", "mod"],
    members: { owner: "owner", coach: "coach", player: "player", mod: "player" },
    memberPerms: { mod: ["manageChats"] },
  });
  store.put("teams/t1/chats/general", { name: "General", readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [] });
  store.put("teams/t1/chats/coaches", { name: "Coaches", readRoles: ["coach"], writeRoles: ["coach"], readUsers: [], writeUsers: [] });
  store.put("teams/t1/chats/coaches/messages/m1", { text: "secret" });
  media.files.set("teams/t1/chats/coaches/coach/m1/a.jpg", { data: Buffer.from("x") });
});

describe("chat rooms", () => {
  it("are made by members who manage chats, with clean access lists", async () => {
    expect((await call("POST", "/v1/teams/t1/chat-rooms", { name: "Lines", access: everyone }, "player")).status).toBe(403);
    const res = await call("POST", "/v1/teams/t1/chat-rooms", {
      name: " Lines ",
      access: { readRoles: ["everyone"], writeRoles: ["coach"], readUsers: [], writeUsers: [] },
    });
    expect(res.status).toBe(400); // writers must read
    const ok = await call("POST", "/v1/teams/t1/chat-rooms", {
      name: " Lines ",
      access: { readRoles: ["coach", "everyone"], writeRoles: ["coach"], readUsers: ["player", "stranger"], writeUsers: [] },
    });
    expect(ok.status).toBe(201);
    expect(store.doc(`teams/t1/chats/${ok.json().id}`)).toMatchObject({
      name: "Lines",
      kind: "text",
      readRoles: ["coach", "everyone"],
      readUsers: ["player"],
      folderId: null,
      createdBy: "coach",
    });
  });

  it("edits name, folder and access but never the kind", async () => {
    store.put("teams/t1/chatFolders/f1", { name: "Film", position: 0 });
    expect((await call("PATCH", "/v1/teams/t1/chat-rooms/coaches", { name: "Staff", folderId: "f1", access: { readRoles: ["coach"], writeRoles: ["coach"] } })).status).toBe(204);
    expect(store.doc("teams/t1/chats/coaches")).toMatchObject({ name: "Staff", folderId: "f1" });
    expect((await call("PATCH", "/v1/teams/t1/chat-rooms/coaches", { name: "Staff", kind: "voice", access: everyone })).status).toBe(400);
    expect((await call("PATCH", "/v1/teams/t1/chat-rooms/coaches", { name: "Staff", folderId: "nope", access: everyone })).status).toBe(404);
  });

  it("deletes a room with its messages and files, only for someone who can read it, and keeps General", async () => {
    expect((await call("DELETE", "/v1/teams/t1/chat-rooms/coaches", undefined, "mod")).status).toBe(403);
    expect((await call("DELETE", "/v1/teams/t1/chat-rooms/general")).status).toBe(412);
    expect((await call("DELETE", "/v1/teams/t1/chat-rooms/coaches")).status).toBe(204);
    expect(store.doc("teams/t1/chats/coaches")).toBeUndefined();
    expect(store.doc("teams/t1/chats/coaches/messages/m1")).toBeUndefined();
    expect(media.files.size).toBe(0);
  });
});

describe("chat folders", () => {
  it("are made, arranged and deleted, moving their rooms out", async () => {
    const f = await call("POST", "/v1/teams/t1/chat-folders", { name: "Film", access: everyone }, "mod");
    expect(f.status).toBe(201);
    const id = f.json().id as string;
    expect(id.length).toBeLessThanOrEqual(40);
    expect((await call("PUT", "/v1/teams/t1/chat-layout", { folders: [{ id, position: 3 }], rooms: [{ id: "general", position: 1, folderId: id }] }, "mod")).status).toBe(204);
    expect(store.doc("teams/t1/chats/general")).toMatchObject({ position: 1, folderId: id });
    expect(store.doc(`teams/t1/chatFolders/${id}`)?.position).toBe(3);
    expect((await call("PUT", "/v1/teams/t1/chat-layout", { rooms: [{ id: "ghost", position: 0, folderId: null }] }, "mod")).status).toBe(404);
    expect((await call("DELETE", `/v1/teams/t1/chat-folders/${id}`, undefined, "player")).status).toBe(403);
    expect((await call("DELETE", `/v1/teams/t1/chat-folders/${id}`, undefined, "mod")).status).toBe(204);
    expect(store.doc("teams/t1/chats/general")?.folderId).toBeNull();
  });
});
