// The caller's profile and username through the API, against FakeStore,
// following firestore.rules' profiles and usernames rules.
import { profileKeywords, usernameProblem } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 11, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, now: () => now });
  const call = (method: "POST" | "PUT", url: string, body: object, uid = "u1") =>
    app.inject({ method, url, payload: body, headers: { authorization: `Bearer token:${uid}` } });
  return { store, users, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.users.records.set("u1", { name: "Pat Lee", email: "pat@x.test", photoUrl: "https://img/p.jpg" });
});
const P = "profiles/u1";
const H = "profiles/u1/private/details";

describe("claim a username (usernames create, profiles username)", () => {
  const claim = (username: string, uid = "u1") => s.call("POST", "/v1/me/username", { username }, uid);

  it("claims it and puts it on the profile with the directory fields", async () => {
    const res = await claim(" @Pat_Lee ");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ username: "pat_lee" });
    expect(s.store.doc("usernames/pat_lee")).toEqual({ uid: "u1", createdAt: new Date(now) });
    expect(s.store.doc(P)).toEqual({
      name: "Pat Lee",
      keywords: profileKeywords("Pat Lee", "pat_lee"),
      photoUrl: "https://img/p.jpg",
      username: "pat_lee",
      updatedAt: new Date(now),
    });
  });

  it("never lists an email as the name: the handle stands in", async () => {
    s.users.records.set("u1", { email: "pat@x.test" });
    await claim("patl");
    expect(s.store.doc(P)!.name).toBe("patl");
  });

  it("refuses a taken name, keeping the claim", async () => {
    s.store.put("usernames/pat", { uid: "u2" });
    const res = await claim("pat");
    expect(res.statusCode).toBe(409);
    expect(res.json().error.message).toBe("@pat is taken. Try another.");
    expect(s.store.doc(P)).toBeUndefined();
  });

  it("only once per account", async () => {
    s.store.put(P, { name: "Pat", username: "pat" });
    expect((await claim("other")).statusCode).toBe(412);
    expect(s.store.doc("usernames/other")).toBeUndefined();
  });

  it("claiming one's own name again is fine", async () => {
    s.store.put(P, { name: "Pat", username: "pat" });
    s.store.put("usernames/pat", { uid: "u1" });
    expect((await claim("pat")).statusCode).toBe(200);
  });

  it.each(["ab", "a".repeat(21), "pat lee", "pat-lee", ".pat", "pat.", "p..at", "admin"])("refuses %j", async (name) => {
    const res = await claim(name);
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message).toBe(`${usernameProblem(name)}.`);
  });
});

describe("profile details (validProfile, private/details)", () => {
  const details = { bio: " Handler ", pronouns: "they", hometown: "Austin", school: "UT", throwingHand: "left", playingSince: 2015, tags: ["ut", "austin"] };

  it("saves them on the public profile with the directory fields from Auth", async () => {
    s.store.put(P, { name: "Old", username: "pat" });
    expect((await s.call("PUT", "/v1/me/profile/details", details)).statusCode).toBe(200);
    expect(s.store.doc(P)).toEqual({
      name: "Pat Lee",
      username: "pat",
      keywords: profileKeywords("Pat Lee", "pat"),
      photoUrl: "https://img/p.jpg",
      tags: ["ut", "austin"],
      updatedAt: new Date(now),
      bio: "Handler",
      pronouns: "they",
      hometown: "Austin",
      school: "UT",
      throwingHand: "left",
      playingSince: 2015,
      visibility: { stats: true, teams: true, games: true },
    });
  });

  it("on the private doc when the profile is private", async () => {
    s.store.put(P, { name: "Pat", private: true, tags: [] });
    await s.call("PUT", "/v1/me/profile/details", details);
    expect(s.store.doc(P)).not.toHaveProperty("bio");
    expect(s.store.doc(P)!.tags).toEqual([]);
    expect(s.store.doc(H)).toMatchObject({ bio: "Handler", tags: ["ut", "austin"] });
  });

  it("checks the limits", async () => {
    for (const bad of [{ bio: "x".repeat(281) }, { pronouns: "x".repeat(31) }, { hometown: "x".repeat(61) }, { school: "x".repeat(61) }, { throwingHand: "neither" }, { tags: Array(101).fill("t") }, { visibility: { all: true } }, { name: "Not me" }]) {
      expect((await s.call("PUT", "/v1/me/profile/details", bad)).statusCode, JSON.stringify(bad)).toBe(400);
    }
  });

  it("needs a signed-in caller", async () => {
    expect((await s.call("PUT", "/v1/me/profile/details", {}, "")).statusCode).toBe(401);
  });
});

describe("privacy", () => {
  it("making it private moves the details to the private doc", async () => {
    s.store.put(P, { name: "Pat", username: "pat", bio: "Hi", teams: [{ id: "t1" }], tags: ["ut"], photoUrl: null });
    expect((await s.call("PUT", "/v1/me/profile/privacy", { private: true })).statusCode).toBe(200);
    expect(s.store.doc(H)).toEqual({ bio: "Hi", teams: [{ id: "t1" }], tags: ["ut"], updatedAt: new Date(now) });
    const main = s.store.doc(P)!;
    expect(main).toMatchObject({ private: true, tags: [], username: "pat", name: "Pat Lee" });
    expect(main).not.toHaveProperty("bio");
    expect(main).not.toHaveProperty("teams");
  });

  it("making it public moves them back", async () => {
    s.store.put(P, { name: "Pat", private: true, tags: [] });
    s.store.put(H, { bio: "Hi", tags: ["ut"], updatedAt: new Date(0) });
    await s.call("PUT", "/v1/me/profile/privacy", { private: false });
    expect(s.store.doc(P)).toMatchObject({ private: false, bio: "Hi", tags: ["ut"] });
    expect(s.store.doc(P)!.updatedAt).toEqual(new Date(now));
    expect(s.store.doc(H)).toBeUndefined();
  });

  it("does nothing when it's already that way (so the private doc isn't wiped)", async () => {
    s.store.put(P, { name: "Pat", private: true, tags: [] });
    s.store.put(H, { bio: "Hi" });
    await s.call("PUT", "/v1/me/profile/privacy", { private: true });
    expect(s.store.doc(H)).toEqual({ bio: "Hi" });
  });

  it("visibility empties hidden sections", async () => {
    s.store.put(P, { name: "Pat", stats: { s: 1 }, games: [1], teams: [1] });
    await s.call("PUT", "/v1/me/profile/visibility", { visibility: { stats: false, teams: true, games: false }, tags: ["x"] });
    expect(s.store.doc(P)).toMatchObject({ stats: {}, games: [], teams: [1], tags: ["x"], visibility: { stats: false, teams: true, games: false } });
  });

  it("visibility of a private profile goes on the private doc", async () => {
    s.store.put(P, { name: "Pat", private: true });
    await s.call("PUT", "/v1/me/profile/visibility", { visibility: { stats: true, teams: false, games: true }, tags: [] });
    expect(s.store.doc(H)).toMatchObject({ teams: [], visibility: { teams: false } });
    expect(s.store.doc(P)).not.toHaveProperty("visibility");
  });
});
