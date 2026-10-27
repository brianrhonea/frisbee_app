import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  arrayRemove,
  arrayUnion,
  deleteField,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  writeBatch,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

// Run with `npm run test:rules` (starts the Firestore emulator; needs Java).

let env: RulesTestEnvironment;

const TEAM = "team1";
const CODE = "ABC234";
const OWNER = "owner";
const COACH = "coach";
const PLAYER = "player";
const OUTSIDER = "outsider";

const db = (uid: string) => env.authenticatedContext(uid).firestore();

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-frisbee",
    firestore: {
      rules: readFileSync(join(__dirname, "../../../firestore.rules"), "utf8"),
    },
  });
});

afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await setDoc(doc(fs, "teams", TEAM), {
      name: "Team",
      division: "mixed",
      level: "club",
      city: "",
      ownerId: OWNER,
      members: { [OWNER]: "owner", [COACH]: "coach", [PLAYER]: "player" },
      memberIds: [OWNER, COACH, PLAYER],
      memberNames: { [OWNER]: "O", [COACH]: "C", [PLAYER]: "P" },
      inviteCode: CODE,
    });
    await setDoc(doc(fs, "inviteCodes", CODE), { teamId: TEAM });
  });
});

describe("team create", () => {
  it("allows creating a team with a matching invite code", async () => {
    const fs = db(OUTSIDER);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", "t2"), {
      name: "New",
      division: "open",
      level: "college",
      city: "Denver",
      ownerId: OUTSIDER,
      members: { [OUTSIDER]: "owner" },
      memberIds: [OUTSIDER],
      memberNames: { [OUTSIDER]: "Me" },
      inviteCode: "ZZZ999",
    });
    batch.set(doc(fs, "inviteCodes", "ZZZ999"), { teamId: "t2" });
    await assertSucceeds(batch.commit());
  });

  it("rejects reusing an existing invite code", async () => {
    const fs = db(OUTSIDER);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", "t2"), {
      name: "New", division: "open", level: "college", city: "",
      ownerId: OUTSIDER, members: { [OUTSIDER]: "owner" },
      memberIds: [OUTSIDER], memberNames: { [OUTSIDER]: "Me" },
      inviteCode: CODE,
    });
    batch.set(doc(fs, "inviteCodes", CODE), { teamId: "t2" });
    await assertFails(batch.commit());
  });
});

describe("team read", () => {
  it("members can read, outsiders cannot", async () => {
    await assertSucceeds(getDoc(doc(db(PLAYER), "teams", TEAM)));
    await assertFails(getDoc(doc(db(OUTSIDER), "teams", TEAM)));
  });
});

describe("join", () => {
  const joinUpdate = (code: string) => ({
    [`members.${OUTSIDER}`]: "player",
    [`memberNames.${OUTSIDER}`]: "New Player",
    memberIds: arrayUnion(OUTSIDER),
    joinCode: code,
  });

  it("allows joining with the current code", async () => {
    await assertSucceeds(updateDoc(doc(db(OUTSIDER), "teams", TEAM), joinUpdate(CODE)));
  });

  it("rejects a wrong code", async () => {
    await assertFails(updateDoc(doc(db(OUTSIDER), "teams", TEAM), joinUpdate("WRONG1")));
  });

  it("rejects joining as coach", async () => {
    await assertFails(
      updateDoc(doc(db(OUTSIDER), "teams", TEAM), {
        ...joinUpdate(CODE),
        [`members.${OUTSIDER}`]: "coach",
      }),
    );
  });
});

describe("roles and removal", () => {
  it("owner can promote a player; coach cannot", async () => {
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { [`members.${PLAYER}`]: "coach" }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: "coach" }));
  });

  it("nobody can demote the owner", async () => {
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${OWNER}`]: "player" }));
  });

  const removal = (uid: string) => ({
    [`members.${uid}`]: deleteField(),
    [`memberNames.${uid}`]: deleteField(),
    memberIds: arrayRemove(uid),
  });

  it("player can leave", async () => {
    await assertSucceeds(updateDoc(doc(db(PLAYER), "teams", TEAM), removal(PLAYER)));
  });

  it("coach can remove a player but not another coach or the owner", async () => {
    await assertSucceeds(updateDoc(doc(db(COACH), "teams", TEAM), removal(PLAYER)));
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), removal(OWNER)));
  });

  it("player cannot remove others", async () => {
    await assertFails(updateDoc(doc(db(PLAYER), "teams", TEAM), removal(COACH)));
  });
});

describe("roster and plays", () => {
  const play = (uid: string) => ({
    name: "Vert stack",
    category: "offense",
    notes: "",
    elements: [],
    arrows: [],
    updatedBy: uid,
  });

  it("coach can write plays, player cannot", async () => {
    await assertSucceeds(setDoc(doc(db(COACH), "teams", TEAM, "plays", "p1"), play(COACH)));
    await assertFails(setDoc(doc(db(PLAYER), "teams", TEAM, "plays", "p2"), play(PLAYER)));
  });

  it("players can read plays, outsiders cannot", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "plays", "p1"), play(COACH)),
    );
    await assertSucceeds(getDoc(doc(db(PLAYER), "teams", TEAM, "plays", "p1")));
    await assertFails(getDoc(doc(db(OUTSIDER), "teams", TEAM, "plays", "p1")));
  });

  it("validates roster entries", async () => {
    const ref = doc(db(OWNER), "teams", TEAM, "roster", "r1");
    await assertSucceeds(setDoc(ref, { name: "Sam", number: 7, position: "handler", userId: null }));
    await assertFails(setDoc(ref, { name: "Sam", number: 7, position: "goalie", userId: null }));
  });
});

describe("usau cache", () => {
  it("is read-only for clients", async () => {
    await assertSucceeds(getDoc(doc(db(PLAYER), "usau_tournaments", "x")));
    await assertFails(setDoc(doc(db(PLAYER), "usau_tournaments", "x"), { name: "hack" }));
  });
});
