// Discord template imports: the discord-previewTemplate callable's checks,
// fetch, timeout and (new) size cap; and applying a plan with what
// firestore.rules check of the app's batch: setRoles() on the team doc,
// validFolder / validRoom / validAccess and manageChats on the new chat
// docs, then the community split and moves. One test per conjunct.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import { discordFetchTimeoutMs, discordTemplateBytesMax } from "../src/discord/service.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
const fixture = readFileSync(join(import.meta.dirname, "fixtures/discord_template_synthetic.json"), "utf8");
let store: FakeStore;
let call: (url: string, body: object, uid?: string) => Promise<{ status: number; json: () => any }>;
let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  store = new FakeStore(() => now);
  const teams = new FakeTeamRepository();
  teams.store = store;
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams, store, media: new FakeMediaStorage(), now: () => now });
  call = async (url, body, uid = "owner") => {
    const res = await app.inject({ method: "POST", url, payload: body, headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
  fetchMock = vi.fn(async () => new Response(fixture, { status: 200, headers: { "content-type": "application/json" } }));
  vi.stubGlobal("fetch", fetchMock);
  store.put("teams/t1", {
    name: "Rockets",
    kind: "team",
    ownerId: "owner",
    memberIds: ["owner", "chats", "player"],
    members: { owner: "owner", chats: "player", player: "player" },
    memberPerms: { chats: ["manageChats"] },
    memberRoles: { player: ["gone"], ghost: ["x"] },
  });
  store.put("teams/t1/chats/general", { name: "General", readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [], folderId: null, position: 0 });
});
afterEach(() => vi.unstubAllGlobals());

const preview = (body: object = { link: "https://discord.new/abc123" }, uid?: string) => call("/v1/teams/t1/discord/preview", body, uid);
async function plan() {
  const res = await preview();
  expect(res.status).toBe(200);
  return res.json();
}
const apply = (body: object, uid?: string, team = "t1") => call(`/v1/teams/${team}/discord/import`, body, uid);
const docsUnder = (prefix: string) => [...store.docs.entries()].filter(([k]) => k.startsWith(prefix) && k.split("/").length === prefix.split("/").length);

describe("preview (the callable's checks)", () => {
  it("returns the plan for the owner", async () => {
    const p = await plan();
    expect(p.serverName).toBe("Rockets Ultimate");
    expect(p.roles.map((r: { name: string }) => r.name)).toEqual(["Admin", "Captains", "Moderator", "Handlers"]);
    expect(p.rooms).toHaveLength(7);
  });

  it("is for the owner only (members[uid] == 'owner')", async () => {
    expect((await preview(undefined, "chats")).status).toBe(403);
    expect((await preview(undefined, "stranger")).status).toBe(403);
    expect((await call("/v1/teams/nope/discord/preview", { link: "https://discord.new/abc123" })).status).toBe(403);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("needs a template link (templateCode)", async () => {
    expect((await preview({ link: "https://example.com/abc123" })).status).toBe(400);
    expect((await preview({})).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("asks only discord.com, with a timeout, no redirects and no credentials", async () => {
    await plan();
    const [url, init] = fetchMock.mock.calls[0]! as [string, RequestInit];
    expect(url).toBe("https://discord.com/api/v10/guilds/templates/abc123");
    expect(init.redirect).toBe("error");
    expect(init.signal).toBeInstanceOf(AbortSignal);
    const headers = new Headers(init.headers);
    expect(headers.has("authorization")).toBe(false);
    expect(headers.has("cookie")).toBe(false);
    expect(discordFetchTimeoutMs).toBe(10_000);
  });

  it("says when Discord doesn't know the template, is busy, fails or can't be reached", async () => {
    fetchMock.mockResolvedValueOnce(new Response("{}", { status: 404 }));
    expect((await preview()).status).toBe(404);
    fetchMock.mockResolvedValueOnce(new Response("{}", { status: 429 }));
    expect((await preview()).status).toBe(429);
    fetchMock.mockResolvedValueOnce(new Response("{}", { status: 502 }));
    expect((await preview()).status).toBe(500);
    fetchMock.mockRejectedValueOnce(new TypeError("fetch failed"));
    expect((await preview()).status).toBe(500);
    fetchMock.mockResolvedValueOnce(new Response("not json", { status: 200 }));
    expect((await preview()).status).toBe(500);
  });

  it("refuses an answer over the size cap", async () => {
    fetchMock.mockResolvedValueOnce(new Response("x".repeat(discordTemplateBytesMax + 1), { status: 200 }));
    expect((await preview()).status).toBe(412);
    fetchMock.mockResolvedValueOnce(new Response("{}", { status: 200, headers: { "content-length": String(discordTemplateBytesMax + 1) } }));
    expect((await preview()).status).toBe(412);
  });

  it("has its own rate limit", async () => {
    for (let i = 0; i < 10; i++) expect((await preview()).status).toBe(200);
    expect((await preview()).status).toBe(429);
  });
});

describe("apply: the team doc (setRoles)", () => {
  it("is the owner's (isOwner(resource.data))", async () => {
    const p = await plan();
    expect((await apply({ plan: p }, "chats")).status).toBe(403);
    expect((await apply({ plan: p }, "player")).status).toBe(403);
    expect((await apply({ plan: p }, "owner", "nope")).status).toBe(404);
  });

  it("writes roles, memberRoles and memberPerms only, members untouched (changed().hasOnly)", async () => {
    const p = await plan();
    const res = await apply({ plan: p });
    expect(res.status).toBe(200);
    expect(res.json().teams).toEqual([{ teamId: "t1", roles: 4, folders: 2, rooms: 7 }]);
    const team = store.doc("teams/t1")!;
    expect(Object.values(team.roles as object).map((r: { name: string }) => r.name).sort()).toEqual(["Admin", "Captains", "Handlers", "Moderator"]);
    expect(team.members).toEqual({ owner: "owner", chats: "player", player: "player" });
    expect(team).not.toHaveProperty("orgRoles");
  });

  it("keeps memberRoles and memberPerms to members (keys ⊆ memberIds) and existing roles", async () => {
    await apply({ plan: await plan() });
    const team = store.doc("teams/t1")!;
    expect(team.memberRoles).toEqual({});
    expect(Object.keys(team.memberPerms as object)).toEqual([]);
  });

  it("stays within 50 roles (roles.size() <= 50)", async () => {
    const roles: Record<string, object> = {};
    for (let i = 0; i < 48; i++) roles[`r${i}`] = { name: `Role ${i}`, color: 0, position: i, perms: [] };
    store.put("teams/t1", { ...store.doc("teams/t1")!, roles });
    await apply({ plan: await plan() });
    expect(Object.keys(store.doc("teams/t1")!.roles as object)).toHaveLength(50);
  });

  it("refuses a malformed plan (the shapes the rules check)", async () => {
    const p = await plan();
    expect((await apply({ plan: { ...p, roles: [{ ...p.roles[0], name: "x".repeat(41) }] } })).status).toBe(400);
    expect((await apply({ plan: { ...p, rooms: [{ ...p.rooms[0], name: "" }] } })).status).toBe(400);
    expect((await apply({ plan: { ...p, rooms: [{ ...p.rooms[0], name: "x".repeat(61) }] } })).status).toBe(400);
    expect((await apply({ plan: { ...p, folders: [{ ...p.folders[0], readRoles: Array(52).fill("everyone") }] } })).status).toBe(400);
    expect((await apply({ plan: { ...p, rooms: [{ ...p.rooms[0], folderKey: "a/b" }] } })).status).toBe(400);
    expect((await apply({ plan: { ...p, roles: [{ ...p.roles[0], perms: ["godMode"] }] } })).status).toBe(400);
  });
});

describe("apply: folders and rooms (validFolder, validRoom, validAccess)", () => {
  it("writes the app's fields: name, position, access, createdBy, createdAt (keys().hasOnly)", async () => {
    await apply({ plan: await plan() });
    const folders = docsUnder("teams/t1/chatFolders/");
    expect(folders).toHaveLength(2);
    for (const [, f] of folders) {
      expect(Object.keys(f).sort()).toEqual(["createdAt", "createdBy", "name", "position", "readRoles", "readUsers", "writeRoles", "writeUsers"]);
      expect(f.createdBy).toBe("owner");
      expect(f.createdAt).toEqual(new Date(now));
      expect(Number.isInteger(f.position)).toBe(true);
    }
    const rooms = docsUnder("teams/t1/chats/").filter(([k]) => !k.endsWith("/general"));
    expect(rooms).toHaveLength(7);
    for (const [, r] of rooms) {
      expect(Object.keys(r).sort()).toEqual(["createdAt", "createdBy", "folderId", "kind", "name", "position", "readRoles", "readUsers", "writeRoles", "writeUsers"]);
      expect(r.kind).toBe("text");
      expect(r.createdBy).toBe("owner");
    }
  });

  it("folds writers into readers (writeRoles ⊆ readRoles) and sets no single members", async () => {
    await apply({ plan: await plan() });
    for (const [, r] of [...docsUnder("teams/t1/chats/"), ...docsUnder("teams/t1/chatFolders/")]) {
      const read = new Set(r.readRoles as string[]);
      expect((r.writeRoles as string[]).every((w) => read.has(w))).toBe(true);
      expect(r.readUsers).toEqual([]);
      expect(r.writeUsers).toEqual([]);
    }
  });

  it("puts rooms in the new folders, numbered per folder (folderId ≤ 40, position int)", async () => {
    await apply({ plan: await plan() });
    const folders = new Map(docsUnder("teams/t1/chatFolders/").map(([k, f]) => [f.name, k.split("/").pop()!]));
    const rooms = new Map(docsUnder("teams/t1/chats/").map(([, r]) => [r.name, r]));
    expect(rooms.get("handlers-only")).toMatchObject({ folderId: folders.get("Team"), position: 1 });
    expect(rooms.get("off-topic")).toMatchObject({ folderId: null, position: 1 });
    expect(folders.get("Team")!.length).toBeLessThanOrEqual(40);
  });

  it("stays under the room and folder caps (existing plus new)", async () => {
    for (let i = 0; i < 197; i++) store.put(`teams/t1/chats/x${i}`, { name: `x${i}`, folderId: null, position: i + 1 });
    expect((await apply({ plan: await plan() })).status).toBe(412);
    expect(docsUnder("teams/t1/chatFolders/")).toHaveLength(0);
  });

  it("is checked again in the transaction: a former owner can't apply (isOwner and manageChats)", async () => {
    const p = await plan();
    store.put("teams/t1", { ...store.doc("teams/t1")!, members: { owner: "player", chats: "owner", player: "player" }, ownerId: "chats" });
    expect((await apply({ plan: p })).status).toBe(403);
  });

  it("adds nothing the second time", async () => {
    const p = await plan();
    await apply({ plan: p });
    const res = await apply({ plan: p });
    expect(res.json().teams).toEqual([]);
    expect(docsUnder("teams/t1/chats/")).toHaveLength(8);
  });
});

describe("apply in a community with teams (the app's _apply order)", () => {
  beforeEach(() => {
    store.put("teams/org", {
      name: "Rockets",
      kind: "organization",
      ownerId: "owner",
      memberIds: ["owner", "p"],
      members: { owner: "owner", p: "player" },
      roles: { a: { name: "Admin", position: 0 }, h: { name: "Handlers", position: 1 } },
      memberRoles: { p: ["h"] },
      linkedTeams: { woof: { name: "Woof", roles: ["h"] }, theirs: { name: "Theirs", roles: [] } },
    });
    store.put("teams/woof", { name: "Woof", kind: "team", ownerId: "owner", memberIds: ["owner", "p"], members: { owner: "owner", p: "player" }, orgId: "org" });
    store.put("teams/theirs", { name: "Theirs", kind: "team", ownerId: "else", memberIds: ["else"], members: { else: "owner" }, orgId: "org" });
    // An earlier import put everything in the community chat.
    store.put("teams/org/chatFolders/fT", { name: "Team", position: 0, readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [] });
    store.put("teams/org/chats/old", { name: "handlers-only", folderId: "fT", position: 0, readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [] });
    store.put("teams/org/chats/gen", { name: "general", folderId: "fT", position: 1, readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [] });
    store.put("teams/t1", { ...store.doc("teams/t1")!, members: { owner: "owner" }, memberIds: ["owner"] });
  });

  async function orgPlan() {
    const res = await call("/v1/teams/org/discord/preview", { link: "https://discord.new/abc123" });
    expect(res.status).toBe(200);
    return res.json();
  }

  it("sends team rooms to the team the owner owns, with role copies (orgRoles), and moves old copies", async () => {
    const res = await apply({ plan: await orgPlan() }, "owner", "org");
    expect(res.status).toBe(200);
    expect(res.json().movedRooms).toBe(1);
    const woof = store.doc("teams/woof")!;
    const copies = Object.entries(woof.roles as Record<string, { name: string }>);
    expect(copies.map(([, r]) => r.name)).toEqual(["Handlers"]);
    expect(woof.orgRoles).toEqual({ [copies[0]![0]]: "h" });
    const woofRooms = docsUnder("teams/woof/chats/").map(([, r]) => r);
    expect(woofRooms.map((r) => r.name)).toEqual(["handlers-only"]);
    // Handlers is the only role that gets on Woof: the whole team reads it.
    expect(woofRooms[0]!.readRoles).toEqual(["everyone"]);
    expect(store.doc("teams/org/chats/old")).toBeUndefined();
    expect(store.doc("teams/org/chats/gen")).toBeDefined();
    expect(docsUnder("teams/theirs/chats/")).toHaveLength(0);
  });

  it("keeps rooms for teams the caller doesn't own in the community", async () => {
    const p = await orgPlan();
    const res = await apply({ plan: p, destinations: [{ room: 3, teamId: "theirs" }] }, "owner", "org");
    expect(res.status).toBe(200);
    expect(docsUnder("teams/theirs/chats/")).toHaveLength(0);
    expect(store.doc("teams/theirs")!).not.toHaveProperty("roles");
  });

  it("lets the owner keep a room in the community", async () => {
    const p = await orgPlan();
    const res = await apply({ plan: p, destinations: [{ room: 3, teamId: null }] }, "owner", "org");
    expect(res.status).toBe(200);
    expect(res.json().movedRooms).toBe(0);
    expect(docsUnder("teams/woof/chats/")).toHaveLength(0);
    expect(store.doc("teams/org/chats/old")).toBeDefined();
  });
});
