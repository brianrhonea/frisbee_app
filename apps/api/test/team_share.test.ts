// Splitting a team fee (GET / PUT / DELETE /v1/teams/:id/share and
// PUT /v1/teams/:id/share/members/:uid), against FakeStore.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

function setup() {
  const store = new FakeStore();
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store });
  const call = (method: "GET" | "PUT" | "DELETE", url: string, uid: string, body?: object) =>
    app.inject({ method, url, headers: { authorization: `Bearer token:${uid}` }, ...(body !== undefined && { payload: body }) });
  return { store, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.store.put("teams/t1", {
    name: "Northside Flyers",
    ownerId: "olive",
    memberIds: ["olive", "pat", "sam", "cap"],
    members: { olive: "owner", pat: "player", sam: "player", cap: "player" },
    memberNames: { olive: "Olive", pat: "Pat", sam: "Sam", cap: "Cap" },
    memberPerms: { cap: ["manageTeam"] },
  });
  s.store.put("teams/g1", { name: "Pickup", kind: "community", ownerId: "olive", memberIds: ["olive"], members: { olive: "owner" } });
});

const url = "/v1/teams/t1/share";

describe("splitting a team fee", () => {
  it("an admin sets it up and collects; members see only their own share", async () => {
    const set = await s.call("PUT", url, "olive", { amountCents: 4000, note: "Venmo @olive" });
    expect(set.statusCode).toBe(200);
    expect(set.json()).toMatchObject({
      share: { amountCents: 4000, currency: "usd", note: "Venmo @olive", collectorId: "olive", collectorName: "Olive" },
      manages: true,
      mine: null,
    });
    expect(set.json().members.map((m: { uid: string }) => m.uid)).toEqual(["cap", "pat", "sam"]);
    expect(s.store.doc("teams/t1/private/share")).toMatchObject({ amountCents: 4000, collectorId: "olive" });

    const pat = (await s.call("GET", url, "pat")).json();
    expect(pat).toMatchObject({ share: { amountCents: 4000, collectorName: "Olive" }, manages: false, mine: { paid: false }, members: [] });
  });

  it("the collector marks people paid; the member sees it; paid marks survive a change", async () => {
    await s.call("PUT", url, "olive", { amountCents: 4000 });
    const marked = await s.call("PUT", `${url}/members/pat`, "olive", { paid: true });
    expect(marked.statusCode).toBe(200);
    expect(marked.json().members).toEqual([
      { uid: "cap", name: "Cap", paid: false },
      { uid: "sam", name: "Sam", paid: false },
      { uid: "pat", name: "Pat", paid: true },
    ]);
    expect((await s.call("GET", url, "pat")).json().mine).toEqual({ paid: true });
    // Another admin changes the amount: Olive still collects, Pat stays paid.
    const changed = (await s.call("PUT", url, "cap", { amountCents: 4500 })).json();
    expect(changed.share).toMatchObject({ amountCents: 4500, collectorId: "olive" });
    expect((await s.call("GET", url, "pat")).json().mine).toEqual({ paid: true });
    expect((await s.call("PUT", `${url}/members/pat`, "cap", { paid: false })).json().members.every((m: { paid: boolean }) => !m.paid)).toBe(true);
  });

  it("refuses members who don't manage it, outsiders, the collector's own mark and groups", async () => {
    expect((await s.call("PUT", url, "pat", { amountCents: 4000 })).statusCode).toBe(403);
    await s.call("PUT", url, "olive", { amountCents: 4000 });
    expect((await s.call("PUT", `${url}/members/sam`, "pat", { paid: true })).statusCode).toBe(403);
    expect((await s.call("PUT", `${url}/members/olive`, "olive", { paid: true })).statusCode).toBe(404);
    expect((await s.call("PUT", `${url}/members/zed`, "olive", { paid: true })).statusCode).toBe(404);
    expect((await s.call("GET", url, "zed")).statusCode).toBe(404);
    expect((await s.call("PUT", url, "olive", { amountCents: 0 })).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/teams/g1/share", "olive", { amountCents: 100 })).statusCode).toBe(412);
  });

  it("an admin stops the split", async () => {
    await s.call("PUT", url, "olive", { amountCents: 4000 });
    expect((await s.call("DELETE", url, "cap")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/private/share")).toBeUndefined();
    expect((await s.call("GET", url, "pat")).json()).toEqual({ share: null, manages: false, mine: null, members: [] });
    expect((await s.call("DELETE", url, "pat")).statusCode).toBe(403);
  });
});
