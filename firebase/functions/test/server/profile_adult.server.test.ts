// D-1317: the profile-created trigger marks a new profile of an account that
// already has the age claim (npm run test:server). Auth is stubbed.
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";

import { markNewProfileAdult } from "../../src/account/functions";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();
const claims = new Set(["paAdult", "paLate"]);
const ageOk = async (u: string) => claims.has(u);

describe("markNewProfileAdult", () => {
  it("marks a new profile whose account has the claim (details saved before the profile)", async () => {
    await db.doc("profiles/paAdult").set({ name: "A" });
    expect(await markNewProfileAdult(db, "paAdult", ageOk)).toBe("set");
    expect((await db.doc("profiles/paAdult").get()).data()).toEqual({ name: "A", adult: true });
  });

  it("is idempotent", async () => {
    expect(await markNewProfileAdult(db, "paAdult", ageOk)).toBe("already");
  });

  it("leaves a profile without the claim alone (a minor, or details not saved yet)", async () => {
    await db.doc("profiles/paTeen").set({ name: "T" });
    expect(await markNewProfileAdult(db, "paTeen", ageOk)).toBe("notAdult");
    expect((await db.doc("profiles/paTeen").get()).data()).toEqual({ name: "T" });
  });

  it("never creates a profile that isn't there", async () => {
    expect(await markNewProfileAdult(db, "paLate", ageOk)).toBe("gone");
    expect((await db.doc("profiles/paLate").get()).exists).toBe(false);
  });
});
