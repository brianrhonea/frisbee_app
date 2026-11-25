// A hosted tournament's Captains' channel and each team's thread with the
// organizers (src/tournament_chats): who may open them, who is in them
// (organizers with manageEvents, entered teams' captainIds and admins), that
// membership follows the entries, and that the conversation endpoints treat
// them as server-run (no adding, removing or renaming; participants post).
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 22, 12);
let store: FakeStore;
let call: (method: "POST" | "PATCH" | "DELETE", url: string, uid: string, body?: object) => Promise<{ status: number; json: () => any }>;

beforeEach(() => {
  store = new FakeStore(() => now);
  const users = new FakeUsers();
  for (const [uid, name] of [["dir", "Dana"], ["vol", "Vic"], ["cap1", "Cam"], ["adm2", "Ada"], ["cap3", "Cy"], ["pl1", "Pat"]]) {
    users.records.set(uid, { name, email: `${uid}@x.test` });
    store.put(`profiles/${uid}`, { name });
  }
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now, writeLimits: false });
  call = async (method, url, uid, body) => {
    const res = await app.inject({ method, url, payload: body ?? {}, headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
  // Host: Dana runs it (owner); Vic is a member with manageEvents; Pat plays.
  store.put("teams/host", { name: "Fling Crew", kind: "community", memberIds: ["dir", "vol", "pl1"], members: { dir: "owner", vol: "player", pl1: "player" }, memberPerms: { vol: ["manageEvents"] } });
  store.put("tournaments/t1", { hostId: "host", name: "Spring Fling", status: "registration" });
  // Haze: Cam is a listed captain (a player); Pat is just on the team.
  store.put("teams/haze", { name: "Haze", kind: "team", memberIds: ["cap1", "pl1"], members: { cap1: "player", pl1: "player" } });
  store.put("tournaments/t1/entries/haze", { teamName: "Haze", status: "applied", captainIds: ["cap1"] });
  // Bolt: Ada is its captain role (an admin), no captainIds.
  store.put("teams/bolt", { name: "Bolt", kind: "team", memberIds: ["adm2"], members: { adm2: "captain" } });
  store.put("tournaments/t1/entries/bolt", { teamName: "Bolt", status: "accepted", captainIds: [] });
  // Gone withdrew.
  store.put("teams/gone", { name: "Gone", kind: "team", memberIds: ["cap3"], members: { cap3: "owner" } });
  store.put("tournaments/t1/entries/gone", { teamName: "Gone", status: "withdrawn", captainIds: ["cap3"] });
});

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const docOf = (path: string) => store.doc(path) as Record<string, any>;
const captains = (uid: string) => call("POST", "/v1/tournaments/t1/chats/captains", uid);
const team = (uid: string, teamId = "haze") => call("POST", `/v1/tournaments/t1/chats/teams/${teamId}`, uid);

describe("the Captains' channel", () => {
  it("holds the organizers and active teams' captains, named for the tournament", async () => {
    const res = await captains("cap1");
    expect(res.status).toBe(200);
    const conv = docOf(`conversations/${res.json().id}`);
    expect(res.json().id).toMatch(/^g-[A-Za-z0-9]+$/);
    expect(conv).toMatchObject({ kind: "tournament", tournamentId: "t1", tournamentChat: "captains", name: "Spring Fling · Captains", createdBy: "" });
    // Organizers first, then captains in entry order.
    expect(conv.participants.slice(0, 2)).toEqual(["dir", "vol"]);
    // Only the captains picked with the roster: Bolt's admin, who isn't one, isn't in.
    expect([...conv.participants].sort()).toEqual(["cap1", "dir", "vol"]);
    expect(conv.names).toEqual({ dir: "Dana", vol: "Vic", cap1: "Cam" });
    expect(docOf("tournaments/t1/chats/captains")).toMatchObject({ conversationId: res.json().id, kind: "captains" });
  });

  it("is the same conversation for everyone, and follows the entries", async () => {
    const id = (await captains("dir")).json().id;
    store.put("tournaments/t1/entries/haze", { teamName: "Haze", status: "withdrawn", captainIds: ["cap1"] });
    store.put("tournaments/t1/entries/gone", { teamName: "Gone", status: "waitlisted", captainIds: ["cap3"] });
    expect((await captains("cap3")).json().id).toBe(id);
    expect([...docOf(`conversations/${id}`).participants].sort()).toEqual(["cap3", "dir", "vol"]);
  });

  it("refuses a team's admin who isn't one of its roster's captains", async () => {
    expect((await captains("adm2")).status).toBe(403);
    // They still have their team's own thread with the organizers.
    expect((await team("adm2", "bolt")).status).toBe(200);
  });

  it("refuses players who aren't captains, withdrawn captains and outsiders", async () => {
    for (const uid of ["pl1", "cap3", "someone"]) {
      expect((await captains(uid)).status, uid).toBe(403);
    }
  });

  it("leaves out invited teams until they apply", async () => {
    store.put("tournaments/t1/entries/gone", { teamName: "Gone", status: "invited", captainIds: ["cap3"] });
    expect((await captains("cap3")).status).toBe(403);
    expect((await team("dir", "gone")).status).toBe(403);
    expect(docOf(`conversations/${(await captains("dir")).json().id}`).participants).not.toContain("cap3");
  });

  it("two first opens at once share one conversation", async () => {
    const [a, b] = await Promise.all([captains("cap1"), captains("dir")]);
    expect(a.json().id).toBe(b.json().id);
    expect(docOf("tournaments/t1/chats/captains").conversationId).toBe(a.json().id);
  });

  it("waits while the tournament is a draft", async () => {
    store.put("tournaments/t1", { hostId: "host", name: "Spring Fling", status: "draft" });
    expect((await captains("dir")).status).toBe(403);
  });
});

describe("a team's thread with the organizers", () => {
  it("holds that team's captains and the organizers only", async () => {
    const res = await team("cap1");
    expect(res.status).toBe(200);
    const conv = docOf(`conversations/${res.json().id}`);
    expect(conv).toMatchObject({ kind: "tournament", tournamentChat: "team", teamId: "haze", name: "Haze · Spring Fling organizers" });
    expect(conv.participants).toEqual(["dir", "vol", "cap1"]);
    expect((await team("vol")).json().id).toBe(res.json().id);
  });

  it("refuses other teams' captains, players and teams no longer in it", async () => {
    expect((await team("adm2")).status).toBe(403);
    expect((await team("pl1")).status).toBe(403);
    expect((await team("cap3", "gone")).status).toBe(403);
    expect((await team("dir", "nobody")).status).toBe(403);
  });
});

describe("as conversations", () => {
  it("participants post; nobody adds, removes, leaves or renames", async () => {
    const id = (await team("cap1")).json().id;
    const sent = await call("POST", `/v1/conversations/${id}/messages`, "cap1", { text: "What time is check-in?" });
    expect(sent.status).toBe(201);
    expect(docOf(`conversations/${id}`).lastMessage).toBe("What time is check-in?");
    expect((await call("POST", `/v1/conversations/${id}/messages`, "adm2", { text: "hi" })).status).toBe(404);
    expect((await call("POST", `/v1/conversations/${id}/members`, "dir", { members: ["pl1"] })).status).toBe(412);
    expect((await call("DELETE", `/v1/conversations/${id}/members/cap1`, "cap1")).status).toBe(412);
    expect((await call("PATCH", `/v1/conversations/${id}`, "dir", { name: "Other" })).status).toBe(412);
  });

  it("keeps read times and the latest message when people change", async () => {
    const id = (await captains("cap1")).json().id;
    await call("POST", `/v1/conversations/${id}/messages`, "cap1", { text: "Hello" });
    await captains("dir");
    expect(docOf(`conversations/${id}`)).toMatchObject({ lastMessage: "Hello", lastSenderId: "cap1" });
    expect(Object.keys(docOf(`conversations/${id}`).readAt)).toContain("cap1");
  });
});
