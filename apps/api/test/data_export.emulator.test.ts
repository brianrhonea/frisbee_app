// FirestoreExportRepository against the Firestore emulator (pnpm
// test:emulator): the collection-group queries by authorId, the caller's
// own entry of each response map, and paging past one round trip.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { FirestoreExportRepository } from "../src/export/repository.js";

const projectId = "demo-stall10";
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run with `pnpm test:emulator`.");

const firebase = initializeApp({ projectId }, "export-emulator-test");
const db = getFirestore(firebase);
const repo = new FirestoreExportRepository(db);
// Unlikely to clash with other emulator tests' data.
const me = "exportMe";
const team = "exportTeam1";

beforeAll(async () => {
  const b = db.batch();
  b.set(db.doc(`posts/exportP1`), { authorId: me, body: "Hello", createdAt: Timestamp.fromMillis(0) });
  b.set(db.doc(`posts/exportP2`), { authorId: "someone", body: "Theirs" });
  b.set(db.doc(`teams/${team}/posts/tp1`), { authorId: me, title: "Team post" });
  b.set(db.doc(`posts/exportP2/comments/c1`), { authorId: me, body: "Nice" });
  b.set(db.doc(`teams/${team}`), { name: "Export Team", memberIds: [me, "someone"] });
  b.set(db.doc(`teams/${team}/events/e1`), {
    title: "Practice",
    startsAt: Timestamp.fromMillis(0),
    notes: "not asked for",
    rsvps: { [me]: "going", someone: "maybe" },
    rsvpNotes: { someone: "theirs" },
  });
  await b.commit();
  // More messages than one page (500), in one conversation.
  for (let start = 0; start < 520; start += 260) {
    const mb = db.batch();
    for (let i = start; i < start + 260; i++) {
      mb.set(db.doc(`conversations/exportC/messages/m${String(i).padStart(4, "0")}`), { authorId: me, text: `#${i}` });
    }
    await mb.commit();
  }
});

afterAll(async () => {
  for (const path of ["posts/exportP1", "posts/exportP2", `teams/${team}`, "conversations/exportC"]) {
    await db.recursiveDelete(db.doc(path));
  }
  await deleteApp(firebase);
});

describe("FirestoreExportRepository", () => {
  it("finds posts and comments by authorId across collections", async () => {
    const posts = await repo.authored("posts", me, 10);
    expect(posts.map((d) => d.path).sort()).toEqual(["posts/exportP1", `teams/${team}/posts/tp1`]);
    expect(posts.find((d) => d.id === "exportP1")!.data.createdAt).toBe(new Date(0).toISOString());
    const comments = await repo.authored("comments", me, 10);
    expect(comments.map((d) => d.path)).toEqual(["posts/exportP2/comments/c1"]);
  });

  it("pages past one round trip, and reads one more than the cap to tell it was capped", async () => {
    expect(await repo.authored("messages", me, 1000)).toHaveLength(520);
    expect(await repo.authored("messages", me, 510)).toHaveLength(511);
  });

  it("reads only the asked-for fields and the caller's own entries", async () => {
    const [e] = await repo.answers(team, "events", me, ["title", "startsAt"], ["rsvps", "rsvpNotes"], 10);
    expect(e.data).toEqual({ title: "Practice", startsAt: new Date(0).toISOString(), rsvps: { [me]: "going" } });
  });

  it("finds liked posts, calendars, usernames, sign-ups and follow requests without new indexes", async () => {
    const b = db.batch();
    b.set(db.doc("posts/exportLiked"), { authorId: "someone", likedBy: [me, "x"] });
    b.set(db.doc("calendars/exportCal"), { ownerId: "someone", name: "Cal", members: { [me]: "edit" }, memberIds: ["someone", me] });
    b.set(db.doc("usernames/exportname"), { uid: me });
    b.set(db.doc("tournaments/exportT"), { name: "Export Open" });
    b.set(db.doc(`tournaments/exportT/signups/${me}`), { name: "Me", status: "applied" });
    b.set(db.doc("profiles/exportPrivate"), { name: "Priv", private: true });
    b.set(db.doc(`profiles/exportPrivate/followRequests/${me}`), { name: "Me" });
    await b.commit();
    expect((await repo.likedPosts(me, 10)).map((d) => d.id)).toEqual(["exportLiked"]);
    expect((await repo.calendarsOf(me, 10)).map((d) => d.id)).toEqual(["exportCal"]);
    expect((await repo.usernamesOf(me, 10)).map((d) => d.id)).toEqual(["exportname"]);
    const [signup] = await repo.signupsOf(me, 10);
    expect(signup.path).toBe(`tournaments/exportT/signups/${me}`);
    expect(signup.tournament.name).toBe("Export Open");
    const [sent] = await repo.followRequestsSent(me, 10);
    expect(sent.path).toBe(`profiles/exportPrivate/followRequests/${me}`);
    expect(sent.owner.name).toBe("Priv");
    for (const path of ["posts/exportLiked", "calendars/exportCal", "usernames/exportname", "tournaments/exportT", "profiles/exportPrivate"]) {
      await db.recursiveDelete(db.doc(path));
    }
  });

  it("finds the caller's teams", async () => {
    expect((await repo.teamsOf(me, 10)).map((d) => d.id)).toContain(team);
  });
});
