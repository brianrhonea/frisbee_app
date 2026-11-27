// fidOwners/{fid} (the deviceOwnership map) is server-only: no rule matches
// it, so every client read, write and delete is refused, whoever asks,
// including the account the device belongs to and a complete account.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, updateDoc } from "firebase/firestore";
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

  describe("the device document, the client's own path to the map", () => {
    const amy = () => env.authenticatedContext("amy", COMPLETE).firestore();
    const device = (db: ReturnType<typeof amy>, uid = "amy") => doc(db, "users", uid, "devices", "fid1");

    it("takes the server's clock, so the trigger's last-writer-wins order can't be forged", async () => {
      await assertSucceeds(setDoc(device(amy()), { platform: "iOS", updatedAt: serverTimestamp() }));
      await assertFails(setDoc(device(amy()), { platform: "iOS", updatedAt: new Date(0) }));
      await assertFails(setDoc(device(amy()), { platform: "iOS", updatedAt: new Date(Date.now() + 86_400_000) }));
      await assertFails(setDoc(device(amy()), { platform: "iOS" }));
    });

    it("can't carry an owner, a token or any other field", async () => {
      await assertFails(setDoc(device(amy()), { platform: "iOS", updatedAt: serverTimestamp(), uid: "zed" }));
      await assertFails(setDoc(device(amy()), { platform: "iOS", updatedAt: serverTimestamp(), token: "t" }));
    });

    it("is only ever written by its own account", async () => {
      const zed = env.authenticatedContext("zed", COMPLETE).firestore();
      await assertFails(setDoc(device(zed, "amy"), { platform: "iOS", updatedAt: serverTimestamp() }));
      await assertFails(deleteDoc(device(zed, "amy")));
      await assertFails(setDoc(doc(zed, "fidOwners", "fid1"), { uid: "zed", updatedAt: new Date() }));
    });
  });
});
