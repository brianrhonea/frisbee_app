// Deleting a team: the owner only, with the name typed, and unhooked from communities.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
let store: FakeStore;
let teams: FakeTeamRepository;
let media: FakeMediaStorage;
let del: (teamId: string, body: object | undefined, uid?: string) => Promise<number>;

beforeEach(() => {
  store = new FakeStore(() => now);
  teams = new FakeTeamRepository();
  teams.store = store;
  media = new FakeMediaStorage();
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams, store, media, now: () => now });
  del = async (teamId, body, uid = "owner") =>
    (await app.inject({ method: "DELETE", url: `/v1/teams/${teamId}`, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } })).statusCode;
  store.put("teams/t1", {
    name: "Haze",
    ownerId: "owner",
    memberIds: ["owner"],
    members: { owner: "owner" },
    orgId: "org",
    orgLinked: true,
  });
  store.put("teams/t1/chats/general", { name: "General" });
  store.put("teams/t1/chats/general/messages/m1", { text: "hi" });
  store.put("teamDirectory/t1", { name: "Haze" });
  store.put("teams/org", { name: "State U", kind: "organization", ownerId: "boss", memberIds: ["boss"], members: { boss: "owner" }, linkedTeams: { t1: { name: "Haze" }, t2: { name: "Other" } } });
  store.put("teams/t2", { name: "Other", orgId: "org", orgLinked: true });
  media.files.set("teams/t1/posts/p/x.jpg", { data: Buffer.from("x") });
  media.files.set("teams/t10/posts/p/y.jpg", { data: Buffer.from("y") });
});

describe("deleting a team", () => {
  it("is the owner's, with the name typed", async () => {
    expect(await del("t1", { name: "Haze" }, "coach")).toBe(403);
    expect(await del("t1", { name: "Haze" }, "stranger")).toBe(403);
    expect(await del("t1", undefined)).toBe(400);
    expect(await del("t1", { name: "Hase" })).toBe(400);
    expect(store.doc("teams/t1")).toBeDefined();
    expect(await del("nope", { name: "x" })).toBe(404);
  });

  it("waits until the owner is the last one on it (soleOwner)", async () => {
    store.put("teams/t1", { ...store.doc("teams/t1"), memberIds: ["owner", "coach"] });
    expect(await del("t1", { name: "Haze" })).toBe(412);
    // members saying "owner" isn't enough: ownerId decides, as in the rule.
    store.put("teams/t3", { name: "Odd", ownerId: "someone", memberIds: ["owner"], members: { owner: "owner" } });
    expect(await del("t3", { name: "Odd" })).toBe(403);
  });

  it("waits while a league it plays in is going (inActiveLeague)", async () => {
    store.put("teams/t1", { ...store.doc("teams/t1"), leagueId: "lg" });
    store.put("tournaments/lg", { status: "inProgress" });
    expect(await del("t1", { name: "Haze" })).toBe(412);
    store.put("tournaments/lg", { status: "finished" });
    expect(await del("t1", { name: "Haze" })).toBe(204);
  });

  it("waits while it hosts a tournament or league that hasn't finished; finished ones are kept", async () => {
    store.put("tournaments/open", { hostId: "t1", kind: "tournament", status: "live" });
    store.put("tournaments/elsewhere", { hostId: "t2", status: "live" });
    expect(await del("t1", { name: "Haze" })).toBe(412);
    // A league with no status reads as a draft: still unfinished.
    store.put("tournaments/open", { hostId: "t1", kind: "tournament", status: "finished" });
    store.put("tournaments/lg2", { hostId: "t1", kind: "league" });
    expect(await del("t1", { name: "Haze" })).toBe(412);
    store.docs.delete("tournaments/lg2");
    expect(await del("t1", { name: "Haze" })).toBe(204);
    expect(store.doc("tournaments/open")).toMatchObject({ status: "finished" });
  });

  it("waits while Stall 10 holds fees for its events or it owes money back", async () => {
    store.put("charges/cs_1", { hostId: "t1", flow: "platform", status: "paid" });
    expect(await del("t1", { name: "Haze" })).toBe(412);
    store.put("charges/cs_1", { hostId: "t1", flow: "platform", status: "paid", released: true });
    store.put("payoutAccounts/t1", { account: "acct_1", owedCents: 500 });
    expect(await del("t1", { name: "Haze" })).toBe(412);
    store.put("payoutAccounts/t1", { account: "acct_1", owedCents: 0 });
    expect(await del("t1", { name: "Haze" })).toBe(204);
  });

  it("deletes everything under it and its files, and leaves its community's list", async () => {
    expect(await del("t1", { name: " haze " })).toBe(204);
    expect(teams.deleted).toEqual(["t1"]);
    expect([...store.docs.keys()].filter((k) => k.startsWith("teams/t1/") || k === "teams/t1" || k === "teamDirectory/t1")).toEqual([]);
    expect(store.doc("teams/org")?.linkedTeams).toEqual({ t2: { name: "Other" } });
    expect(media.files.has("teams/t1/posts/p/x.jpg")).toBe(false);
    expect(media.files.has("teams/t10/posts/p/y.jpg")).toBe(true);
  });

  it("frees a community's teams when the community goes", async () => {
    expect(await del("org", { name: "State U" }, "boss")).toBe(204);
    expect(store.doc("teams/t2")).toMatchObject({ orgId: null, orgLinked: false });
  });
});
