// D-1317 in the browse callables, against the Firestore emulator
// (npm run test:server): accounts without the adult claim drop out of the
// feed, a post, a profile and search. The claim lookup is stubbed.
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";

import { adults } from "../../src/browse/adults";
import { feed, post, profile, search } from "../../src/browse/functions";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();

const call = (fn: unknown, data: unknown, uid = "viewer1") =>
  (fn as { run: (r: unknown) => Promise<any> }).run({ data, auth: { uid, token: {} }, rawRequest: { headers: {}, ip: "127.0.0.1" } });

const hideTeen = () =>
  vi.spyOn(adults, "hidden").mockImplementation(async (uids) => new Set(uids.filter((u) => u === "baTeen")));

beforeAll(async () => {
  await db.doc("profiles/baTeen").set({ name: "Teen", keywords: ["zork"], private: false });
  await db.doc("profiles/baAdult").set({ name: "Adult", keywords: ["zork"], private: false });
  await db.doc("posts/baPostTeen").set({ authorId: "baTeen", text: "t", createdAt: Timestamp.now() });
  await db.doc("posts/baPostAdult").set({ authorId: "baAdult", text: "a", createdAt: Timestamp.now() });
});
afterEach(() => vi.restoreAllMocks());

describe("browse callables and D-1317", () => {
  it("feed and post leave out the hidden author's posts", async () => {
    hideTeen();
    const f = await call(feed, {});
    const ids = f.posts.map((p: { id: string }) => p.id);
    expect(ids).toContain("baPostAdult");
    expect(ids).not.toContain("baPostTeen");
    await expect(call(post, { id: "baPostTeen" })).rejects.toThrow(/isn't public/);
    expect((await call(post, { id: "baPostAdult" })).post.id).toBe("baPostAdult");
  });

  it("profile answers not-found for a hidden account", async () => {
    hideTeen();
    await expect(call(profile, { uid: "baTeen" })).rejects.toThrow(/No such player/);
    expect((await call(profile, { uid: "baAdult" })).profile).toBeTruthy();
  });

  it("search leaves out hidden accounts", async () => {
    hideTeen();
    const r = await call(search, { kind: "players", key: "zork" });
    expect(r.results.map((x: { id: string }) => x.id)).toEqual(["baAdult"]);
  });

  it("without hiding (report mode) everything is shown", async () => {
    vi.spyOn(adults, "hidden").mockResolvedValue(new Set());
    const r = await call(search, { kind: "players", key: "zork" });
    expect(r.results.map((x: { id: string }) => x.id).sort()).toEqual(["baAdult", "baTeen"]);
  });
});
