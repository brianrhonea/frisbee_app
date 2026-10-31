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
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

// Run with `npm run test:rules` (starts the Firestore emulator; needs Java).

let env: RulesTestEnvironment;

const TEAM = "team1";
const CODE = "ABC234";
const OWNER = "owner";
const COACH = "coach";
const CAPTAIN = "captain";
const STATS = "stats";
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
      members: {
        [OWNER]: "owner",
        [COACH]: "coach",
        [CAPTAIN]: "captain",
        [STATS]: "player",
        [PLAYER]: "player",
      },
      statKeepers: [STATS],
      memberIds: [OWNER, COACH, CAPTAIN, STATS, PLAYER],
      memberNames: { [OWNER]: "O", [COACH]: "C", [CAPTAIN]: "K", [STATS]: "S", [PLAYER]: "P" },
    });
    await setDoc(doc(fs, "teams", TEAM, "private", "invite"), { code: CODE });
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
    });
    batch.set(doc(fs, "teams", "t2", "private", "invite"), { code: "ZZZ999" });
    batch.set(doc(fs, "inviteCodes", "ZZZ999"), { teamId: "t2" });
    await assertSucceeds(batch.commit());
  });

  it("rejects a team that keeps its invite code on the team doc", async () => {
    const fs = db(OUTSIDER);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", "t2"), {
      name: "New", division: "open", level: "college", city: "",
      ownerId: OUTSIDER, members: { [OUTSIDER]: "owner" },
      memberIds: [OUTSIDER], memberNames: { [OUTSIDER]: "Me" },
      inviteCode: "ZZZ999",
    });
    batch.set(doc(fs, "teams", "t2", "private", "invite"), { code: "ZZZ999" });
    batch.set(doc(fs, "inviteCodes", "ZZZ999"), { teamId: "t2" });
    await assertFails(batch.commit());
  });

  it("rejects reusing an existing invite code", async () => {
    const fs = db(OUTSIDER);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", "t2"), {
      name: "New", division: "open", level: "college", city: "",
      ownerId: OUTSIDER, members: { [OUTSIDER]: "owner" },
      memberIds: [OUTSIDER], memberNames: { [OUTSIDER]: "Me" },
    });
    batch.set(doc(fs, "teams", "t2", "private", "invite"), { code: CODE });
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
  const joinUpdate = {
    [`members.${OUTSIDER}`]: "player",
    [`memberNames.${OUTSIDER}`]: "New Player",
    memberIds: arrayUnion(OUTSIDER),
  };
  const join = (code: string, update: Record<string, unknown> = joinUpdate, uid = OUTSIDER) => {
    const fs = db(uid);
    return writeBatch(fs)
      .set(doc(fs, "teams", TEAM, "joins", uid), { code })
      .update(doc(fs, "teams", TEAM), update)
      .commit();
  };

  it("allows joining with the current code", async () => {
    await assertSucceeds(join(CODE));
  });

  it("rejects a wrong code or no proof", async () => {
    await assertFails(join("WRONG1"));
    await assertFails(updateDoc(doc(db(OUTSIDER), "teams", TEAM), joinUpdate));
  });

  it("rejects putting the code on the team doc", async () => {
    await assertFails(join(CODE, { ...joinUpdate, joinCode: CODE }));
  });

  it("rejects joining as coach", async () => {
    await assertFails(join(CODE, { ...joinUpdate, [`members.${OUTSIDER}`]: "coach" }));
  });

  it("join proofs are private to the joiner", async () => {
    await assertSucceeds(join(CODE));
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "teams", TEAM, "joins", OUTSIDER)));
    await assertFails(getDoc(doc(db(PLAYER), "teams", TEAM, "joins", OUTSIDER)));
    await assertFails(getDoc(doc(db(COACH), "teams", TEAM, "joins", OUTSIDER)));
    await assertFails(setDoc(doc(db(PLAYER), "teams", TEAM, "joins", OUTSIDER), { code: "X" }));
  });

  it("older teams with the code on the team doc still accept joins", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), "teams", TEAM, "private", "invite"));
      await updateDoc(doc(ctx.firestore(), "teams", TEAM), { inviteCode: CODE });
    });
    await assertFails(join("WRONG1"));
    await assertSucceeds(join(CODE));
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
    statKeepers: arrayRemove(uid),
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

  it("only the owner sets roles, to any non-owner role", async () => {
    for (const role of ["coach", "captain", "player"]) {
      await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: role }));
    }
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: "owner" }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: "stats" }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: "admin" }));
    await assertFails(updateDoc(doc(db(CAPTAIN), "teams", TEAM), { [`members.${PLAYER}`]: "coach" }));
    await assertFails(updateDoc(doc(db(STATS), "teams", TEAM), { [`members.${PLAYER}`]: "coach" }));
  });

  it("only the owner gives stats access, and only to members", async () => {
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { statKeepers: arrayUnion(PLAYER) }));
    await assertFails(updateDoc(doc(db(STATS), "teams", TEAM), { statKeepers: arrayUnion(PLAYER) }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { statKeepers: arrayUnion(OUTSIDER) }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { statKeepers: arrayUnion(PLAYER) }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { statKeepers: arrayRemove(STATS) }));
  });

  it("captains remove players (with their stats access), not coaches", async () => {
    await assertSucceeds(updateDoc(doc(db(CAPTAIN), "teams", TEAM), removal(STATS)));
    await assertFails(updateDoc(doc(db(CAPTAIN), "teams", TEAM), removal(COACH)));
    await assertSucceeds(updateDoc(doc(db(COACH), "teams", TEAM), removal(PLAYER)));
  });

  it("removing a stats keeper must drop their stats access", async () => {
    const { statKeepers: _, ...keepAccess } = removal(STATS);
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), keepAccess));
  });

  it("stats keepers cannot remove anyone", async () => {
    await assertFails(updateDoc(doc(db(STATS), "teams", TEAM), removal(PLAYER)));
  });

  const transfer = (to: string) => ({
    ownerId: to,
    [`members.${to}`]: "owner",
    [`members.${OWNER}`]: "player",
  });

  it("owner can transfer ownership and becomes a player", async () => {
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), {
      ownerId: COACH,
      [`members.${COACH}`]: "owner",
      [`members.${OWNER}`]: "player",
    }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), {
      ...transfer(COACH),
      [`members.${OWNER}`]: "coach",
    }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), transfer(OUTSIDER)));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), transfer(COACH)));
    // The new owner has full control; the old one doesn't.
    await assertSucceeds(updateDoc(doc(db(COACH), "teams", TEAM), { [`members.${PLAYER}`]: "captain" }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: "coach" }));
  });
});

describe("invite codes and admin", () => {
  const invite = (uid: string) => doc(db(uid), "teams", TEAM, "private", "invite");
  const regenerate = (uid: string) => {
    const fs = db(uid);
    return writeBatch(fs)
      .set(doc(fs, "teams", TEAM, "private", "invite"), { code: "NEW777" })
      .set(doc(fs, "inviteCodes", "NEW777"), { teamId: TEAM })
      .delete(doc(fs, "inviteCodes", CODE))
      .commit();
  };

  it("only owners, coaches and captains can read the invite code", async () => {
    for (const uid of [OWNER, COACH, CAPTAIN]) {
      await assertSucceeds(getDoc(invite(uid)));
    }
    for (const uid of [PLAYER, STATS, OUTSIDER]) {
      await assertFails(getDoc(invite(uid)));
    }
  });

  it("only the owner generates a new invite code", async () => {
    await assertFails(regenerate(COACH));
    await assertFails(regenerate(CAPTAIN));
    await assertFails(regenerate(PLAYER));
    await assertSucceeds(regenerate(OWNER));
  });

  it("codes can't point at a code the team doesn't own", async () => {
    await assertFails(setDoc(invite(OWNER), { code: "NOPE22" }));
    await assertFails(setDoc(doc(db(OWNER), "inviteCodes", "NOPE22"), { teamId: TEAM }));
  });

  it("admins move an older team's code off the team doc", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), "teams", TEAM, "private", "invite"));
      await updateDoc(doc(ctx.firestore(), "teams", TEAM), { inviteCode: CODE, joinCode: CODE });
    });
    const move = (uid: string) => {
      const fs = db(uid);
      return writeBatch(fs)
        .set(doc(fs, "teams", TEAM, "private", "invite"), { code: CODE })
        .update(doc(fs, "teams", TEAM), { inviteCode: deleteField(), joinCode: deleteField() })
        .commit();
    };
    await assertFails(move(PLAYER));
    await assertSucceeds(move(CAPTAIN));
  });

  it("captains and coaches manage the team; stats keepers and players cannot", async () => {
    const edit = (uid: string) => updateDoc(doc(db(uid), "teams", TEAM), { city: "Seattle" });
    await assertSucceeds(edit(COACH));
    await assertSucceeds(edit(CAPTAIN));
    await assertFails(edit(STATS));
    await assertFails(edit(PLAYER));
    const roster = (uid: string) =>
      setDoc(doc(db(uid), "teams", TEAM, "roster", uid), { name: "Sam", number: 7, position: "handler", userId: null });
    await assertSucceeds(roster(CAPTAIN));
    await assertFails(roster(STATS));
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
    await assertFails(setDoc(ref, { name: "Sam", number: 7, position: "handler", userId: null, memberId: "123" }));
  });

  it("roster entries can't carry paid or USA Ultimate status", async () => {
    const ref = doc(db(OWNER), "teams", TEAM, "roster", "r1");
    await assertFails(setDoc(ref, { name: "Sam", number: 7, position: "handler", userId: null, paid: true }));
    await assertFails(setDoc(ref, { name: "Sam", number: 7, position: "handler", userId: null, onUsau: true }));
  });

  it("admins can strip legacy status from roster entries", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "roster", "r1"), {
        name: "Sam", number: 7, position: "handler", userId: null, onUsau: true, paid: true,
      }),
    );
    const strip = { onUsau: deleteField(), paid: deleteField() };
    await assertFails(updateDoc(doc(db(PLAYER), "teams", TEAM, "roster", "r1"), strip));
    await assertSucceeds(updateDoc(doc(db(COACH), "teams", TEAM, "roster", "r1"), strip));
  });
});

describe("roster status", () => {
  const status = (uid: string) => doc(db(uid), "teams", TEAM, "rosterStatus", "r1");

  beforeEach(() =>
    env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "rosterStatus", "r1"), { onUsau: true, paid: false }),
    ),
  );

  it("only owners, coaches and captains can read it", async () => {
    for (const uid of [OWNER, COACH, CAPTAIN]) {
      await assertSucceeds(getDoc(status(uid)));
    }
    for (const uid of [PLAYER, STATS, OUTSIDER]) {
      await assertFails(getDoc(status(uid)));
    }
  });

  it("players can't list it", async () => {
    await assertFails(getDocs(collection(db(PLAYER), "teams", TEAM, "rosterStatus")));
    await assertSucceeds(getDocs(collection(db(CAPTAIN), "teams", TEAM, "rosterStatus")));
  });

  it("only admins write it, with valid fields", async () => {
    await assertSucceeds(setDoc(status(CAPTAIN), { onUsau: false, paid: true }));
    await assertSucceeds(setDoc(status(OWNER), { onUsau: null, paid: false }));
    await assertFails(setDoc(status(PLAYER), { onUsau: true, paid: true }));
    await assertFails(setDoc(status(STATS), { onUsau: true, paid: true }));
    await assertFails(setDoc(status(COACH), { onUsau: true, paid: "yes" }));
    await assertFails(setDoc(status(COACH), { paid: true, note: "cash" }));
    await assertFails(deleteDoc(status(PLAYER)));
    await assertSucceeds(deleteDoc(status(COACH)));
  });
});

describe("USA Ultimate link", () => {
  const url = "https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc%3d";

  it("admins link the team page; players and other sites cannot", async () => {
    await assertFails(updateDoc(doc(db(PLAYER), "teams", TEAM), { usauUrl: url, usauName: "Ring" }));
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { usauUrl: "https://evil.example/x" }));
    await assertSucceeds(updateDoc(doc(db(CAPTAIN), "teams", TEAM), { usauUrl: url, usauName: "Ring" }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { usauUrl: null, usauName: null, usauSyncedAt: null }));
  });

  it("a sync stamps the server time with the roster writes", async () => {
    const fs = db(COACH);
    await assertSucceeds(
      writeBatch(fs)
        .update(doc(fs, "teams", TEAM), { usauSyncedAt: serverTimestamp() })
        .set(doc(fs, "teams", TEAM, "roster", "r9"), { name: "New", number: 12, position: "hybrid", userId: null })
        .set(doc(fs, "teams", TEAM, "rosterStatus", "r9"), { onUsau: true, paid: false })
        .commit(),
    );
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { usauSyncedAt: new Date(2020, 1, 1) }));
  });
});

describe("events", () => {
  const event = (uid: string, extra: Record<string, unknown> = {}) => ({
    title: "Practice",
    type: "practice",
    startsAt: new Date("2026-11-02T18:00:00Z"),
    endsAt: null,
    location: "",
    notes: "",
    poll: {
      question: "Jerseys?",
      options: [{ id: "a", text: "Dark" }, { id: "b", text: "Light" }],
      multiple: false,
    },
    rsvps: {},
    reactions: {},
    votes: {},
    createdBy: uid,
    ...extra,
  });
  const ev = (uid: string) => doc(db(uid), "teams", TEAM, "events", "e1");
  const seed = () =>
    env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "events", "e1"), event(COACH)),
    );

  it("coach can create events, player and outsider cannot", async () => {
    await assertSucceeds(setDoc(ev(COACH), event(COACH)));
    await assertFails(setDoc(doc(db(PLAYER), "teams", TEAM, "events", "e2"), event(PLAYER)));
    await assertFails(setDoc(doc(db(OUTSIDER), "teams", TEAM, "events", "e3"), event(OUTSIDER)));
  });

  it("accepts every event type and rejects unknown ones", async () => {
    for (const type of ["practice", "game", "tournament", "scrimmage", "workout", "social", "other"]) {
      await assertSucceeds(setDoc(doc(db(COACH), "teams", TEAM, "events", `t-${type}`), event(COACH, { type })));
    }
    await assertFails(setDoc(doc(db(COACH), "teams", TEAM, "events", "t-bogus"), event(COACH, { type: "bogus" })));
  });

  it("rejects events created with pre-filled responses", async () => {
    await assertFails(setDoc(ev(COACH), event(COACH, { rsvps: { [PLAYER]: "going" } })));
  });

  it("members can RSVP, react and vote for themselves only", async () => {
    await seed();
    await assertSucceeds(updateDoc(ev(PLAYER), { [`rsvps.${PLAYER}`]: "going" }));
    await assertSucceeds(updateDoc(ev(PLAYER), { [`reactions.${PLAYER}`]: arrayUnion("fire") }));
    await assertSucceeds(updateDoc(ev(PLAYER), { [`votes.${PLAYER}`]: ["a"] }));
    await assertFails(updateDoc(ev(PLAYER), { [`rsvps.${COACH}`]: "notGoing" }));
    await assertFails(updateDoc(ev(OUTSIDER), { [`rsvps.${OUTSIDER}`]: "going" }));
  });

  it("only attendees can react or vote", async () => {
    await seed();
    await assertFails(updateDoc(ev(PLAYER), { [`reactions.${PLAYER}`]: arrayUnion("fire") }));
    await assertSucceeds(updateDoc(ev(PLAYER), { [`rsvps.${PLAYER}`]: "maybe" }));
    await assertFails(updateDoc(ev(PLAYER), { [`votes.${PLAYER}`]: ["a"] }));
  });

  it("leaving 'going' must drop reactions and votes", async () => {
    await seed();
    await updateDoc(ev(PLAYER), { [`rsvps.${PLAYER}`]: "going" });
    await updateDoc(ev(PLAYER), { [`reactions.${PLAYER}`]: arrayUnion("fire") });
    await assertFails(updateDoc(ev(PLAYER), { [`rsvps.${PLAYER}`]: "notGoing" }));
    await assertSucceeds(
      updateDoc(ev(PLAYER), {
        [`rsvps.${PLAYER}`]: "notGoing",
        [`reactions.${PLAYER}`]: deleteField(),
        [`votes.${PLAYER}`]: deleteField(),
      }),
    );
  });

  it("validates response values", async () => {
    await seed();
    await updateDoc(ev(PLAYER), { [`rsvps.${PLAYER}`]: "going" });
    await assertFails(updateDoc(ev(PLAYER), { [`rsvps.${PLAYER}`]: "yes" }));
    await assertFails(updateDoc(ev(PLAYER), { [`reactions.${PLAYER}`]: ["skull"] }));
    // Single-choice poll.
    await assertFails(updateDoc(ev(PLAYER), { [`votes.${PLAYER}`]: ["a", "b"] }));
  });

  it("players cannot edit details; coaches can but cannot forge votes", async () => {
    await seed();
    await assertFails(updateDoc(ev(PLAYER), { title: "Cancelled" }));
    await assertSucceeds(updateDoc(ev(COACH), { title: "Track workout" }));
    await assertSucceeds(updateDoc(ev(COACH), { poll: null, votes: {} }));
    await assertFails(updateDoc(ev(COACH), { votes: { [PLAYER]: ["a"] } }));
  });

  it("players cannot delete events", async () => {
    await seed();
    await assertFails(deleteDoc(ev(PLAYER)));
    await assertSucceeds(deleteDoc(ev(COACH)));
  });
});

describe("personal events", () => {
  const mine = (extra: Record<string, unknown> = {}) => ({
    title: "Track workout",
    type: "workout",
    startsAt: new Date("2026-11-02T07:00:00Z"),
    endsAt: null,
    location: "",
    notes: "",
    poll: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  });
  const ref = (as: string, owner = PLAYER) => doc(db(as), "users", owner, "events", "m1");

  it("only the owner can create, read, edit and delete", async () => {
    await assertSucceeds(setDoc(ref(PLAYER), mine()));
    await assertSucceeds(getDoc(ref(PLAYER)));
    await assertSucceeds(updateDoc(ref(PLAYER), { title: "Pickup", type: "other" }));
    await assertFails(getDoc(ref(COACH)));
    await assertFails(updateDoc(ref(OWNER), { title: "Hijack" }));
    await assertFails(deleteDoc(ref(OUTSIDER)));
    await assertSucceeds(deleteDoc(ref(PLAYER)));
  });

  it("validates details and rejects polls and responses", async () => {
    await assertFails(setDoc(ref(PLAYER), mine({ title: "" })));
    await assertFails(setDoc(ref(PLAYER), mine({ type: "bogus" })));
    await assertFails(setDoc(ref(PLAYER), mine({ rsvps: {} })));
    await assertFails(
      setDoc(ref(PLAYER), mine({ poll: { question: "?", options: [{ id: "a", text: "A" }, { id: "b", text: "B" }], multiple: false } })),
    );
  });
});

describe("public events", () => {
  const details = (extra: Record<string, unknown> = {}) => ({
    title: "Open tryouts",
    type: "other",
    startsAt: new Date("2026-11-07T15:00:00Z"),
    endsAt: null,
    location: "Central Park",
    notes: "",
    updatedAt: serverTimestamp(),
    ...extra,
  });
  const pub = (uid: string) => doc(db(uid), "teams", TEAM, "publicEvents", "e1");

  it("editors mark an event public and write its public copy", async () => {
    const fs = db(COACH);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", TEAM, "events", "e1"), {
      ...details(),
      poll: null,
      public: true,
      rsvps: {},
      reactions: {},
      votes: {},
      createdBy: COACH,
      createdAt: serverTimestamp(),
    });
    batch.set(doc(fs, "teams", TEAM, "publicEvents", "e1"), details());
    await assertSucceeds(batch.commit());
    await assertSucceeds(updateDoc(doc(fs, "teams", TEAM, "events", "e1"), { public: false }));
    await assertSucceeds(deleteDoc(pub(COACH)));
  });

  it("players and outsiders cannot write public copies", async () => {
    await assertFails(setDoc(pub(PLAYER), details()));
    await assertFails(setDoc(pub(OUTSIDER), details()));
  });

  it("public copies hold details only", async () => {
    await assertFails(setDoc(pub(COACH), details({ rsvps: {} })));
    await assertFails(setDoc(pub(COACH), details({ title: "" })));
  });

  it("anyone signed in can read public copies, not the events", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "publicEvents", "e1"), details()),
    );
    await assertSucceeds(getDoc(pub(OUTSIDER)));
    await assertSucceeds(getDocs(collection(db(OUTSIDER), "teams", TEAM, "publicEvents")));
    await assertFails(getDocs(collection(db(OUTSIDER), "teams", TEAM, "events")));
    await assertFails(
      getDoc(doc(env.unauthenticatedContext().firestore(), "teams", TEAM, "publicEvents", "e1")),
    );
  });

  it("personal events cannot be public", async () => {
    await assertFails(
      setDoc(doc(db(PLAYER), "users", PLAYER, "events", "m1"), {
        ...details(),
        poll: null,
        public: true,
        createdAt: serverTimestamp(),
      }),
    );
  });
});

describe("posts", () => {
  const post = (uid: string, extra: Record<string, unknown> = {}) => ({
    title: "Tryouts",
    body: "Saturday at 10.",
    public: true,
    authorId: uid,
    authorName: "C",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  });
  const ref = (uid: string, id = "p1") => doc(db(uid), "teams", TEAM, "posts", id);
  const seed = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", TEAM, "posts", "pub"), { ...post(COACH), createdAt: new Date() });
      await setDoc(doc(fs, "teams", TEAM, "posts", "priv"), {
        ...post(COACH),
        public: false,
        createdAt: new Date(),
      });
    });

  it("owners, coaches and captains post; players and outsiders cannot", async () => {
    await assertSucceeds(setDoc(ref(OWNER, "a"), post(OWNER)));
    await assertSucceeds(setDoc(ref(COACH, "b"), post(COACH)));
    await assertSucceeds(setDoc(ref(CAPTAIN, "c"), post(CAPTAIN, { public: false })));
    await assertFails(setDoc(ref(PLAYER, "d"), post(PLAYER)));
    await assertFails(setDoc(ref(OUTSIDER, "e"), post(OUTSIDER)));
  });

  it("validates posts and their author", async () => {
    await assertFails(setDoc(ref(COACH), post(OWNER)));
    await assertFails(setDoc(ref(COACH), post(COACH, { body: "" })));
    await assertFails(setDoc(ref(COACH), post(COACH, { public: "yes" })));
    await assertFails(setDoc(ref(COACH), post(COACH, { pinned: true })));
    await assertFails(setDoc(ref(COACH), post(COACH, { createdAt: new Date("2020-01-01") })));
  });

  it("posts may have a place, up to 5 web links and 4 photos", async () => {
    const image = { path: "p/0-a.png", name: "a.png", contentType: "image/png", size: 3 };
    await assertSucceeds(
      setDoc(ref(COACH, "f"), post(COACH, {
        location: "Wash Park",
        links: ["https://example.com", "http://x.org/a"],
        images: [image],
      })),
    );
    // A photo alone is enough.
    await assertSucceeds(setDoc(ref(COACH, "g"), post(COACH, { body: "", images: [image] })));
    await assertFails(setDoc(ref(COACH, "h"), post(COACH, { links: ["javascript:alert(1)"] })));
    await assertFails(
      setDoc(ref(COACH, "i"), post(COACH, { links: Array(6).fill("https://example.com") })),
    );
    await assertFails(setDoc(ref(COACH, "j"), post(COACH, { images: Array(5).fill(image) })));
    await assertFails(setDoc(ref(COACH, "k"), post(COACH, { location: "x".repeat(201) })));
  });

  it("members read every post; others only public ones", async () => {
    await seed();
    await assertSucceeds(getDocs(collection(db(PLAYER), "teams", TEAM, "posts")));
    await assertSucceeds(getDoc(ref(PLAYER, "priv")));
    await assertSucceeds(getDoc(ref(OUTSIDER, "pub")));
    await assertFails(getDoc(ref(OUTSIDER, "priv")));
    await assertFails(getDocs(collection(db(OUTSIDER), "teams", TEAM, "posts")));
    await assertSucceeds(
      getDocs(query(collection(db(OUTSIDER), "teams", TEAM, "posts"), where("public", "==", true))),
    );
  });

  it("editors edit content and visibility only, and delete", async () => {
    await seed();
    await assertSucceeds(
      updateDoc(ref(CAPTAIN, "pub"), { body: "Moved to 11.", public: false, updatedAt: serverTimestamp() }),
    );
    await assertFails(updateDoc(ref(CAPTAIN, "pub"), { authorId: CAPTAIN }));
    await assertFails(updateDoc(ref(PLAYER, "pub"), { body: "Hijack" }));
    await assertFails(deleteDoc(ref(PLAYER, "pub")));
    await assertSucceeds(deleteDoc(ref(OWNER, "pub")));
  });
});

describe("videos", () => {
  const video = (uid: string, extra: Record<string, unknown> = {}) => ({
    youtubeId: "dQw4w9WgXcQ",
    title: "Film review",
    description: "",
    authorId: uid,
    authorName: "C",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  });
  const ref = (uid: string, id = "v1") => doc(db(uid), "teams", TEAM, "videos", id);
  const seed = () =>
    env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "videos", "v1"), {
        ...video(COACH),
        createdAt: new Date(),
        updatedAt: new Date(),
      }),
    );

  it("owners, coaches and captains share videos; players and outsiders cannot", async () => {
    await assertSucceeds(setDoc(ref(OWNER, "a"), video(OWNER)));
    await assertSucceeds(setDoc(ref(COACH, "b"), video(COACH)));
    await assertSucceeds(setDoc(ref(CAPTAIN, "c"), video(CAPTAIN)));
    await assertFails(setDoc(ref(PLAYER, "d"), video(PLAYER)));
    await assertFails(setDoc(ref(OUTSIDER, "e"), video(OUTSIDER)));
  });

  it("stores only a YouTube video id, a title and a description", async () => {
    await assertFails(setDoc(ref(COACH), video(OWNER)));
    await assertFails(setDoc(ref(COACH), video(COACH, { youtubeId: "https://evil.example/x" })));
    await assertFails(setDoc(ref(COACH), video(COACH, { youtubeId: "short" })));
    await assertFails(setDoc(ref(COACH), video(COACH, { title: "" })));
    await assertFails(setDoc(ref(COACH), video(COACH, { title: "x".repeat(101) })));
    await assertFails(setDoc(ref(COACH), video(COACH, { description: "x".repeat(2001) })));
    await assertFails(setDoc(ref(COACH), video(COACH, { url: "https://youtu.be/dQw4w9WgXcQ" })));
    await assertFails(setDoc(ref(COACH), video(COACH, { createdAt: new Date("2020-01-01") })));
  });

  it("uploads record an MP4 under the video's own path, up to 500 MB", async () => {
    const file = (extra: Record<string, unknown> = {}) => ({
      path: `teams/${TEAM}/videos/f1/tryouts.mp4`,
      name: "tryouts.mp4",
      size: 120 * 1024 * 1024,
      contentType: "video/mp4",
      ...extra,
    });
    const upload = (f: Record<string, unknown>, extra: Record<string, unknown> = {}) =>
      video(COACH, { youtubeId: "", file: f, ...extra });
    await assertSucceeds(setDoc(ref(COACH, "f1"), upload(file())));
    await assertFails(setDoc(ref(COACH, "f2"), upload(file())));
    await assertFails(setDoc(ref(COACH, "f1"), upload(file({ size: 501 * 1024 * 1024 }))));
    await assertFails(setDoc(ref(COACH, "f1"), upload(file({ contentType: "application/pdf" }))));
    await assertSucceeds(
      setDoc(ref(COACH, "f3"), upload(file({ name: "s.mkv", path: `teams/${TEAM}/videos/f3/s.mkv`, contentType: "video/x-matroska" }))),
    );
    await assertFails(setDoc(ref(COACH, "f1"), upload(file({ url: "https://x" }))));
    await assertFails(setDoc(ref(COACH, "f1"), upload(file(), { youtubeId: "dQw4w9WgXcQ" })));
    await assertFails(setDoc(ref(PLAYER, "f1"), video(PLAYER, { youtubeId: "", file: file() })));
  });

  it("an upload's file can't be swapped after it's shared", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "videos", "f1"), {
        ...video(COACH, {
          youtubeId: "",
          file: { path: `teams/${TEAM}/videos/f1/a.mp4`, name: "a.mp4", size: 10, contentType: "video/mp4" },
        }),
        createdAt: new Date(),
        updatedAt: new Date(),
      }),
    );
    await assertSucceeds(updateDoc(ref(COACH, "f1"), { title: "Renamed", updatedAt: serverTimestamp() }));
    await assertFails(
      updateDoc(ref(COACH, "f1"), { "file.size": 1, updatedAt: serverTimestamp() }),
    );
  });

  it("members watch; outsiders see nothing", async () => {
    await seed();
    await assertSucceeds(getDocs(collection(db(PLAYER), "teams", TEAM, "videos")));
    await assertSucceeds(getDoc(ref(PLAYER)));
    await assertFails(getDoc(ref(OUTSIDER)));
    await assertFails(getDocs(collection(db(OUTSIDER), "teams", TEAM, "videos")));
  });

  it("editors change the link, title and description, and remove videos", async () => {
    await seed();
    await assertSucceeds(
      updateDoc(ref(CAPTAIN), { title: "Film review, week 2", youtubeId: "abcdefghijk", updatedAt: serverTimestamp() }),
    );
    await assertFails(updateDoc(ref(CAPTAIN), { authorId: CAPTAIN, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(PLAYER), { title: "Hijack", updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(ref(PLAYER)));
    await assertSucceeds(deleteDoc(ref(CAPTAIN)));
  });
});

describe("video folders", () => {
  const ref = (uid: string, id = "f1") => doc(db(uid), "teams", TEAM, "videoFolders", id);
  const folder = (name = "Game film") => ({ name, createdAt: serverTimestamp() });
  const video = (ctx: string, extra: Record<string, unknown> = {}) => ({
    youtubeId: "dQw4w9WgXcQ",
    title: "Film review",
    description: "",
    authorId: ctx,
    authorName: "C",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  });

  it("owners, coaches and captains make folders; members see them", async () => {
    await assertSucceeds(setDoc(ref(COACH), folder()));
    await assertSucceeds(setDoc(ref(CAPTAIN, "f2"), folder("Highlights")));
    await assertFails(setDoc(ref(PLAYER, "f3"), folder()));
    await assertFails(setDoc(ref(COACH, "f4"), folder("")));
    await assertFails(setDoc(ref(COACH, "f5"), folder("x".repeat(41))));
    await assertFails(setDoc(ref(COACH, "f6"), { ...folder(), color: "red" }));
    await assertSucceeds(getDoc(ref(PLAYER)));
    await assertFails(getDoc(ref(OUTSIDER)));
  });

  it("editors rename and delete folders", async () => {
    await assertSucceeds(setDoc(ref(COACH), folder()));
    await assertSucceeds(updateDoc(ref(CAPTAIN), { name: "Games" }));
    await assertFails(updateDoc(ref(PLAYER), { name: "Mine" }));
    await assertFails(updateDoc(ref(CAPTAIN), { createdAt: new Date("2020-01-01") }));
    await assertFails(deleteDoc(ref(PLAYER)));
    await assertSucceeds(deleteDoc(ref(OWNER)));
  });

  it("videos are filed by folder id", async () => {
    const v = (uid: string) => doc(db(uid), "teams", TEAM, "videos", "v1");
    await assertSucceeds(setDoc(v(COACH), video(COACH, { folderId: "f1" })));
    await assertSucceeds(updateDoc(v(CAPTAIN), { folderId: "", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(v(PLAYER), { folderId: "f1", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(v(CAPTAIN), { folderId: 7, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(v(CAPTAIN), { folderId: "x".repeat(41), updatedAt: serverTimestamp() }));
  });
});

describe("team directory", () => {
  const listing = (extra: Record<string, unknown> = {}) => ({
    name: "Team",
    division: "mixed",
    level: "club",
    city: "",
    keywords: ["t", "te", "tea", "team"],
    ...extra,
  });
  const ref = (uid: string, id = TEAM) => doc(db(uid), "teamDirectory", id);

  it("anyone signed in can search listings", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teamDirectory", TEAM), listing()),
    );
    await assertSucceeds(getDoc(ref(OUTSIDER)));
    await assertSucceeds(
      getDocs(query(collection(db(OUTSIDER), "teamDirectory"), where("keywords", "array-contains", "tea"))),
    );
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "teamDirectory", TEAM)));
  });

  it("editors list their team as it is; players and outsiders cannot", async () => {
    await assertSucceeds(setDoc(ref(CAPTAIN), listing()));
    await assertFails(setDoc(ref(PLAYER), listing()));
    await assertFails(setDoc(ref(OUTSIDER), listing()));
    await assertFails(setDoc(ref(COACH), listing({ name: "Better Team" })));
    await assertFails(setDoc(ref(COACH), listing({ memberIds: [OWNER] })));
  });

  it("listing changes go with the team's edits", async () => {
    const fs = db(COACH);
    const batch = writeBatch(fs);
    batch.update(doc(fs, "teams", TEAM), { name: "Renamed", city: "Austin" });
    batch.set(doc(fs, "teamDirectory", TEAM), listing({ name: "Renamed", city: "Austin" }));
    await assertSucceeds(batch.commit());
  });

  it("a new team lists itself in its create batch", async () => {
    const fs = db(OUTSIDER);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", "t2"), {
      name: "New", division: "open", level: "college", city: "Denver",
      ownerId: OUTSIDER, members: { [OUTSIDER]: "owner" },
      memberIds: [OUTSIDER], memberNames: { [OUTSIDER]: "Me" },
    });
    batch.set(doc(fs, "teams", "t2", "private", "invite"), { code: "ZZZ999" });
    batch.set(doc(fs, "inviteCodes", "ZZZ999"), { teamId: "t2" });
    batch.set(
      doc(fs, "teamDirectory", "t2"),
      listing({ name: "New", division: "open", level: "college", city: "Denver" }),
    );
    await assertSucceeds(batch.commit());
  });

  it("only the owner deletes a team's listing", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teamDirectory", TEAM), listing()),
    );
    await assertFails(deleteDoc(ref(COACH)));
    await assertSucceeds(deleteDoc(ref(OWNER)));
  });
});

describe("stats", () => {
  const game = (extra: Record<string, unknown> = {}) => ({
    opponent: "Rival",
    date: new Date(2026, 9, 28),
    gameTo: 15,
    tournamentId: null,
    eventId: null,
    points: [
      {
        line: ["a", "b", "c", "d", "e", "f", "g"],
        startedOn: "offense",
        actions: [{ kind: "pickup", playerId: "a" }],
        result: null,
      },
    ],
    finished: false,
    lines: [],
    timeoutsPerHalf: 2,
    timeouts: [],
    ...extra,
  });
  const tournament = () => ({
    name: "Regionals",
    startDate: new Date(2026, 9, 28),
    location: "",
    eventId: null,
    roster: ["a", "b"],
    lines: [{ id: "l1", name: "O-line", players: ["a"], side: "offense" }],
  });
  const g = (uid: string) => doc(db(uid), "teams", TEAM, "statsGames", "g1");
  const t = (uid: string) => doc(db(uid), "teams", TEAM, "statsTournaments", "t1");

  it("owners, coaches, captains and stats keepers keep stats; others cannot", async () => {
    await assertSucceeds(setDoc(g(COACH), game()));
    await assertSucceeds(setDoc(g(OWNER), game({ finished: true })));
    await assertSucceeds(setDoc(g(STATS), game()));
    await assertSucceeds(setDoc(g(CAPTAIN), game()));
    await assertFails(setDoc(g(PLAYER), game()));
    await assertFails(setDoc(g(OUTSIDER), game()));
    await assertSucceeds(setDoc(t(COACH), tournament()));
    await assertSucceeds(setDoc(t(STATS), tournament()));
    await assertSucceeds(setDoc(t(CAPTAIN), tournament()));
    await assertFails(setDoc(t(PLAYER), tournament()));
  });

  it("members can view stats, outsiders cannot", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "statsGames", "g1"), game()),
    );
    await assertSucceeds(getDoc(g(PLAYER)));
    await assertFails(getDoc(g(OUTSIDER)));
  });

  it("validates games", async () => {
    await assertFails(setDoc(g(COACH), game({ opponent: "" })));
    await assertFails(setDoc(g(COACH), game({ gameTo: "15" })));
    await assertFails(setDoc(g(COACH), game({ hacked: true })));
    await assertFails(setDoc(g(COACH), game({ timeoutsPerHalf: -1 })));
  });

  it("only editors delete stats", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "statsGames", "g1"), game()),
    );
    await assertFails(deleteDoc(g(PLAYER)));
    await assertSucceeds(deleteDoc(g(COACH)));
  });
});

describe("usau cache", () => {
  it("is read-only for clients", async () => {
    await assertSucceeds(getDoc(doc(db(PLAYER), "usau_tournaments", "x")));
    await assertFails(setDoc(doc(db(PLAYER), "usau_tournaments", "x"), { name: "hack" }));
  });
});

describe("chat", () => {
  const room = (overrides: Record<string, unknown> = {}) => ({
    name: "Captains",
    readRoles: ["owner", "coach", "captain"],
    writeRoles: ["owner", "captain"],
    readUsers: [STATS],
    writeUsers: [],
    createdBy: COACH,
    createdAt: serverTimestamp(),
    ...overrides,
  });
  const roomRef = (uid: string, id = "r1") => doc(db(uid), "teams", TEAM, "chats", id);
  const messages = (uid: string, id = "r1") =>
    collection(db(uid), "teams", TEAM, "chats", id, "messages");
  const message = (uid: string, overrides: Record<string, unknown> = {}) => ({
    authorId: uid,
    authorName: "Name",
    text: "Hi",
    attachments: [],
    createdAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(() =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", TEAM, "chats", "r1"), { ...room(), createdAt: new Date() });
      await setDoc(doc(fs, "teams", TEAM, "chats", "r1", "messages", "m1"), {
        ...message(CAPTAIN),
        createdAt: new Date(),
      });
    }),
  );

  it("owners, coaches and captains create rooms; players cannot", async () => {
    await assertSucceeds(setDoc(roomRef(COACH, "r2"), room()));
    await assertSucceeds(setDoc(roomRef(CAPTAIN, "r3"), room({ createdBy: CAPTAIN })));
    await assertFails(setDoc(roomRef(PLAYER, "r4"), room({ createdBy: PLAYER })));
    await assertFails(setDoc(roomRef(OUTSIDER, "r5"), room({ createdBy: OUTSIDER })));
  });

  it("validates rooms: writers must be readers, roles are known", async () => {
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ writeRoles: ["player"] })));
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ writeUsers: [PLAYER] })));
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ readRoles: ["admin"] })));
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ name: "" })));
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ createdBy: OWNER })));
  });

  it("General can be created with its team in one batch", async () => {
    const fs = db(OUTSIDER);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", "t2"), {
      name: "New", division: "mixed", level: "club", city: "",
      ownerId: OUTSIDER, members: { [OUTSIDER]: "owner" }, memberIds: [OUTSIDER],
      memberNames: { [OUTSIDER]: "X" }, createdAt: serverTimestamp(),
    });
    batch.set(doc(fs, "teams", "t2", "private", "invite"), { code: "NEW234" });
    batch.set(doc(fs, "inviteCodes", "NEW234"), { teamId: "t2" });
    batch.set(doc(fs, "teams", "t2", "chats", "general"), {
      name: "General",
      readRoles: ["owner", "coach", "captain", "player"],
      writeRoles: ["owner", "coach", "captain", "player"],
      readUsers: [], writeUsers: [], createdBy: OUTSIDER, createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it("room details: admins see every room, others only rooms they can read", async () => {
    for (const uid of [OWNER, COACH, CAPTAIN, STATS]) {
      await assertSucceeds(getDoc(roomRef(uid)));
    }
    await assertFails(getDoc(roomRef(PLAYER)));
    await assertFails(getDoc(roomRef(OUTSIDER)));
  });

  it("players list rooms by role or by their uid, not all rooms", async () => {
    const chats = (uid: string) => collection(db(uid), "teams", TEAM, "chats");
    await assertFails(getDocs(chats(PLAYER)));
    await assertSucceeds(getDocs(query(chats(PLAYER), where("readRoles", "array-contains", "player"))));
    await assertSucceeds(getDocs(query(chats(PLAYER), where("readUsers", "array-contains", PLAYER))));
    await assertFails(getDocs(query(chats(PLAYER), where("readUsers", "array-contains", STATS))));
    await assertSucceeds(getDocs(chats(COACH)));
  });

  it("messages: readers by role or name read; the owner reads every room", async () => {
    await assertSucceeds(getDocs(messages(OWNER)));
    await assertSucceeds(getDocs(messages(CAPTAIN)));
    await assertSucceeds(getDocs(messages(STATS)));
    await assertFails(getDocs(messages(PLAYER)));
    await assertFails(getDocs(messages(OUTSIDER)));
  });

  it("only writers post, as themselves", async () => {
    await assertSucceeds(setDoc(doc(messages(CAPTAIN)), message(CAPTAIN)));
    await assertSucceeds(setDoc(doc(messages(OWNER)), message(OWNER)));
    // Coaches and named readers can read but not post here.
    await assertFails(setDoc(doc(messages(COACH)), message(COACH)));
    await assertFails(setDoc(doc(messages(STATS)), message(STATS)));
    await assertFails(setDoc(doc(messages(PLAYER)), message(PLAYER)));
    await assertFails(setDoc(doc(messages(CAPTAIN)), message(OWNER)));
  });

  it("validates messages", async () => {
    const m = (o: Record<string, unknown>) => setDoc(doc(messages(CAPTAIN)), message(CAPTAIN, o));
    await assertFails(m({ text: "", attachments: [] }));
    await assertFails(m({ text: "x".repeat(4001) }));
    await assertFails(m({ attachments: new Array(11).fill({ path: "p" }) }));
    await assertFails(m({ createdAt: new Date(0) }));
    await assertFails(m({ pinned: true }));
    await assertSucceeds(m({ text: "", attachments: [{ path: "p", name: "a.png", contentType: "image/png", size: 1 }] }));
  });

  it("messages can't be edited", async () => {
    await assertFails(
      updateDoc(doc(db(CAPTAIN), "teams", TEAM, "chats", "r1", "messages", "m1"), { text: "edited" }),
    );
  });

  it("authors delete their own messages; the owner deletes any", async () => {
    const m1 = (uid: string) => doc(db(uid), "teams", TEAM, "chats", "r1", "messages", "m1");
    await assertFails(deleteDoc(m1(COACH)));
    await assertSucceeds(deleteDoc(m1(CAPTAIN)));
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "chats", "r1", "messages", "m1"), {
        ...message(CAPTAIN),
        createdAt: new Date(),
      }),
    );
    await assertSucceeds(deleteDoc(m1(OWNER)));
  });

  it("admins change access; only the owner deletes rooms", async () => {
    await assertSucceeds(updateDoc(roomRef(COACH), { readUsers: [STATS, PLAYER] }));
    await assertFails(updateDoc(roomRef(PLAYER), { readUsers: [PLAYER] }));
    await assertFails(updateDoc(roomRef(COACH), { createdBy: COACH }));
    await assertFails(deleteDoc(roomRef(COACH)));
    await assertSucceeds(deleteDoc(roomRef(OWNER)));
  });
});

describe("direct messages", () => {
  // OWNER < PLAYER alphabetically, so their conversation id is "owner_player".
  const CONV = `${OWNER}_${PLAYER}`;
  const profile = (name = "Pat Player") => ({ name, keywords: ["pat"], photoUrl: null, updatedAt: serverTimestamp() });
  const newConv = (overrides: Record<string, unknown> = {}) => ({
    participants: [OWNER, PLAYER],
    names: { [OWNER]: "O", [PLAYER]: "P" },
    lastMessage: "",
    lastMessageAt: null,
    lastSenderId: "",
    readAt: {},
    createdAt: serverTimestamp(),
    ...overrides,
  });
  const conv = (uid: string, id = CONV) => doc(db(uid), "conversations", id);
  const msgs = (uid: string, id = CONV) => collection(db(uid), "conversations", id, "messages");
  const msg = (uid: string) => ({
    authorId: uid, authorName: "N", text: "Hi", attachments: [], createdAt: serverTimestamp(),
  });

  beforeEach(() =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "profiles", OWNER), { name: "Olive Owner", keywords: ["olive"], photoUrl: null });
      await setDoc(doc(fs, "profiles", PLAYER), { name: "Pat Player", keywords: ["pat"], photoUrl: null });
    }),
  );

  it("profiles: anyone signed in reads; only you write yours, without email", async () => {
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "profiles", PLAYER)));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "profiles", PLAYER)));
    await assertSucceeds(setDoc(doc(db(PLAYER), "profiles", PLAYER), profile()));
    await assertFails(setDoc(doc(db(OUTSIDER), "profiles", PLAYER), profile()));
    await assertFails(setDoc(doc(db(PLAYER), "profiles", PLAYER), { ...profile(), email: "a@b.c" }));
    await assertFails(setDoc(doc(db(PLAYER), "profiles", PLAYER), profile("")));
  });

  it("participants start a conversation with a listed user", async () => {
    await assertSucceeds(getDoc(conv(PLAYER))); // checking it exists
    await assertSucceeds(setDoc(conv(PLAYER), newConv()));
  });

  it("rejects bad conversations", async () => {
    await assertFails(setDoc(conv(OUTSIDER), newConv()));
    await assertFails(setDoc(conv(OWNER, `${PLAYER}_${OWNER}`), newConv({ participants: [PLAYER, OWNER] })));
    await assertFails(setDoc(conv(OWNER, `${OWNER}_zed`), newConv({
      participants: [OWNER, "zed"], names: { [OWNER]: "O", zed: "Z" },
    })));
    await assertFails(setDoc(conv(OWNER), newConv({ lastMessage: "forged" })));
  });

  describe("an existing conversation", () => {
    beforeEach(() =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "conversations", CONV), { ...newConv(), createdAt: new Date() }),
      ),
    );

    it("only the two participants read it and its messages", async () => {
      await assertSucceeds(getDoc(conv(OWNER)));
      await assertFails(getDoc(conv(COACH)));
      await assertSucceeds(getDocs(query(collection(db(PLAYER), "conversations"), where("participants", "array-contains", PLAYER))));
      await assertFails(getDocs(collection(db(PLAYER), "conversations")));
      await assertSucceeds(getDocs(msgs(PLAYER)));
      await assertFails(getDocs(msgs(COACH)));
    });

    it("participants post as themselves and update the preview", async () => {
      const fs = db(PLAYER);
      const batch = writeBatch(fs);
      batch.set(doc(collection(fs, "conversations", CONV, "messages")), msg(PLAYER));
      batch.update(doc(fs, "conversations", CONV), {
        lastMessage: "Hi", lastMessageAt: serverTimestamp(), lastSenderId: PLAYER,
        [`readAt.${PLAYER}`]: serverTimestamp(), [`names.${PLAYER}`]: "Pat",
      });
      await assertSucceeds(batch.commit());
      await assertFails(setDoc(doc(msgs(COACH)), msg(COACH)));
      await assertFails(setDoc(doc(msgs(PLAYER)), msg(OWNER)));
    });

    it("nobody forges the other's read time, name or preview", async () => {
      await assertFails(updateDoc(conv(PLAYER), { [`readAt.${OWNER}`]: serverTimestamp() }));
      await assertFails(updateDoc(conv(PLAYER), {
        lastMessage: "x", lastMessageAt: serverTimestamp(), lastSenderId: OWNER,
      }));
      await assertFails(updateDoc(conv(PLAYER), {
        lastMessage: "x", lastMessageAt: serverTimestamp(), lastSenderId: PLAYER, [`names.${OWNER}`]: "Mallory",
      }));
      await assertSucceeds(updateDoc(conv(PLAYER), { [`readAt.${PLAYER}`]: serverTimestamp() }));
    });

    it("authors delete only their own messages", async () => {
      await env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "conversations", CONV, "messages", "m1"), { ...msg(OWNER), createdAt: new Date() }),
      );
      await assertFails(deleteDoc(doc(db(PLAYER), "conversations", CONV, "messages", "m1")));
      await assertSucceeds(deleteDoc(doc(db(OWNER), "conversations", CONV, "messages", "m1")));
    });

    it("conversations can't be deleted", async () => {
      await assertFails(deleteDoc(conv(OWNER)));
    });
  });
});

describe("notifications", () => {
  const prefs = (uid: string) => doc(db(uid), "users", uid, "settings", "notifications");
  const device = (uid: string, fid: string) => doc(db(uid), "users", uid, "devices", fid);
  const entry = (uid: string, id: string) => doc(db(uid), "users", uid, "notifications", id);

  beforeEach(() =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", PLAYER, "notifications", "n1"), {
        category: "chat",
        title: "General · Team",
        body: "C: hi",
        route: "/teams/team1/chats/general",
        createdAt: serverTimestamp(),
        read: false,
        count: 1,
      });
    }),
  );

  it("lets users keep their own preferences", async () => {
    await assertSucceeds(
      setDoc(prefs(PLAYER), {
        categories: { chat: false },
        teams: { [TEAM]: { eventReminders: true } },
        mutedRooms: [`${TEAM}/general`],
        utcOffsetMinutes: -360,
        updatedAt: serverTimestamp(),
      }, { merge: true }),
    );
    await assertSucceeds(getDoc(prefs(PLAYER)));
    await assertFails(getDoc(doc(db(COACH), "users", PLAYER, "settings", "notifications")));
    await assertFails(setDoc(doc(db(COACH), "users", PLAYER, "settings", "notifications"), {}));
  });

  it("rejects unknown preference fields and categories", async () => {
    await assertFails(setDoc(prefs(PLAYER), { email: "x@y.z" }));
    await assertFails(setDoc(prefs(PLAYER), { categories: { spam: true } }));
    await assertFails(setDoc(prefs(PLAYER), { utcOffsetMinutes: 5000 }));
  });

  it("registers only your own devices", async () => {
    await assertSucceeds(setDoc(device(PLAYER, "fid1"), { platform: "iOS", updatedAt: serverTimestamp() }));
    await assertFails(setDoc(device(PLAYER, "fid2"), { platform: "windows", updatedAt: serverTimestamp() }));
    await assertFails(setDoc(device(PLAYER, "fid3"), { platform: "android", token: "x" }));
    await assertFails(getDoc(doc(db(COACH), "users", PLAYER, "devices", "fid1")));
    await assertSucceeds(deleteDoc(device(PLAYER, "fid1")));
  });

  it("lets the owner of a feed read, mark read and clear it, but not write it", async () => {
    await assertSucceeds(getDocs(collection(db(PLAYER), "users", PLAYER, "notifications")));
    await assertFails(getDoc(doc(db(COACH), "users", PLAYER, "notifications", "n1")));
    await assertFails(updateDoc(entry(PLAYER, "n1"), { title: "Forged" }));
    await assertFails(updateDoc(entry(PLAYER, "n1"), { read: false, count: 9 }));
    await assertSucceeds(updateDoc(entry(PLAYER, "n1"), { read: true }));
    await assertFails(setDoc(entry(PLAYER, "n2"), { title: "Forged", read: false }));
    await assertSucceeds(deleteDoc(entry(PLAYER, "n1")));
  });

  it("keeps reminder records server-only", async () => {
    await assertFails(getDoc(doc(db(PLAYER), "sentReminders", "x")));
    await assertFails(setDoc(doc(db(PLAYER), "sentReminders", "x"), {}));
  });

  it("lets only the owner mark a team as being deleted", async () => {
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { deletingAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { deletingAt: serverTimestamp(), name: "X" }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { deletingAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { deletingAt: new Date(2000, 0, 1) }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { deletingAt: deleteField() }));
  });
});

describe("meetings", () => {
  // Invites players by name only: STATS is invited, PLAYER isn't.
  const meeting = (overrides: Record<string, unknown> = {}) => ({
    title: "Film review",
    startsAt: new Date("2026-11-02T19:00:00Z"),
    endsAt: null,
    notes: "",
    inviteRoles: [],
    inviteUsers: [STATS],
    requireApproval: false,
    status: "scheduled",
    rsvps: {},
    createdBy: COACH,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });
  const ref = (uid: string, id = "m1") => doc(db(uid), "teams", TEAM, "meetings", id);
  const meetings = (uid: string) => collection(db(uid), "teams", TEAM, "meetings");
  const request = (uid: string, who = uid) =>
    doc(db(uid), "teams", TEAM, "meetings", "m1", "requests", who);
  const messages = (uid: string) => collection(db(uid), "teams", TEAM, "meetings", "m1", "messages");
  const seed = (overrides: Record<string, unknown> = {}) =>
    env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "meetings", "m1"), {
        ...meeting(overrides),
        createdAt: new Date(),
        updatedAt: new Date(),
      }),
    );
  const say = (uid: string) => ({ authorId: uid, authorName: "N", text: "Hi", createdAt: serverTimestamp() });

  it("admins schedule meetings; players and outsiders can't", async () => {
    await assertSucceeds(setDoc(ref(CAPTAIN), meeting({ createdBy: CAPTAIN })));
    await assertFails(setDoc(ref(PLAYER, "m2"), meeting({ createdBy: PLAYER })));
    await assertFails(setDoc(ref(OUTSIDER, "m3"), meeting({ createdBy: OUTSIDER })));
  });

  it("new meetings start scheduled, with no RSVPs", async () => {
    await assertFails(setDoc(ref(COACH), meeting({ status: "live" })));
    await assertFails(setDoc(ref(COACH), meeting({ rsvps: { [COACH]: "attending" } })));
    await assertFails(setDoc(ref(COACH), meeting({ inviteRoles: ["fan"] })));
  });

  it("only admins and invitees can read, and queries must be limited to theirs", async () => {
    await seed();
    await assertSucceeds(getDoc(ref(OWNER)));
    await assertSucceeds(getDoc(ref(CAPTAIN)));
    await assertSucceeds(getDoc(ref(STATS)));
    await assertFails(getDoc(ref(PLAYER)));
    await assertFails(getDoc(ref(OUTSIDER)));
    await assertSucceeds(getDocs(meetings(COACH)));
    await assertFails(getDocs(meetings(PLAYER)));
    await assertSucceeds(getDocs(query(meetings(PLAYER), where("inviteRoles", "array-contains", "player"))));
    await assertSucceeds(getDocs(query(meetings(STATS), where("inviteUsers", "array-contains", STATS))));
  });

  it("invitees answer only for themselves", async () => {
    await seed();
    await assertSucceeds(updateDoc(ref(STATS), { [`rsvps.${STATS}`]: "attending" }));
    await assertSucceeds(updateDoc(ref(STATS), { [`rsvps.${STATS}`]: deleteField() }));
    await assertFails(updateDoc(ref(STATS), { [`rsvps.${STATS}`]: "maybe" }));
    await assertFails(updateDoc(ref(STATS), { [`rsvps.${COACH}`]: "attending" }));
    await assertFails(updateDoc(ref(PLAYER), { [`rsvps.${PLAYER}`]: "attending" }));
    await assertFails(updateDoc(ref(STATS), { title: "Mine now" }));
  });

  it("admins start and end meetings; invitees can't", async () => {
    await seed();
    await assertFails(
      updateDoc(ref(STATS), { status: "live", startedAt: serverTimestamp(), startedBy: STATS }),
    );
    await assertFails(
      updateDoc(ref(COACH), { status: "live", startedAt: serverTimestamp(), startedBy: OWNER }),
    );
    await assertSucceeds(
      updateDoc(ref(COACH), { status: "live", startedAt: serverTimestamp(), startedBy: COACH }),
    );
    await assertFails(updateDoc(ref(STATS), { status: "ended", endedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref(CAPTAIN), { status: "ended", endedAt: serverTimestamp() }));
    await assertFails(
      updateDoc(ref(COACH), { status: "live", startedAt: serverTimestamp(), startedBy: COACH }),
    );
  });

  it("admins edit and delete; invitees can't", async () => {
    await seed();
    await assertSucceeds(
      updateDoc(ref(COACH), { title: "Film", inviteRoles: ["player"], updatedAt: serverTimestamp() }),
    );
    await assertFails(updateDoc(ref(COACH), { rsvps: { [STATS]: "attending" } }));
    await assertFails(deleteDoc(ref(STATS)));
    await assertSucceeds(deleteDoc(ref(OWNER)));
  });

  describe("join requests", () => {
    const ask = () => ({ name: "N", status: "pending", requestedAt: serverTimestamp() });

    it("invitees ask only when approval is on, for themselves", async () => {
      await seed();
      await assertFails(setDoc(request(STATS), ask()));
      await seed({ requireApproval: true, status: "live" });
      await assertSucceeds(setDoc(request(STATS), ask()));
      await assertFails(setDoc(request(STATS, PLAYER), ask()));
      await assertFails(setDoc(request(PLAYER), ask()));
      await assertFails(setDoc(request(STATS), { ...ask(), status: "admitted" }));
    });

    it("admins let people in or turn them away; requests are private", async () => {
      await seed({ requireApproval: true, status: "live" });
      await assertSucceeds(setDoc(request(STATS), ask()));
      await assertFails(getDoc(request(PLAYER, STATS)));
      await assertSucceeds(getDocs(collection(db(CAPTAIN), "teams", TEAM, "meetings", "m1", "requests")));
      await assertFails(
        updateDoc(request(STATS), { status: "admitted", decidedBy: STATS, decidedAt: serverTimestamp() }),
      );
      await assertSucceeds(
        updateDoc(request(COACH, STATS), { status: "admitted", decidedBy: COACH, decidedAt: serverTimestamp() }),
      );
      // Asking again after a decision.
      await assertSucceeds(setDoc(request(STATS), ask()));
    });

    it("no asking once the meeting has ended", async () => {
      await seed({ requireApproval: true, status: "ended" });
      await assertFails(setDoc(request(STATS), ask()));
    });
  });

  describe("chat", () => {
    it("people in a live call chat; others can't", async () => {
      await seed({ status: "live" });
      await assertSucceeds(setDoc(doc(messages(STATS), "a"), say(STATS)));
      await assertSucceeds(getDocs(messages(COACH)));
      await assertFails(setDoc(doc(messages(PLAYER), "b"), say(PLAYER)));
      await assertFails(getDocs(messages(PLAYER)));
      await assertFails(setDoc(doc(messages(STATS), "c"), say(COACH)));
    });

    it("needs the meeting to be live", async () => {
      await seed();
      await assertFails(setDoc(doc(messages(COACH), "a"), say(COACH)));
    });

    it("with approval on, only people let in can chat", async () => {
      await seed({ status: "live", requireApproval: true });
      await assertFails(setDoc(doc(messages(STATS), "a"), say(STATS)));
      await assertFails(getDocs(messages(STATS)));
      await env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "teams", TEAM, "meetings", "m1", "requests", STATS), {
          name: "S",
          status: "admitted",
        }),
      );
      await assertSucceeds(setDoc(doc(messages(STATS), "a"), say(STATS)));
      await assertSucceeds(getDocs(messages(STATS)));
      await assertSucceeds(setDoc(doc(messages(CAPTAIN), "b"), say(CAPTAIN)));
    });
  });

  describe("watch together", () => {
    const playback = (uid: string, id = "current") =>
      doc(db(uid), "teams", TEAM, "meetings", "m1", "playback", id);
    const state = (uid: string, extra: Record<string, unknown> = {}) => ({
      videoId: "v1",
      playing: true,
      positionMs: 1500,
      presenterId: uid,
      presenterName: "P",
      updatedAt: serverTimestamp(),
      ...extra,
    });
    const seedVideo = () =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "teams", TEAM, "videos", "v1"), { youtubeId: "dQw4w9WgXcQ", title: "Film" }),
      );

    it("admins play team videos for a live call; people in it follow", async () => {
      await seed({ status: "live" });
      await seedVideo();
      await assertSucceeds(setDoc(playback(COACH), state(COACH)));
      await assertSucceeds(getDoc(playback(STATS)));
      await assertFails(getDoc(playback(PLAYER)));
      await assertFails(setDoc(playback(STATS), state(STATS)));
      // Another admin takes over; nobody plays as someone else.
      await assertSucceeds(setDoc(playback(CAPTAIN), state(CAPTAIN, { playing: false })));
      await assertFails(setDoc(playback(CAPTAIN), state(COACH)));
      await assertFails(deleteDoc(playback(STATS)));
      await assertSucceeds(deleteDoc(playback(CAPTAIN)));
    });

    it("only a team video, only while live, only the one doc", async () => {
      await seed({ status: "live" });
      await seedVideo();
      await assertFails(setDoc(playback(COACH), state(COACH, { videoId: "nope" })));
      await assertFails(setDoc(playback(COACH), state(COACH, { positionMs: -1 })));
      await assertFails(setDoc(playback(COACH), state(COACH, { url: "https://x" })));
      await assertFails(setDoc(playback(COACH, "other"), state(COACH)));
      await seed({ status: "ended" });
      await assertFails(setDoc(playback(COACH), state(COACH)));
    });
  });
});
