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
