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

// The current Terms version, read from packages/shared (the rules carry it as a literal).
const current = Number(/export const termsVersion = (\d+);/.exec(readFileSync(join(__dirname, "../../../../packages/shared/src/agreements.ts"), "utf8"))?.[1]);

// What a token can carry: email_verified from Auth, ageOk and terms from the API.
const complete = { email_verified: true, ageOk: true, terms: current };
// Incomplete accounts that DO have ageOk: only the email or the Terms are pending.
const adultsPending = {
  unverified: { ageOk: true, terms: current, email_verified: false },
  "no terms": { email_verified: true, ageOk: true },
  "terms 0": { email_verified: true, ageOk: true, terms: 0 },
  "an older Terms version (current - 1)": { email_verified: true, ageOk: true, terms: current - 1 },
  "terms as a string": { email_verified: true, ageOk: true, terms: String(current) },
  "adult with nothing else": { ageOk: true },
};
// Incomplete accounts WITHOUT a valid ageOk (never made it past the age check).
const noAge = {
  "no ageOk": { email_verified: true, terms: current },
  "ageOk false": { email_verified: true, ageOk: false, terms: current },
  "ageOk as a string": { email_verified: true, ageOk: "true", terms: current },
  "ageOk 1": { email_verified: true, ageOk: 1, terms: current },
  "a REST-created account (nothing)": {},
};
const incomplete = { ...adultsPending, ...noAge };

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

describe("the onboarding paths", () => {
  const profileBatch = (db: ReturnType<typeof fs>) =>
    writeBatch(db)
      .set(doc(db, "usernames", "pat.player"), { uid: PLAYER, createdAt: serverTimestamp() })
      .set(doc(db, "profiles", PLAYER), { name: "Pat Player", keywords: ["pat"], photoUrl: null, username: "pat.player", updatedAt: serverTimestamp() }, { merge: true })
      .commit();

  for (const [label, claims] of Object.entries(incomplete)) {
    it(`${label}: users doc, device, notification settings stay open`, async () => {
      const db = fs(PLAYER, claims);
      await assertSucceeds(setDoc(doc(db, "users", PLAYER), { displayName: "Pat", updatedAt: serverTimestamp() }, { merge: true }));
      await assertSucceeds(setDoc(doc(db, "users", PLAYER, "devices", "fid1"), { platform: "iOS", updatedAt: serverTimestamp() }));
      await assertSucceeds(
        setDoc(doc(db, "users", PLAYER, "settings", "notifications"), { categories: { chat: false }, updatedAt: serverTimestamp() }, { merge: true }),
      );
      await assertSucceeds(deleteDoc(doc(db, "users", PLAYER, "devices", "fid1")));
    });
  }

  // F1: the profile and the username need the adult check (ageOk), not the email or Terms.
  for (const [label, claims] of Object.entries(adultsPending)) {
    it(`${label}: an adult may claim a username and publish a profile before the email or Terms are done`, async () => {
      await assertSucceeds(profileBatch(fs(PLAYER, claims)));
      await assertSucceeds(
        setDoc(doc(fs(PLAYER, claims), "profiles", PLAYER, "private", "details"), { bio: "Handler", updatedAt: serverTimestamp() }),
      );
    });
  }

  for (const [label, claims] of Object.entries(noAge)) {
    it(`${label}: no profile, private details or username (F1)`, async () => {
      const db = fs(PLAYER, claims);
      await assertFails(profileBatch(db));
      await assertFails(setDoc(doc(db, "profiles", PLAYER), { name: "Pat Player", keywords: ["pat"], photoUrl: null, updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(db, "profiles", PLAYER, "private", "details"), { bio: "Hi", updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(db, "usernames", "pat.player"), { uid: PLAYER, createdAt: serverTimestamp() }));
    });
    it(`${label}: can't update an existing profile`, async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "profiles", PLAYER), { name: "Pat Player", keywords: ["pat"], photoUrl: null });
      });
      await assertFails(updateDoc(doc(fs(PLAYER, claims), "profiles", PLAYER), { name: "Renamed", keywords: ["x"] }));
    });
    it(`${label}: may still delete its own profile and private details`, async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "profiles", PLAYER), { name: "Pat Player", keywords: ["pat"], photoUrl: null });
        await setDoc(doc(ctx.firestore(), "profiles", PLAYER, "private", "details"), { bio: "x" });
      });
      await assertSucceeds(deleteDoc(doc(fs(PLAYER, claims), "profiles", PLAYER, "private", "details")));
      await assertSucceeds(deleteDoc(doc(fs(PLAYER, claims), "profiles", PLAYER)));
    });
  }

  it("but only their own", async () => {
    const db = fs(PLAYER, {});
    await assertFails(setDoc(doc(db, "users", OWNER, "devices", "fid1"), { platform: "iOS", updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(fs(PLAYER, adultsPending.unverified), "profiles", OWNER), { name: "Not me", keywords: [], photoUrl: null, updatedAt: serverTimestamp() }));
  });

  it("a newer Terms version than the rules' literal is still accepted", async () => {
    await assertSucceeds(
      setDoc(doc(fs(PLAYER, { ...complete, terms: current + 1 }), "users", PLAYER, "follows", `user_${OWNER}`), {
        key: `user_${OWNER}`,
        type: "user",
        targetId: OWNER,
        name: "Olive",
        notify: false,
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("ageRefusals is closed to every client, even a complete account (F3)", async () => {
    await assertFails(getDoc(doc(fs(PLAYER), "ageRefusals", PLAYER)));
    await assertFails(setDoc(doc(fs(PLAYER), "ageRefusals", PLAYER), { ciphertext: "x" }));
    await assertFails(deleteDoc(doc(fs(PLAYER), "ageRefusals", PLAYER)));
  });
});

describe("profile pictures can only point at this app's own Storage (F5)", () => {
  const bucket = "frisbee-app-brianrhonea-dev.firebasestorage.app";
  const own = (uid: string, file = "avatar.jpg") =>
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/users%2F${uid}%2Fprofile%2F${file}?alt=media&token=abc-123`;
  const card = (extra: Record<string, unknown>) => ({ name: "Pat Player", keywords: ["pat"], updatedAt: serverTimestamp(), ...extra });
  const write = (extra: Record<string, unknown>) => setDoc(doc(fs(PLAYER), "profiles", PLAYER), card(extra));

  it("accepts null, empty, the player's own download URL (dev and production buckets) and a Google account photo", async () => {
    await assertSucceeds(write({ photoUrl: null }));
    await assertSucceeds(write({ photoUrl: "" }));
    await assertSucceeds(write({ photoUrl: own(PLAYER), headerUrl: own(PLAYER, "header.png") }));
    await assertSucceeds(write({ photoUrl: own(PLAYER).replace("-dev.firebasestorage.app", ".firebasestorage.app") }));
    await assertSucceeds(write({ photoUrl: own(PLAYER).replace("firebasestorage.app", "appspot.com") }));
    await assertSucceeds(write({ photoUrl: "https://lh3.googleusercontent.com/a/ACg8oc=s96-c" }));
  });

  it.each([
    ["a tracking server", "https://evil.example/pixel.gif"],
    ["plain http", own(PLAYER).replace("https:", "http:")],
    ["someone else's profile folder", own(OWNER)],
    ["a different folder of their own", own(PLAYER).replace("%2Fprofile%2F", "%2Fposts%2F")],
    ["another project's bucket", own(PLAYER).replace(bucket, "someone-elses-project.firebasestorage.app")],
    ["a look-alike host", own(PLAYER).replace("firebasestorage.googleapis.com", "firebasestorage.googleapis.com.evil.example")],
    ["a javascript URL", "javascript:alert(1)"],
  ])("refuses a photoUrl or headerUrl pointing at %s", async (_, url) => {
    await assertFails(write({ photoUrl: url }));
    await assertFails(write({ photoUrl: null, headerUrl: url }));
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

  for (const [label, claims] of Object.entries(adultsPending)) {
    it(`${label}: a profile picture is part of onboarding, in its own folder only`, async () => {
      await assertSucceeds(st(PLAYER, claims).ref(`users/${PLAYER}/profile/avatar.png`).put(bytes(10), png).then());
      await assertFails(st(PLAYER, claims).ref(`users/${OWNER}/profile/avatar.png`).put(bytes(10), png).then());
    });
  }

  for (const [label, claims] of Object.entries(noAge)) {
    it(`${label}: no profile picture without ageOk (F1), but it may delete its own`, async () => {
      await assertFails(st(PLAYER, claims).ref(`users/${PLAYER}/profile/avatar.png`).put(bytes(10), png).then());
      await env.withSecurityRulesDisabled(async (ctx) => {
        await ctx.storage().ref(`users/${PLAYER}/profile/old.png`).put(bytes(10), png);
      });
      await assertSucceeds(st(PLAYER, claims).ref(`users/${PLAYER}/profile/old.png`).delete());
    });
  }

  // F5: the API marks photos it screened with `stall10Checked`; a client can't forge the mark.
  describe("the API's screening mark can't be forged by a client", () => {
    const marked = { contentType: "image/png", customMetadata: { stall10Checked: "api" } };
    const kinds: Array<[string, string, (s: ReturnType<typeof st>) => Promise<unknown>]> = [
      ["a profile picture", PLAYER, (s) => s.ref(`users/${PLAYER}/profile/forged.png`).put(bytes(10), marked).then()],
      ["a chat attachment", CAPTAIN, (s) => s.ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m2/0-forged.png`).put(bytes(10), marked).then()],
      ["a direct-message attachment", PLAYER, (s) => s.ref(`conversations/${CONV}/${PLAYER}/m1/0-forged.png`).put(bytes(10), marked).then()],
      ["a team post photo", COACH, (s) => s.ref(`teams/${TEAM}/posts/p1/1/0-forged.png`).put(bytes(10), marked).then()],
      ["a team video", COACH, (s) => s.ref(`teams/${TEAM}/videos/v1/forged.mp4`).put(bytes(10), { contentType: "video/mp4", customMetadata: { stall10Checked: "api" } }).then()],
      ["a post photo", PLAYER, (s) => s.ref(`users/${PLAYER}/posts/p1/1/0-forged.png`).put(bytes(10), marked).then()],
    ];
    for (const [name, uid, run] of kinds) {
      it(`${name} with the mark is refused`, async () => {
        await assertFails(run(st(uid)));
      });
    }
    it("the same upload without the mark, or with other metadata, is accepted", async () => {
      await assertSucceeds(st(PLAYER).ref(`users/${PLAYER}/profile/fine.png`).put(bytes(10), png).then());
      await assertSucceeds(st(PLAYER).ref(`users/${PLAYER}/profile/fine2.png`).put(bytes(10), { contentType: "image/png", customMetadata: { note: "x" } }).then());
    });
    it("adding the mark to an existing file by a metadata update is refused too", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await ctx.storage().ref(`users/${PLAYER}/profile/mine.png`).put(bytes(10), png);
      });
      await assertFails(st(PLAYER).ref(`users/${PLAYER}/profile/mine.png`).updateMetadata({ customMetadata: { stall10Checked: "api" } }));
      await assertSucceeds(st(PLAYER).ref(`users/${PLAYER}/profile/mine.png`).updateMetadata({ customMetadata: { note: "x" } }));
    });
  });
});
