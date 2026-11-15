// FirestoreDocQueries against the Firestore emulator (pnpm test:emulator):
// the id-only and few-field queries the services use in place of lists.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { FirestoreDocQueries } from "../src/queries.js";

const projectId = "demo-stall10";
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run with `pnpm test:emulator`.");

const firebase = initializeApp({ projectId }, "queries-emulator-test");
const db = getFirestore(firebase);
const q = new FirestoreDocQueries(db);
const col = "queryTests/t1/rows";

beforeAll(async () => {
  const b = db.batch();
  b.set(db.doc(`${col}/a`), { tournamentId: "x", status: "accepted", big: "z".repeat(1000), startsAt: Timestamp.fromMillis(0) });
  b.set(db.doc(`${col}/b`), { tournamentId: "x", status: "applied", startsAt: null });
  b.set(db.doc(`${col}/c`), { tournamentId: "y", status: "accepted" });
  b.set(db.doc(`${col}/d`), { tournamentId: "x", status: "accepted" });
  await b.commit();
});

afterAll(async () => {
  await db.recursiveDelete(db.collection("queryTests"));
  await deleteApp(firebase);
});

describe("FirestoreDocQueries", () => {
  it("ids: equality filters, one or two, in id order", async () => {
    expect(await q.ids(col, 10, { tournamentId: "x" })).toEqual(["a", "b", "d"]);
    expect(await q.ids(col, 10, { tournamentId: "x", status: "accepted" })).toEqual(["a", "d"]);
    expect(await q.ids(col, 1, { tournamentId: "x", status: "accepted" })).toEqual(["a"]);
    expect(await q.ids(col, 10, { tournamentId: "none" })).toEqual([]);
  });

  it("ids: no filter, up to the limit", async () => {
    expect(await q.ids(col, 3)).toEqual(["a", "b", "c"]);
  });

  it("fields: only the listed fields, timestamps as Date", async () => {
    const rows = await q.fields(col, ["status", "startsAt"], 2);
    expect(rows.map((r) => r.id)).toEqual(["a", "b"]);
    expect(rows[0].data).toEqual({ status: "accepted", startsAt: new Date(0) });
    expect(rows[1].data).toEqual({ status: "applied", startsAt: null });
  });

  it("fields: with equality filters", async () => {
    const rows = await q.fields(col, ["status"], 10, { tournamentId: "x", status: "accepted" });
    expect(rows).toEqual([
      { id: "a", data: { status: "accepted" } },
      { id: "d", data: { status: "accepted" } },
    ]);
  });
});
