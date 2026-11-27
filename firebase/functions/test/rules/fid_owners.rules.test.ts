// fidOwners/{fid} (the deviceOwnership map) is server-only: no rule matches
// it, so every client read, write and delete is refused, whoever asks,
// including the account the device belongs to and a complete account.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assertFails, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;
const COMPLETE = { email_verified: true, ageOk: true, terms: 1 };

beforeAll(async () => {
  const rules = readFileSync(join(__dirname, "../../../firestore.rules"), "utf8");
  env = await initializeTestEnvironment({ projectId: "demo-fidowners", firestore: { rules } });
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "fidOwners", "fid1"), { uid: "amy", updatedAt: new Date() });
    await setDoc(doc(ctx.firestore(), "users", "amy", "devices", "fid1"), { token: "t", updatedAt: new Date() });
  });
});

describe("fidOwners", () => {
  const clients = {
    "the owning account": () => env.authenticatedContext("amy", COMPLETE).firestore(),
    "another complete account": () => env.authenticatedContext("zed", COMPLETE).firestore(),
    "a signed-in account with no claims": () => env.authenticatedContext("kim").firestore(),
    "a visitor": () => env.unauthenticatedContext().firestore(),
  };
  for (const [who, db] of Object.entries(clients)) {
    it(`refuses every read, write and delete by ${who}`, async () => {
      const ref = doc(db(), "fidOwners", "fid1");
      await assertFails(getDoc(ref));
      await assertFails(getDocs(collection(db(), "fidOwners")));
      await assertFails(setDoc(ref, { uid: "zed", updatedAt: new Date() }));
      await assertFails(setDoc(doc(db(), "fidOwners", "fidNew"), { uid: "amy", updatedAt: new Date() }));
      await assertFails(updateDoc(ref, { uid: "zed" }));
      await assertFails(deleteDoc(ref));
    });
  }

  it("is not reachable by changing a device document either: the device doc stays the client's own, the map is not", async () => {
    const zed = env.authenticatedContext("zed", COMPLETE).firestore();
    await assertFails(setDoc(doc(zed, "fidOwners", "fid1"), { uid: "zed", updatedAt: new Date() }));
  });
});
