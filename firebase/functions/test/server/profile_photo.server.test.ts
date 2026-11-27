// A notification's copy of a person's photo is the trusted one only (3a-F),
// against the Firestore emulator (npm run test:server).
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";

import { profileOf } from "../../src/notifications/triggers";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();

describe("profileOf", () => {
  it("copies a Google lh3 photo, and drops one from anywhere else", async () => {
    await db.doc("profiles/photoGood").set({ name: "Gia", photoUrl: "https://lh3.googleusercontent.com/a/g" });
    await db.doc("profiles/photoBad").set({ name: "Bo", photoUrl: "https://tracker.example/p.gif" });
    expect(await profileOf("photoGood")).toEqual({ name: "Gia", photoUrl: "https://lh3.googleusercontent.com/a/g" });
    expect(await profileOf("photoBad")).toEqual({ name: "Bo", photoUrl: null });
    expect(await profileOf("photoMissing")).toEqual({ name: "", photoUrl: null });
  });
});
