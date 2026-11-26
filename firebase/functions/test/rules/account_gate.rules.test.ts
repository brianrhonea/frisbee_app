import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  serverTimestamp,
  updateDoc,
  addDoc,
  writeBatch,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

// The account gate (SEC-2, docs/specifications/contracts/account-gate.md):
// every client write that is user activity needs a verified email plus the
// API-set `ageOk` and `terms` claims; reads and the onboarding paths (own
// users doc, profile and username, devices, notification settings) don't.
// Run with `npm run test:rules` (needs Java).

let env: RulesTestEnvironment;

const TEAM = "team1";
const OWNER = "owner";
const COACH = "coach";
const CAPTAIN = "captain";
const PLAYER = "player";
const OUTSIDER = "outsider";
const CONV = `${OWNER}_${PLAYER}`;

// What a token can carry: email_verified from Auth, ageOk and terms from the API.
const complete = { email_verified: true, ageOk: true, terms: 1 };
const incomplete = {
  unverified: { ageOk: true, terms: 1, email_verified: false },
  "no ageOk": { email_verified: true, terms: 1 },
  "ageOk false": { email_verified: true, ageOk: false, terms: 1 },
  "no terms": { email_verified: true, ageOk: true },
  "terms 0": { email_verified: true, ageOk: true, terms: 0 },
  "terms as a string": { email_verified: true, ageOk: true, terms: "1" },
  "ageOk as a string": { email_verified: true, ageOk: "true", terms: 1 },
  "a REST-created account (nothing)": {},
};

const fs = (uid: string, claims: Record<string, unknown> = complete) => env.authenticatedContext(uid, claims).firestore();
const st = (uid: string, claims: Record<string, unknown> = complete) => env.authenticatedContext(uid, claims).storage();
const bytes = (n: number) => new Uint8Array(n);

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-frisbee",
    firestore: { rules: readFileSync(join(__dirname, "../../../firestore.rules"), "utf8") },
    storage: { rules: readFileSync(join(__dirname, "../../../storage.rules"), "utf8") },
  });
}, 60_000);

afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    // Video uploads on, so the video case tests only the account gate
    // (the flag itself: storage.rules.test.ts).
    await setDoc(doc(f, "meta", "flags"), { videoUploads: true });
    await setDoc(doc(f, "teams", TEAM), {
      name: "Team",
      division: "mixed",
      level: "college",
      city: "",
      ownerId: OWNER,
      members: { [OWNER]: "owner", [COACH]: "coach", [CAPTAIN]: "captain", [PLAYER]: "player" },
      memberIds: [OWNER, COACH, CAPTAIN, PLAYER],
      memberNames: { [OWNER]: "O", [COACH]: "C", [CAPTAIN]: "K", [PLAYER]: "P" },
    });
    await setDoc(doc(f, "teams", TEAM, "chats", "r1"), {
      name: "Captains",
      readRoles: ["owner", "coach", "captain"],
      writeRoles: ["owner", "captain"],
      readUsers: [],
      writeUsers: [],
      createdBy: COACH,
      createdAt: new Date(),
    });
    await setDoc(doc(f, "teams", TEAM, "events", "e1"), {
      title: "Practice",
      type: "practice",
      startsAt: new Date("2026-11-02T18:00:00Z"),
      endsAt: null,
      location: "",
      notes: "",
      rsvps: {},
      reactions: {},
      votes: {},
      createdBy: COACH,
    });
    await setDoc(doc(f, "conversations", CONV), {
      participants: [OWNER, PLAYER],
      names: { [OWNER]: "O", [PLAYER]: "P" },
      lastMessage: "",
      lastMessageAt: null,
      lastSenderId: "",
      readAt: {},
      createdAt: new Date(),
    });
    await ctx
      .storage()
      .ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m1/0-photo.png`)
      .put(bytes(10), { contentType: "image/png" });
  });
});

/** Each write is tried by a complete account (must succeed) and by every incomplete one (must fail). */
type Write = [name: string, uid: string, run: (db: ReturnType<typeof fs>) => Promise<unknown>];

const writes: Write[] = [
  [
    "creating a team",
    OUTSIDER,
    (db) =>
      setDoc(doc(db, "teams", "t2"), {
        name: "New",
        division: "open",
        level: "college",
        city: "Denver",
        ownerId: OUTSIDER,
        members: { [OUTSIDER]: "owner" },
        memberIds: [OUTSIDER],
        memberNames: { [OUTSIDER]: "Me" },
      }),
  ],
  [
    "a chat message",
    CAPTAIN,
    (db) =>
      addDoc(collection(db, "teams", TEAM, "chats", "r1", "messages"), {
        authorId: CAPTAIN,
        authorName: "Name",
        text: "Hi",
        attachments: [],
        createdAt: serverTimestamp(),
      }),
  ],
  [
    "a direct message",
    PLAYER,
    (db) =>
      addDoc(collection(db, "conversations", CONV, "messages"), {
        authorId: PLAYER,
        authorName: "N",
        text: "Hi",
        attachments: [],
        createdAt: serverTimestamp(),
      }),
  ],
  ["an RSVP", PLAYER, (db) => updateDoc(doc(db, "teams", TEAM, "events", "e1"), { [`rsvps.${PLAYER}`]: "going" })],
  [
    "a follow",
    OUTSIDER,
    (db) =>
      setDoc(doc(db, "users", OUTSIDER, "follows", `user_${PLAYER}`), {
        key: `user_${PLAYER}`,
        type: "user",
        targetId: PLAYER,
        name: "Pat",
        notify: false,
        createdAt: serverTimestamp(),
      }),
  ],
  ["deleting an event", COACH, (db) => deleteDoc(doc(db, "teams", TEAM, "events", "e1"))],
];

describe("Firestore writes", () => {
  for (const [name, uid, run] of writes) {
    it(`${name}: a complete account may`, async () => {
      await assertSucceeds(run(fs(uid)));
    });
    for (const [label, claims] of Object.entries(incomplete)) {
      it(`${name}: refused for ${label}`, async () => {
        await assertFails(run(fs(uid, claims)));
      });
    }
  }

  it("signed out is refused as before", async () => {
    await assertFails(updateDoc(doc(env.unauthenticatedContext().firestore(), "teams", TEAM, "events", "e1"), { [`rsvps.${PLAYER}`]: "going" }));
  });

  it("a claim can't be given by writing it: users docs take no claims or agreement", async () => {
    await assertFails(setDoc(doc(fs(PLAYER, {}), "users", PLAYER), { ageOk: true }, { merge: true }));
    await assertFails(setDoc(doc(fs(PLAYER), "users", PLAYER), { agreedTerms: { version: 1 } }, { merge: true }));
  });
});

describe("Firestore reads stay open to an incomplete account", () => {
  for (const [label, claims] of Object.entries(incomplete)) {
    it(`${label}: reads its team, events and own chat`, async () => {
      await assertSucceeds(getDoc(doc(fs(PLAYER, claims), "teams", TEAM)));
      await assertSucceeds(getDoc(doc(fs(PLAYER, claims), "teams", TEAM, "events", "e1")));
      await assertSucceeds(getDoc(doc(fs(PLAYER, claims), "conversations", CONV)));
    });
  }
});

describe("the onboarding paths stay open to an incomplete account", () => {
  for (const [label, claims] of Object.entries(incomplete)) {
    it(`${label}: users doc, device, notification settings, profile and username`, async () => {
      const db = fs(PLAYER, claims);
      await assertSucceeds(setDoc(doc(db, "users", PLAYER), { displayName: "Pat", updatedAt: serverTimestamp() }, { merge: true }));
      await assertSucceeds(
        setDoc(doc(db, "users", PLAYER, "devices", "fid1"), { platform: "iOS", updatedAt: serverTimestamp() }),
      );
      await assertSucceeds(
        setDoc(doc(db, "users", PLAYER, "settings", "notifications"), { categories: { chat: false }, updatedAt: serverTimestamp() }, { merge: true }),
      );
      await assertSucceeds(
        writeBatch(db)
          .set(doc(db, "usernames", "pat.player"), { uid: PLAYER, createdAt: serverTimestamp() })
          .set(doc(db, "profiles", PLAYER), { name: "Pat Player", keywords: ["pat"], photoUrl: null, username: "pat.player", updatedAt: serverTimestamp() }, { merge: true })
          .commit(),
      );
      await assertSucceeds(deleteDoc(doc(db, "users", PLAYER, "devices", "fid1")));
    });
  }

  it("but only their own", async () => {
    const db = fs(PLAYER, {});
    await assertFails(setDoc(doc(db, "users", OWNER, "devices", "fid1"), { platform: "iOS", updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(db, "profiles", OWNER), { name: "Not me", keywords: [], photoUrl: null, updatedAt: serverTimestamp() }));
  });
});

describe("Storage", () => {
  const png = { contentType: "image/png" };
  const uploads: Array<[string, string, (s: ReturnType<typeof st>) => Promise<unknown>]> = [
    ["a chat attachment", CAPTAIN, (s) => s.ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m2/0-ok.png`).put(bytes(10), png).then()],
    ["a direct-message attachment", PLAYER, (s) => s.ref(`conversations/${CONV}/${PLAYER}/m1/0-photo.png`).put(bytes(10), png).then()],
    ["a team post photo", COACH, (s) => s.ref(`teams/${TEAM}/posts/p1/1/0-photo.png`).put(bytes(10), png).then()],
    ["a team video", COACH, (s) => s.ref(`teams/${TEAM}/videos/v1/clip.mp4`).put(bytes(10), { contentType: "video/mp4" }).then()],
    ["a post photo", PLAYER, (s) => s.ref(`users/${PLAYER}/posts/p1/1/0-photo.png`).put(bytes(10), png).then()],
    ["deleting a chat attachment", CAPTAIN, (s) => s.ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m1/0-photo.png`).delete()],
  ];

  for (const [name, uid, run] of uploads) {
    it(`${name}: a complete account may`, async () => {
      await assertSucceeds(run(st(uid)));
    });
    for (const [label, claims] of Object.entries(incomplete)) {
      it(`${name}: refused for ${label}`, async () => {
        await assertFails(run(st(uid, claims)));
      });
    }
  }

  it("downloads stay open to an incomplete account", async () => {
    await assertSucceeds(st(CAPTAIN, {}).ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m1/0-photo.png`).getMetadata());
  });

  it("a profile picture is part of onboarding: open to an incomplete account, in its own folder only", async () => {
    await assertSucceeds(st(PLAYER, {}).ref(`users/${PLAYER}/profile/avatar.png`).put(bytes(10), png).then());
    await assertFails(st(PLAYER, {}).ref(`users/${OWNER}/profile/avatar.png`).put(bytes(10), png).then());
  });
});
