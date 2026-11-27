// D-1317: `profiles/{uid}.adult` is a server-only marker (the API sets it from
// the age claim). Clients can't create, change or clear it; a direct message,
// a message request, a group add and a message in a direct conversation need
// the other person's profile to carry it; and a list of profiles must filter
// on it (a search says where('adult', '==', true)).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  limit,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;
const COMPLETE = { email_verified: true, ageOk: true, terms: 1 };
const db = (uid: string) => env.authenticatedContext(uid, COMPLETE).firestore();

const AMY = "amy"; // the caller: a complete adult account
const BEA = "bea"; // an adult the server marked
const TOM = "tom"; // listed, but not marked (13 to 17, or never asked)

beforeAll(async () => {
  const rules = readFileSync(join(__dirname, "../../../firestore.rules"), "utf8");
  env = await initializeTestEnvironment({ projectId: "demo-adult-marker", firestore: { rules } });
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await setDoc(doc(fs, "profiles", AMY), { name: "Amy", keywords: ["zork"], photoUrl: null, adult: true });
    await setDoc(doc(fs, "profiles", BEA), { name: "Bea", keywords: ["zork"], photoUrl: null, adult: true });
    await setDoc(doc(fs, "profiles", TOM), { name: "Tom", keywords: ["zork"], photoUrl: null });
    // Both follow Amy, so a start or an add would otherwise pass.
    for (const who of [BEA, TOM]) {
      await setDoc(doc(fs, "users", who, "follows", `user_${AMY}`), { key: `user_${AMY}`, type: "user", targetId: AMY, name: "Amy", notify: false });
    }
  });
});

const conv = (other: string, overrides: Record<string, unknown> = {}) => ({
  participants: [AMY, other],
  names: { [AMY]: "Amy", [other]: "X" },
  lastMessage: "",
  lastMessageAt: null,
  lastSenderId: "",
  readAt: {},
  createdAt: serverTimestamp(),
  ...overrides,
});

describe("starting a direct conversation", () => {
  it("to the user's inbox: an adult target passes, an unmarked one is refused", async () => {
    await assertSucceeds(setDoc(doc(db(AMY), "conversations", `${AMY}_${BEA}`), conv(BEA)));
    await assertFails(setDoc(doc(db(AMY), "conversations", `${AMY}_${TOM}`), conv(TOM)));
  });

  it("as a request: an adult target passes, an unmarked one is refused", async () => {
    const req = (other: string) => conv(other, { status: "request", requestedOf: other });
    await assertSucceeds(setDoc(doc(db(AMY), "conversations", `${AMY}_${BEA}`), req(BEA)));
    await assertFails(setDoc(doc(db(AMY), "conversations", `${AMY}_${TOM}`), req(TOM)));
  });

  it("a target with no profile at all is refused", async () => {
    await assertFails(setDoc(doc(db(AMY), "conversations", `${AMY}_zed`), conv("zed", { status: "request", requestedOf: "zed" })));
  });
});

describe("writing in a direct conversation that already exists", () => {
  beforeEach(() =>
    env.withSecurityRulesDisabled(async (ctx) => {
      for (const other of [BEA, TOM]) {
        await setDoc(doc(ctx.firestore(), "conversations", `${AMY}_${other}`), { ...conv(other), createdAt: new Date(), status: "accepted" });
      }
    }),
  );
  const message = { authorId: AMY, authorName: "Amy", text: "hi", attachments: [], createdAt: serverTimestamp() };

  it("a message to an adult passes, to an unmarked account is refused", async () => {
    await assertSucceeds(setDoc(doc(db(AMY), "conversations", `${AMY}_${BEA}`, "messages", "m1"), message));
    await assertFails(setDoc(doc(db(AMY), "conversations", `${AMY}_${TOM}`, "messages", "m1"), message));
  });
});

describe("adding to a group", () => {
  beforeEach(() =>
    env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "conversations", "g-crew"), {
        kind: "group",
        name: "Crew",
        createdBy: AMY,
        participants: [AMY],
        names: { [AMY]: "Amy" },
        lastMessage: "",
        lastMessageAt: null,
        lastSenderId: "",
        readAt: {},
        createdAt: new Date(),
      }),
    ),
  );
  const add = (who: string) => updateDoc(doc(db(AMY), "conversations", "g-crew"), { participants: [AMY, who], [`names.${who}`]: "N" });

  it("an adult who follows the adder is added; an unmarked account who follows is refused", async () => {
    await assertFails(add(TOM));
    await assertSucceeds(add(BEA));
  });
});

describe("listing profiles", () => {
  const list = (uid: string, ...filters: ReturnType<typeof where>[]) =>
    getDocs(query(collection(db(uid), "profiles"), ...filters, limit(40)));

  it("a search must filter on adult == true", async () => {
    await assertFails(list(AMY));
    await assertFails(list(AMY, where("keywords", "array-contains", "zork")));
    await assertFails(list(AMY, where("adult", "==", false)));
    const snap = await assertSucceeds(list(AMY, where("keywords", "array-contains", "zork"), where("adult", "==", true)));
    if (snap.docs.map((d) => d.id).sort().join() !== `${AMY},${BEA}`) throw new Error("unmarked profile listed");
  });

  it("a tag search works the same way", async () => {
    await assertSucceeds(list(AMY, where("tags", "array-contains", "x"), where("adult", "==", true)));
    await assertFails(list(AMY, where("tags", "array-contains", "x")));
  });

  it("your own profile can be listed by id, marked or not", async () => {
    await assertSucceeds(list(TOM, where(documentId(), "==", TOM)));
    await assertSucceeds(list(AMY, where(documentId(), "==", AMY)));
    await assertFails(list(TOM, where(documentId(), "==", AMY.concat("x"))));
  });

  it("a single profile can still be read by anyone signed in, marked or not", async () => {
    await assertSucceeds(getDoc(doc(db(AMY), "profiles", TOM)));
    await assertSucceeds(getDoc(doc(db(TOM), "profiles", BEA)));
  });

  it("visitors list nothing", async () => {
    await assertFails(getDocs(query(collection(env.unauthenticatedContext().firestore(), "profiles"), where("adult", "==", true), limit(10))));
  });
});

describe("the marker is the server's", () => {
  const base = { name: "Pat", keywords: ["pat"], photoUrl: null, updatedAt: serverTimestamp() };

  it("a client can't create a profile carrying it", async () => {
    await assertFails(setDoc(doc(db("pat"), "profiles", "pat"), { ...base, adult: true }));
    await assertFails(setDoc(doc(db("pat"), "profiles", "pat"), { ...base, adult: false }));
    await assertSucceeds(setDoc(doc(db("pat"), "profiles", "pat"), base));
  });

  it("a fresh profile without the marker (onboarding) can be created and then edited by its owner", async () => {
    await assertSucceeds(setDoc(doc(db("newbie"), "profiles", "newbie"), base));
    await assertSucceeds(updateDoc(doc(db("newbie"), "profiles", "newbie"), { name: "New B", updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(db("newbie"), "profiles", "newbie"), { name: "New C", updatedAt: serverTimestamp() }, { merge: true }));
  });

  it("the owner can't set it on their own profile", async () => {
    await assertFails(updateDoc(doc(db(TOM), "profiles", TOM), { adult: true }));
    await assertFails(setDoc(doc(db(TOM), "profiles", TOM), { ...base, adult: true }));
    await assertFails(setDoc(doc(db(TOM), "profiles", TOM), { name: "Tom", keywords: ["zork"], photoUrl: null, adult: true }, { merge: true }));
  });

  it("the owner can't change or clear it once set", async () => {
    await assertFails(updateDoc(doc(db(AMY), "profiles", AMY), { adult: false }));
    await assertFails(setDoc(doc(db(AMY), "profiles", AMY), { ...base }));
    await assertFails(setDoc(doc(db(AMY), "profiles", AMY), { ...base, adult: false }));
  });

  it("nobody else can write it either", async () => {
    await assertFails(updateDoc(doc(db(AMY), "profiles", TOM), { adult: true }));
  });

  it("existing profile edits still pass, with or without the marker", async () => {
    await assertSucceeds(updateDoc(doc(db(AMY), "profiles", AMY), { name: "Amy B", updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(db(AMY), "profiles", AMY), { ...base, name: "Amy C", adult: true }));
    await assertSucceeds(setDoc(doc(db(AMY), "profiles", AMY), { name: "Amy D", updatedAt: serverTimestamp() }, { merge: true }));
    await assertSucceeds(updateDoc(doc(db(TOM), "profiles", TOM), { name: "Tom B", updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(db(TOM), "profiles", TOM), { name: "Tom C", updatedAt: serverTimestamp() }, { merge: true }));
  });

  it("deleting the profile is still the owner's, and a re-created one starts unmarked", async () => {
    await assertSucceeds(deleteDoc(doc(db(AMY), "profiles", AMY)));
    await assertSucceeds(setDoc(doc(db(AMY), "profiles", AMY), base));
    // Unmarked again until the server sets it, so she can't be started with
    // (even by someone she follows).
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "users", AMY, "follows", `user_${BEA}`), { key: `user_${BEA}`, type: "user", targetId: BEA, name: "Bea", notify: false }),
    );
    await assertFails(setDoc(doc(db(BEA), "conversations", `${AMY}_${BEA}`), { ...conv(BEA), participants: [AMY, BEA] }));
  });
});
