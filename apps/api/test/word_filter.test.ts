// The word filter (packages/shared word_filter.ts, clean() in the request
// schemas): slurs are refused with 400, mild swearing is stored masked.
import { blockedWordsMessage } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users,
    teams: new FakeTeamRepository(),
    store,
    media: new FakeMediaStorage(),
    now: () => now,
  });
  const call = (method: "POST" | "PATCH" | "PUT", url: string, body: object, uid = "me") =>
    app.inject({ method, url, payload: body, headers: { authorization: `Bearer token:${uid}` } });
  return { store, users, call };
}

/** Documents directly in [collection]. */
const inCollection = (collection: string) =>
  [...s.store.docs.entries()].filter(([path]) => path.startsWith(`${collection}/`) && !path.slice(collection.length + 1).includes("/"));

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.users.records.set("me", { name: "Mia Member", email: "mia@x.test" });
});

describe("word filter", () => {
  it("masks mild swearing in a post", async () => {
    const res = await s.call("POST", "/v1/posts", { body: "That was a shit throw, fucking wind" });
    expect(res.statusCode).toBe(201);
    expect(s.store.doc(`posts/${res.json().id}`)?.body).toBe("That was a s*** throw, f****** wind");
  });

  it("refuses a post with a slur, and saves nothing", async () => {
    const res = await s.call("POST", "/v1/posts", { body: "you f@gg0t" });
    expect(res.statusCode).toBe(400);
    expect(JSON.stringify(res.json())).toContain(blockedWordsMessage);
    expect(inCollection("posts")).toHaveLength(0);
  });

  it("refuses telling someone to kill themselves in a comment", async () => {
    const post = await s.call("POST", "/v1/posts", { body: "Nice" });
    const res = await s.call("POST", `/v1/posts/${post.json().id}/comments`, { body: "go kill yourself" });
    expect(res.statusCode).toBe(400);
  });

  it("masks a comment", async () => {
    const post = (await s.call("POST", "/v1/posts", { body: "Nice" })).json().id;
    const res = await s.call("POST", `/v1/posts/${post}/comments`, { body: "holy shit" });
    expect(res.statusCode).toBe(201);
    const [[, comment]] = inCollection(`posts/${post}/comments`);
    expect(comment?.body).toBe("holy s***");
  });
});
