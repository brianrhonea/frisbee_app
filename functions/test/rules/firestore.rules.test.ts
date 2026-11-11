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

// An inviteCodes doc as the app mints it (InviteCode in
// lib/domain/models/invite_code.dart): a 6-character code that works for
// 45 seconds, or a 20-character link token for 1 hour to 30 days.
const SECOND = 1000;
const liveCode = (teamId = TEAM, ttl = 45, createdAt = new Date()) => ({
  teamId,
  createdBy: COACH,
  createdAt,
  ttl,
  expiresAt: new Date(createdAt.getTime() + ttl * SECOND),
});
const TOKEN = "ABCDEFGHJKLMNPQRSTUV";

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
    await setDoc(doc(fs, "inviteCodes", CODE), liveCode());
  });
});

describe("team create", () => {
  const newTeam = (extra: Record<string, unknown> = {}) => ({
    name: "New",
    division: "open",
    level: "college",
    city: "Denver",
    ownerId: OUTSIDER,
    members: { [OUTSIDER]: "owner" },
    memberIds: [OUTSIDER],
    memberNames: { [OUTSIDER]: "Me" },
    ...extra,
  });

  it("allows creating a team, with no invite code", async () => {
    await assertSucceeds(setDoc(doc(db(OUTSIDER), "teams", "t2"), newTeam()));
  });

  it("rejects a team that keeps an invite code on the team doc", async () => {
    await assertFails(setDoc(doc(db(OUTSIDER), "teams", "t2"), newTeam({ inviteCode: "ZZZ999" })));
  });
});

describe("team read", () => {
  it("members can read, outsiders cannot", async () => {
    await assertSucceeds(getDoc(doc(db(PLAYER), "teams", TEAM)));
    await assertFails(getDoc(doc(db(OUTSIDER), "teams", TEAM)));
  });
});

describe("team delete", () => {
  // deleteTeam in team_repository_firebase.dart deletes an older team's
  // private/invite by name because the owner can't list private.
  it("the owner deletes an older team's private/invite; nobody reads it", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "private", "invite"), { code: "OLD234" }),
    );
    for (const uid of [OWNER, COACH, CAPTAIN, PLAYER]) {
      await assertFails(getDoc(doc(db(uid), "teams", TEAM, "private", "invite")));
    }
    await assertFails(getDocs(collection(db(OWNER), "teams", TEAM, "private")));
    await assertFails(deleteDoc(doc(db(COACH), "teams", TEAM, "private", "invite")));
    await assertSucceeds(deleteDoc(doc(db(OWNER), "teams", TEAM, "private", "invite")));
  });

  it("only the owner deletes the team, and only once everyone else is gone", async () => {
    await assertFails(deleteDoc(doc(db(COACH), "teams", TEAM)));
    await assertFails(deleteDoc(doc(db(OWNER), "teams", TEAM)));
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "teams", TEAM), {
        members: { [OWNER]: "owner" },
        memberIds: [OWNER],
      }),
    );
    await assertSucceeds(deleteDoc(doc(db(OWNER), "teams", TEAM)));
  });
});

describe("a league's team", () => {
  // createLeagueTeams (functions/src/tournaments/callables.ts) writes these:
  // the captain owns it and the league's id is on it.
  const LEAGUE = "league_t1_team1";
  const CAP = "leagueCaptain";
  const MATE = "leagueMate";
  const leagueTeam = (extra: Record<string, unknown> = {}) => ({
    name: "Reds - Thursday Night",
    division: "mixed",
    level: "league",
    city: "Denver",
    ownerId: CAP,
    members: { [CAP]: "owner", [MATE]: "player" },
    memberIds: [CAP, MATE],
    memberNames: { [CAP]: "Cap", [MATE]: "Mate" },
    leagueId: "t1",
    leagueHostId: "host1",
    ...extra,
  });
  const seedLeague = (status: string | null) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", LEAGUE), leagueTeam());
      if (status) {
        await setDoc(doc(fs, "tournaments", "t1"), { hostId: "host1", name: "Thursday Night", status });
      }
    });

  it("its captain-owner manages it like any team, despite the league fields", async () => {
    await seedLeague("live");
    const ref = doc(db(CAP), "teams", LEAGUE);
    await assertSucceeds(updateDoc(ref, { name: "Crimson - Thursday Night", city: "Boulder" }));
    await assertSucceeds(
      setDoc(doc(db(CAP), "teams", LEAGUE, "roster", "r1"), { name: "Sub", number: 9, position: "hybrid", userId: null }),
    );
    // Teammates can read it but not rename it, and nobody can forge a league id.
    await assertSucceeds(getDoc(doc(db(MATE), "teams", LEAGUE)));
    await assertFails(updateDoc(doc(db(MATE), "teams", LEAGUE), { name: "Mine" }));
    await assertFails(updateDoc(ref, { leagueId: "other" }));
    await assertFails(updateDoc(ref, { ownerId: MATE }));
  });

  it("can't be deleted by its owner while the league runs", async () => {
    await seedLeague("live");
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "teams", LEAGUE), { members: { [CAP]: "owner" }, memberIds: [CAP] }),
    );
    await assertFails(deleteDoc(doc(db(CAP), "teams", LEAGUE)));
    await assertFails(updateDoc(doc(db(CAP), "teams", LEAGUE), { deletingAt: serverTimestamp() }));
  });

  it("can be deleted once the league is final, or if the league is gone", async () => {
    for (const status of ["finished", null]) {
      await env.clearFirestore();
      await seedLeague(status);
      await env.withSecurityRulesDisabled((ctx) =>
        updateDoc(doc(ctx.firestore(), "teams", LEAGUE), { members: { [CAP]: "owner" }, memberIds: [CAP] }),
      );
      await assertSucceeds(deleteDoc(doc(db(CAP), "teams", LEAGUE)));
    }
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

  const seedCode = (code: string, data: Record<string, unknown>) =>
    env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), "inviteCodes", code), data));

  it("allows joining with a live code", async () => {
    await assertSucceeds(join(CODE));
  });

  it("allows joining with a live link token", async () => {
    await seedCode(TOKEN, liveCode(TEAM, 604800));
    await assertSucceeds(join(TOKEN));
  });

  it("rejects an expired code or link", async () => {
    await seedCode("OLD234", liveCode(TEAM, 45, new Date(Date.now() - 46 * SECOND)));
    await assertFails(join("OLD234"));
    await seedCode(TOKEN, liveCode(TEAM, 3600, new Date(Date.now() - 3601 * SECOND)));
    await assertFails(join(TOKEN));
  });

  it("rejects another team's code", async () => {
    await seedCode("OTH234", liveCode("t2"));
    await assertFails(join("OTH234"));
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

  it("permanent codes from before rotation no longer work", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", TEAM, "private", "invite"), { code: "OLD234" });
      await setDoc(doc(fs, "inviteCodes", "OLD234"), { teamId: TEAM });
      await setDoc(doc(fs, "inviteCodes", "OLD777"), { teamId: TEAM });
      await updateDoc(doc(fs, "teams", TEAM), { inviteCode: "OLD777" });
    });
    await assertFails(join("OLD234"));
    await assertFails(join("OLD777"));
  });
});

describe("team invites", () => {
  const invitePath = (uid = OUTSIDER) => ["users", uid, "teamInvites", TEAM] as const;
  const invite = (from = CAPTAIN) => ({
    teamName: "Team",
    kind: "team",
    invitedBy: from,
    invitedByName: "K",
    createdAt: serverTimestamp(),
  });
  const joinUpdate = {
    [`members.${OUTSIDER}`]: "player",
    [`memberNames.${OUTSIDER}`]: "New Player",
    memberIds: arrayUnion(OUTSIDER),
  };
  const accept = (update: Record<string, unknown> = joinUpdate) => {
    const fs = db(OUTSIDER);
    return writeBatch(fs)
      .update(doc(fs, "teams", TEAM), update)
      .delete(doc(fs, ...invitePath()))
      .commit();
  };
  const seedInvite = () =>
    env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), ...invitePath()), { ...invite(), createdAt: new Date() }),
    );

  it("owners and organizers invite people who aren't members", async () => {
    await assertSucceeds(setDoc(doc(db(CAPTAIN), ...invitePath()), invite()));
    await assertFails(setDoc(doc(db(PLAYER), ...invitePath()), invite(PLAYER)));
    await assertFails(setDoc(doc(db(OUTSIDER), ...invitePath()), invite(OUTSIDER)));
    // Not someone already on the team, nor with a made-up team name.
    await assertFails(setDoc(doc(db(CAPTAIN), ...invitePath(PLAYER)), invite()));
    await assertFails(setDoc(doc(db(CAPTAIN), ...invitePath()), { ...invite(), teamName: "Other" }));
  });

  it("only the invitee and the team's editors see an invite", async () => {
    await seedInvite();
    await assertSucceeds(getDoc(doc(db(OUTSIDER), ...invitePath())));
    await assertSucceeds(getDoc(doc(db(COACH), ...invitePath())));
    await assertFails(getDoc(doc(db(PLAYER), ...invitePath())));
  });

  it("the invitee joins as a player without a code", async () => {
    await seedInvite();
    await assertFails(accept({ ...joinUpdate, [`members.${OUTSIDER}`]: "coach" }));
    await assertSucceeds(accept());
  });

  it("joining needs an invite, used up in the same batch", async () => {
    await assertFails(accept());
    await seedInvite();
    await assertFails(updateDoc(doc(db(OUTSIDER), "teams", TEAM), joinUpdate));
  });

  it("the invitee declines by deleting it", async () => {
    await seedInvite();
    await assertSucceeds(deleteDoc(doc(db(OUTSIDER), ...invitePath())));
  });
});

describe("community groups", () => {
  const GROUP = "group1";
  const ORGANIZER = "organizer";
  const MEMBER = "member";

  const setGroup = (requiresApproval: boolean) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "teams", GROUP), {
        name: "Pickup Crew",
        division: "mixed",
        level: "pickup",
        city: "Denver",
        kind: "community",
        description: "Sunday pickup",
        requiresApproval,
        location: { address: "City Park", lat: 39.75, lng: -104.95 },
        ownerId: OWNER,
        members: { [OWNER]: "owner", [ORGANIZER]: "captain", [MEMBER]: "player" },
        memberIds: [OWNER, ORGANIZER, MEMBER],
        memberNames: { [OWNER]: "O", [ORGANIZER]: "G", [MEMBER]: "M" },
      });
    });

  const joinUpdate = (uid = OUTSIDER, role = "player") => ({
    [`members.${uid}`]: role,
    [`memberNames.${uid}`]: "Newbie",
    memberIds: arrayUnion(uid),
  });

  const groupDoc = (extra: Record<string, unknown> = {}) => ({
    name: "New Group",
    division: "mixed",
    level: "pickup",
    city: "",
    kind: "community",
    description: "",
    requiresApproval: false,
    location: null,
    ownerId: OUTSIDER,
    members: { [OUTSIDER]: "owner" },
    memberIds: [OUTSIDER],
    memberNames: { [OUTSIDER]: "Me" },
    ...extra,
  });

  it("anyone creates a group without an invite code", async () => {
    await assertSucceeds(setDoc(doc(db(OUTSIDER), "teams", "g2"), groupDoc()));
    // A team still needs one.
    await assertFails(setDoc(doc(db(OUTSIDER), "teams", "t2"), groupDoc({ kind: "team" })));
  });

  it("validates group fields", async () => {
    const fs = db(OUTSIDER);
    await assertFails(setDoc(doc(fs, "teams", "g2"), groupDoc({ description: "x".repeat(1001) })));
    await assertFails(setDoc(doc(fs, "teams", "g2"), groupDoc({ requiresApproval: "no" })));
    await assertFails(setDoc(doc(fs, "teams", "g2"), groupDoc({ location: { address: "", lat: 91, lng: 0 } })));
    await assertFails(setDoc(doc(fs, "teams", "g2"), groupDoc({ members: { [OUTSIDER]: "owner", x: "player" } })));
    await assertSucceeds(
      setDoc(doc(fs, "teams", "g2"), groupDoc({ location: { address: "Park", lat: 40, lng: -105 } })),
    );
  });

  it("anyone joins an open group as a member, only themself", async () => {
    await setGroup(false);
    await assertFails(updateDoc(doc(db(OUTSIDER), "teams", GROUP), joinUpdate(OUTSIDER, "captain")));
    await assertFails(updateDoc(doc(db(OUTSIDER), "teams", GROUP), joinUpdate("someoneElse")));
    await assertSucceeds(updateDoc(doc(db(OUTSIDER), "teams", GROUP), joinUpdate()));
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "teams", GROUP)));
  });

  it("an open join doesn't work on a team", async () => {
    await assertFails(updateDoc(doc(db(OUTSIDER), "teams", TEAM), joinUpdate()));
  });

  it("approval groups need a request an organizer approves", async () => {
    await setGroup(true);
    await assertFails(updateDoc(doc(db(OUTSIDER), "teams", GROUP), joinUpdate()));

    const request = doc(db(OUTSIDER), "teams", GROUP, "joinRequests", OUTSIDER);
    await assertFails(setDoc(request, { name: "x".repeat(81), createdAt: serverTimestamp() }));
    await assertSucceeds(setDoc(request, { name: "Newbie", createdAt: serverTimestamp() }));
    await assertFails(
      setDoc(doc(db(OUTSIDER), "teams", GROUP, "joinRequests", "someoneElse"), {
        name: "Fake", createdAt: serverTimestamp(),
      }),
    );

    // Requests are private to the requester and organizers.
    await assertSucceeds(getDoc(request));
    await assertFails(getDoc(doc(db(MEMBER), "teams", GROUP, "joinRequests", OUTSIDER)));
    await assertSucceeds(getDocs(collection(db(ORGANIZER), "teams", GROUP, "joinRequests")));

    const approve = (uid: string, clearRequest = true) => {
      const fs = db(uid);
      const batch = writeBatch(fs).update(doc(fs, "teams", GROUP), joinUpdate());
      if (clearRequest) batch.delete(doc(fs, "teams", GROUP, "joinRequests", OUTSIDER));
      return batch.commit();
    };
    await assertFails(approve(MEMBER));
    await assertFails(approve(ORGANIZER, false));
    await assertSucceeds(approve(ORGANIZER));
  });

  it("approval needs a pending request", async () => {
    await setGroup(true);
    const fs = db(ORGANIZER);
    await assertFails(
      writeBatch(fs)
        .update(doc(fs, "teams", GROUP), joinUpdate())
        .delete(doc(fs, "teams", GROUP, "joinRequests", OUTSIDER))
        .commit(),
    );
  });

  it("members can't request, and open groups take no requests", async () => {
    await setGroup(true);
    await assertFails(
      setDoc(doc(db(MEMBER), "teams", GROUP, "joinRequests", MEMBER), { name: "M", createdAt: serverTimestamp() }),
    );
    await setGroup(false);
    await assertFails(
      setDoc(doc(db(OUTSIDER), "teams", GROUP, "joinRequests", OUTSIDER), { name: "N", createdAt: serverTimestamp() }),
    );
  });

  it("requesters withdraw and organizers decline", async () => {
    await setGroup(true);
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", GROUP, "joinRequests", OUTSIDER), { name: "N" }),
    );
    await assertFails(deleteDoc(doc(db(MEMBER), "teams", GROUP, "joinRequests", OUTSIDER)));
    await assertSucceeds(deleteDoc(doc(db(ORGANIZER), "teams", GROUP, "joinRequests", OUTSIDER)));
  });

  it("organizers edit group details but never the kind", async () => {
    await setGroup(false);
    const ref = doc(db(ORGANIZER), "teams", GROUP);
    await assertSucceeds(updateDoc(ref, { description: "Weeknights", requiresApproval: true }));
    await assertSucceeds(updateDoc(ref, { location: null }));
    await assertFails(updateDoc(ref, { kind: "team" }));
    await assertFails(updateDoc(doc(db(MEMBER), "teams", GROUP), { description: "Hi" }));
    // Teams don't take group fields.
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { description: "Hi" }));
  });

  it("groups have only owners and members; custom roles do the rest", async () => {
    await setGroup(false);
    const ref = doc(db(OWNER), "teams", GROUP);
    await assertFails(updateDoc(ref, { [`members.${MEMBER}`]: "coach" }));
    // No new organizers; legacy ones can be made members.
    await assertFails(updateDoc(ref, { [`members.${MEMBER}`]: "captain" }));
    await assertSucceeds(updateDoc(ref, { [`members.${ORGANIZER}`]: "player" }));
  });

  it("the owner moves legacy organizers into a custom role in one write", async () => {
    await setGroup(false);
    const migrate = {
      roles: { org: { name: "Organizer", color: 0, position: 0, perms: ["manageMembers", "manageEvents"] } },
      memberRoles: { [ORGANIZER]: ["org"] },
      memberPerms: { [ORGANIZER]: ["manageMembers", "manageEvents"] },
      [`members.${ORGANIZER}`]: "player",
    };
    await assertFails(updateDoc(doc(db(ORGANIZER), "teams", GROUP), migrate));
    // Members can't be promoted to owner along the way.
    await assertFails(updateDoc(doc(db(OWNER), "teams", GROUP), { ...migrate, [`members.${MEMBER}`]: "owner" }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", GROUP), migrate));
    // Still an organizer in all but name: approves and edits events.
    await assertSucceeds(getDocs(collection(db(ORGANIZER), "teams", GROUP, "joinRequests")));
    await assertFails(getDocs(collection(db(MEMBER), "teams", GROUP, "joinRequests")));
  });

  it("the directory listing mirrors the group fields", async () => {
    await setGroup(false);
    const listing = {
      name: "Pickup Crew", division: "mixed", level: "pickup", city: "Denver",
      kind: "community", description: "Sunday pickup", requiresApproval: false,
      location: { address: "City Park", lat: 39.75, lng: -104.95 },
      keywords: ["pickup"],
    };
    const ref = doc(db(ORGANIZER), "teamDirectory", GROUP);
    await assertFails(setDoc(ref, { ...listing, requiresApproval: true }));
    await assertFails(setDoc(ref, { ...listing, kind: "team" }));
    await assertSucceeds(setDoc(ref, listing));
  });

  it("a private group's listing leaves out its location", async () => {
    await setGroup(true);
    const listing = {
      name: "Pickup Crew", division: "mixed", level: "pickup", city: "Denver",
      kind: "community", description: "Sunday pickup", requiresApproval: true,
      keywords: ["pickup"],
    };
    const ref = doc(db(ORGANIZER), "teamDirectory", GROUP);
    await assertFails(
      setDoc(ref, { ...listing, location: { address: "City Park", lat: 39.75, lng: -104.95 } }),
    );
    await assertSucceeds(setDoc(ref, listing));
  });

  describe("private content", () => {
    const seed = () =>
      env.withSecurityRulesDisabled(async (ctx) => {
        const fs = ctx.firestore();
        await setDoc(doc(fs, "teams", GROUP, "posts", "p1"), {
          title: "", body: "Hi", public: true, authorId: OWNER, authorName: "O",
        });
        await setDoc(doc(fs, "teams", GROUP, "publicEvents", "e1"), { title: "Pickup" });
      });

    it("outsiders see an open group's public posts and events", async () => {
      await setGroup(false);
      await seed();
      await assertSucceeds(getDoc(doc(db(OUTSIDER), "teams", GROUP, "posts", "p1")));
      await assertSucceeds(getDoc(doc(db(OUTSIDER), "teams", GROUP, "publicEvents", "e1")));
    });

    it("only members see a private group's posts and events", async () => {
      await setGroup(true);
      await seed();
      await assertFails(getDoc(doc(db(OUTSIDER), "teams", GROUP, "posts", "p1")));
      await assertFails(getDoc(doc(db(OUTSIDER), "teams", GROUP, "publicEvents", "e1")));
      await assertSucceeds(getDoc(doc(db(MEMBER), "teams", GROUP, "posts", "p1")));
      await assertSucceeds(getDoc(doc(db(MEMBER), "teams", GROUP, "publicEvents", "e1")));
    });
  });
});

describe("group tournaments", () => {
  const GROUP = "group1";
  const ORGANIZER = "organizer";
  const CAP_A = "capA";
  const PLAYER_A = "playerA";
  const CAP_B = "capB";
  const MEMBER = "member"; // in the group, not playing
  const TOUR = "tour1";

  const tournament = (extra: Record<string, unknown> = {}) => ({
    name: "Fall Hat",
    eventId: null,
    settings: { format: "singleElim" },
    status: "scheduled",
    teams: [
      { id: "A", name: "Team 1", captainId: CAP_A, playerIds: [CAP_A, PLAYER_A], playerNames: {} },
      { id: "B", name: "Team 2", captainId: CAP_B, playerIds: [CAP_B], playerNames: {} },
    ],
    participantIds: [CAP_A, PLAYER_A, CAP_B],
    captains: { A: CAP_A, B: CAP_B },
    createdBy: ORGANIZER,
    createdAt: new Date(),
    ...extra,
  });

  const game = (extra: Record<string, unknown> = {}) => ({
    order: 0, stage: "winners", round: 1, label: "Semifinal", pool: null,
    field: 1, startsAt: new Date(), teamA: "A", teamB: "B",
    sourceA: null, sourceB: null, status: "scheduled",
    scoreA: null, scoreB: null, report: null, ifNeeded: false,
    ...extra,
  });

  const gameRef = (uid: string, id: string) =>
    doc(db(uid), "teams", GROUP, "groupTournaments", TOUR, "games", id);

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", GROUP), {
        name: "Pickup", division: "mixed", level: "pickup", city: "",
        kind: "community", description: "", requiresApproval: false, location: null,
        ownerId: OWNER,
        members: {
          [OWNER]: "owner", [ORGANIZER]: "captain", [CAP_A]: "player",
          [PLAYER_A]: "player", [CAP_B]: "player", [MEMBER]: "player",
        },
        memberIds: [OWNER, ORGANIZER, CAP_A, PLAYER_A, CAP_B, MEMBER],
        memberNames: {},
      });
      await setDoc(doc(fs, "teams", GROUP, "groupTournaments", TOUR), tournament());
      await setDoc(doc(fs, "teams", GROUP, "groupTournaments", TOUR, "games", "g1"), game());
      await setDoc(
        doc(fs, "teams", GROUP, "groupTournaments", TOUR, "games", "g2"),
        game({
          order: 1, label: "Final", teamA: null, teamB: null,
          sourceA: { type: "winner", game: "g1" }, sourceB: { type: "loser", game: "g1" },
        }),
      );
    });
  });

  it("organizers create tournaments for group members only", async () => {
    const ref = (uid: string) => doc(db(uid), "teams", GROUP, "groupTournaments", "t2");
    const fresh = (uid: string, extra: Record<string, unknown> = {}) =>
      tournament({ createdBy: uid, createdAt: serverTimestamp(), ...extra });
    await assertFails(setDoc(ref(MEMBER), fresh(MEMBER)));
    await assertFails(
      setDoc(ref(ORGANIZER), fresh(ORGANIZER, { participantIds: [CAP_A, OUTSIDER] })),
    );
    await assertFails(
      setDoc(ref(ORGANIZER), fresh(ORGANIZER, { captains: { A: MEMBER } })),
    );
    await assertSucceeds(setDoc(ref(ORGANIZER), fresh(ORGANIZER)));
    // Teams don't run these.
    await assertFails(
      setDoc(doc(db(COACH), "teams", TEAM, "groupTournaments", "t3"), fresh(COACH)),
    );
  });

  it("only players and organizers see a tournament and its games", async () => {
    const tour = (uid: string) => doc(db(uid), "teams", GROUP, "groupTournaments", TOUR);
    await assertSucceeds(getDoc(tour(PLAYER_A)));
    await assertSucceeds(getDoc(tour(ORGANIZER)));
    await assertFails(getDoc(tour(MEMBER)));
    await assertFails(getDoc(tour(OUTSIDER)));
    await assertSucceeds(getDoc(gameRef(PLAYER_A, "g1")));
    await assertFails(getDoc(gameRef(MEMBER, "g1")));
    // Players list only the ones they're in.
    const col = collection(db(PLAYER_A), "teams", GROUP, "groupTournaments");
    await assertSucceeds(getDocs(query(col, where("participantIds", "array-contains", PLAYER_A))));
    await assertFails(getDocs(col));
  });

  it("captains report; others can't; no ties", async () => {
    const report = (uid: string, byTeam: string, a = 11, b = 7) =>
      updateDoc(gameRef(uid, "g1"), { status: "reported", report: { scoreA: a, scoreB: b, byTeam } });
    await assertFails(report(PLAYER_A, "A"));
    await assertFails(report(CAP_A, "B"));
    await assertFails(report(CAP_A, "A", 9, 9));
    await assertFails(report(MEMBER, "A"));
    await assertSucceeds(report(CAP_A, "A"));
    // The other captain disagrees and files their own.
    await assertSucceeds(report(CAP_B, "B", 11, 9));
  });

  it("the other captain confirms the reported score", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "teams", GROUP, "groupTournaments", TOUR, "games", "g1"), {
        status: "reported", report: { scoreA: 11, scoreB: 7, byTeam: "A" },
      }),
    );
    const confirm = (uid: string, a = 11, b = 7) =>
      updateDoc(gameRef(uid, "g1"), { status: "done", scoreA: a, scoreB: b, report: null });
    await assertFails(confirm(CAP_A));
    await assertFails(confirm(CAP_B, 11, 5));
    await assertSucceeds(confirm(CAP_B));
  });

  it("winners move on only to the games that wait for them", async () => {
    // Not final yet: nothing moves.
    await assertFails(updateDoc(gameRef(PLAYER_A, "g2"), { teamA: "A" }));

    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "teams", GROUP, "groupTournaments", TOUR, "games", "g1"), {
        status: "done", scoreA: 11, scoreB: 7,
      }),
    );
    await assertFails(updateDoc(gameRef(PLAYER_A, "g2"), { teamA: "B" }));
    await assertFails(updateDoc(gameRef(MEMBER, "g2"), { teamA: "A", teamB: "B" }));
    await assertFails(updateDoc(gameRef(PLAYER_A, "g2"), { teamA: "A", label: "Hacked" }));
    await assertSucceeds(updateDoc(gameRef(PLAYER_A, "g2"), { teamA: "A", teamB: "B" }));
    // Filled slots stay put.
    await assertFails(updateDoc(gameRef(CAP_B, "g2"), { teamA: "B" }));
  });

  it("confirming and advancing go together in one batch", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "teams", GROUP, "groupTournaments", TOUR, "games", "g1"), {
        status: "reported", report: { scoreA: 7, scoreB: 11, byTeam: "A" },
      }),
    );
    const fs = db(CAP_B);
    await assertSucceeds(
      writeBatch(fs)
        .update(doc(fs, "teams", GROUP, "groupTournaments", TOUR, "games", "g1"), {
          status: "done", scoreA: 7, scoreB: 11, report: null,
        })
        .update(doc(fs, "teams", GROUP, "groupTournaments", TOUR, "games", "g2"), {
          teamA: "B", teamB: "A",
        })
        .commit(),
    );
  });

  it("organizers set any score; members can't touch games", async () => {
    await assertSucceeds(
      updateDoc(gameRef(ORGANIZER, "g1"), { status: "done", scoreA: 13, scoreB: 11, report: null }),
    );
    await assertFails(
      updateDoc(gameRef(ORGANIZER, "g1"), { status: "done", scoreA: 11, scoreB: 11 }),
    );
    await assertFails(updateDoc(gameRef(MEMBER, "g1"), { field: 2 }));
    await assertFails(deleteDoc(gameRef(CAP_A, "g1")));
    await assertSucceeds(deleteDoc(gameRef(ORGANIZER, "g1")));
  });
});

describe("roles and removal", () => {
  it("members read the tournaments their team entered; only the server writes them", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "tournamentEntries", "x1"), { name: "Classic", status: "applied" }),
    );
    const rec = (uid: string) => doc(db(uid), "teams", TEAM, "tournamentEntries", "x1");
    await assertSucceeds(getDoc(rec(PLAYER)));
    await assertFails(getDoc(rec(OUTSIDER)));
    await assertFails(setDoc(rec(OWNER), { name: "Fake", status: "accepted" }));
    await assertFails(updateDoc(rec(OWNER), { status: "accepted" }));
    await assertFails(deleteDoc(rec(PLAYER)));
    await assertSucceeds(deleteDoc(rec(OWNER)));
  });

  it("a team's name and level can be edited, but never its division", async () => {
    const team = (uid: string) => doc(db(uid), "teams", TEAM);
    await assertSucceeds(updateDoc(team(OWNER), { name: "Renamed", level: "club" }));
    await assertFails(updateDoc(team(OWNER), { division: "open" }));
    await assertFails(updateDoc(team(OWNER), { name: "Again", division: "women" }));
  });

  it("nobody becomes a coach or captain now; the owner moves them down", async () => {
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { [`members.${PLAYER}`]: "coach" }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: "coach" }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: "captain" }));
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { [`members.${CAPTAIN}`]: "player" }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${CAPTAIN}`]: "player" }));
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

  it("only the owner sets tiers, and only player is left to give", async () => {
    for (const role of ["coach", "captain"]) {
      await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${PLAYER}`]: role }));
    }
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${COACH}`]: "player" }));
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
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { [`members.${CAPTAIN}`]: "player" }));
    await assertSucceeds(updateDoc(doc(db(COACH), "teams", TEAM), { [`members.${CAPTAIN}`]: "player" }));
  });
});

describe("invite codes and admin", () => {
  const mint = (uid: string, code = "NEW234", extra: Record<string, unknown> = {}) =>
    setDoc(doc(db(uid), "inviteCodes", code), {
      teamId: TEAM,
      createdBy: uid,
      createdAt: serverTimestamp(),
      ttl: 45,
      expiresAt: new Date(Date.now() + 45 * SECOND),
      ...extra,
    });
  const link = (uid: string, ttl: number, code = TOKEN) =>
    mint(uid, code, { ttl, expiresAt: new Date(Date.now() + ttl * SECOND) });

  it("owners, coaches and captains mint codes; players and outsiders cannot", async () => {
    await assertSucceeds(mint(OWNER, "OWN234"));
    await assertSucceeds(mint(COACH, "COA234"));
    await assertSucceeds(mint(CAPTAIN, "CAP234"));
    await assertFails(mint(STATS, "STA234"));
    await assertFails(mint(PLAYER, "PLA234"));
    await assertFails(mint(OUTSIDER, "OUT234"));
  });

  it("codes last 45 seconds; links 1 hour, 1, 7 or 30 days", async () => {
    await assertFails(mint(COACH, "NEW234", { ttl: 3600 }), "a short code that lasts an hour");
    await assertFails(mint(COACH, "NEW234", { ttl: 60 }));
    await assertFails(link(COACH, 45), "a link token that lasts 45 seconds");
    await assertFails(link(COACH, 365 * 86400));
    await assertFails(link(COACH, 3600, "SHORT"));
    for (const [i, ttl] of [3600, 86400, 604800, 2592000].entries()) {
      await assertSucceeds(link(COACH, ttl, TOKEN.slice(0, 19) + i));
    }
  });

  it("codes are stamped by the server, for their minter, and never reused", async () => {
    await assertFails(mint(COACH, "NEW234", { createdAt: new Date(Date.now() + 3600 * SECOND) }));
    await assertFails(mint(COACH, "NEW234", { createdBy: OWNER }));
    await assertFails(mint(COACH, "NEW234", { expiresAt: new Date(Date.now() - SECOND) }));
    await assertFails(mint(COACH, "NEW234", { expiresAt: new Date(Date.now() + 3 * 86400 * SECOND) }));
    await assertFails(mint(COACH, "NEW234", { note: "hi" }));
    await assertFails(mint(COACH, CODE), "overwriting a live code");
  });

  it("groups have no codes", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", "g1"), {
        name: "Group", ownerId: OWNER, kind: "community",
        members: { [OWNER]: "owner" }, memberIds: [OWNER],
      }),
    );
    await assertFails(mint(OWNER, "GRP234", { teamId: "g1" }));
  });

  it("anyone signed in looks a code up; nobody lists them", async () => {
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "inviteCodes", CODE)));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "inviteCodes", CODE)));
    await assertFails(getDocs(query(collection(db(OWNER), "inviteCodes"), where("teamId", "==", TEAM))));
  });

  it("the minter or the owner revokes a code early", async () => {
    await assertFails(deleteDoc(doc(db(PLAYER), "inviteCodes", CODE)));
    await assertFails(deleteDoc(doc(db(CAPTAIN), "inviteCodes", CODE)));
    await assertSucceeds(deleteDoc(doc(db(COACH), "inviteCodes", CODE)));
    await assertSucceeds(mint(CAPTAIN, "CAP234"));
    await assertSucceeds(deleteDoc(doc(db(OWNER), "inviteCodes", "CAP234")));
  });

  it("admins clear an older team's code off the team doc", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "teams", TEAM), { inviteCode: CODE, joinCode: CODE }),
    );
    const clear = (uid: string) =>
      updateDoc(doc(db(uid), "teams", TEAM), { inviteCode: deleteField(), joinCode: deleteField() });
    await assertFails(clear(PLAYER));
    await assertSucceeds(clear(CAPTAIN));
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

  it("roster entries can't carry paid or the retired USA Ultimate status", async () => {
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

  it("admins link a roster spot to a member only", async () => {
    const ref = doc(db(CAPTAIN), "teams", TEAM, "roster", "r1");
    const spot = (userId: string | null) => ({ name: "Sam", number: 7, position: "handler", userId });
    await assertSucceeds(setDoc(ref, spot(PLAYER)));
    await assertSucceeds(setDoc(ref, spot(null)));
    await assertFails(setDoc(ref, spot(OUTSIDER)));
  });

  it("members claim an unlinked spot for themselves and let go of their own", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", TEAM, "roster", "r1"), { name: "Pat", number: 4, position: "cutter", userId: null });
      await setDoc(doc(fs, "teams", TEAM, "roster", "r2"), { name: "Cam", number: 5, position: "cutter", userId: CAPTAIN });
    });
    const spot = (uid: string, id: string) => doc(db(uid), "teams", TEAM, "roster", id);
    // Not for someone else, nor with other changes, nor someone's spot.
    await assertFails(updateDoc(spot(PLAYER, "r1"), { userId: STATS }));
    await assertFails(updateDoc(spot(PLAYER, "r1"), { userId: PLAYER, number: 99 }));
    await assertFails(updateDoc(spot(PLAYER, "r2"), { userId: PLAYER }));
    await assertFails(updateDoc(spot(PLAYER, "r2"), { userId: null }));
    await assertFails(updateDoc(spot(OUTSIDER, "r1"), { userId: OUTSIDER }));
    await assertSucceeds(updateDoc(spot(PLAYER, "r1"), { userId: PLAYER }));
    await assertSucceeds(updateDoc(spot(PLAYER, "r1"), { userId: null }));
  });
});

describe("roster status", () => {
  const status = (uid: string) => doc(db(uid), "teams", TEAM, "rosterStatus", "r1");

  beforeEach(() =>
    env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "rosterStatus", "r1"), { paid: false }),
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
    await assertSucceeds(setDoc(status(CAPTAIN), { paid: true }));
    await assertSucceeds(setDoc(status(OWNER), { paid: false }));
    await assertFails(setDoc(status(PLAYER), { paid: true }));
    await assertFails(setDoc(status(STATS), { paid: true }));
    await assertFails(setDoc(status(COACH), { paid: "yes" }));
    await assertFails(setDoc(status(COACH), { onUsau: true, paid: true }));
    await assertFails(setDoc(status(COACH), { paid: true, note: "cash" }));
    await assertFails(deleteDoc(status(PLAYER)));
    await assertSucceeds(deleteDoc(status(COACH)));
  });
});

describe("USA Ultimate link (removed)", () => {
  it("teams can't link a USA Ultimate page any more", async () => {
    const url = "https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc%3d";
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { usauUrl: url, usauName: "Ring" }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { usauSyncedAt: serverTimestamp() }));
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
    for (const type of ["practice", "game", "tournament", "scrimmage", "workout", "social", "other", "pickup"]) {
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

  it("the listing no longer carries a USA Ultimate page", async () => {
    await assertFails(
      setDoc(ref(COACH), listing({ usauUrl: "https://play.usaultimate.org/teams/events/Eventteam/?TeamId=1" })),
    );
  });

  it("a new team lists itself in its create batch", async () => {
    const fs = db(OUTSIDER);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", "t2"), {
      name: "New", division: "open", level: "college", city: "Denver",
      ownerId: OUTSIDER, members: { [OUTSIDER]: "owner" },
      memberIds: [OUTSIDER], memberNames: { [OUTSIDER]: "Me" },
    });
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

describe("meta", () => {
  it("is read-only for clients", async () => {
    await assertSucceeds(getDoc(doc(db(PLAYER), "meta", "flags")));
    await assertFails(setDoc(doc(db(PLAYER), "meta", "flags"), { use_api_search: true }));
  });

  it("no longer serves the USA Ultimate cache", async () => {
    await assertFails(getDoc(doc(db(PLAYER), "usau_tournaments", "x")));
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

  it("readers of a room react to its messages as themselves", async () => {
    const m1 = (uid: string) => doc(db(uid), "teams", TEAM, "chats", "r1", "messages", "m1");
    await assertSucceeds(updateDoc(m1(COACH), { [`reactions.${COACH}`]: "😂" }));
    await assertSucceeds(updateDoc(m1(STATS), { [`reactions.${STATS}`]: "👍" }));
    await assertFails(updateDoc(m1(COACH), { [`reactions.${STATS}`]: deleteField() }));
    await assertFails(updateDoc(m1(PLAYER), { [`reactions.${PLAYER}`]: "👍" }));
    await assertFails(updateDoc(m1(OUTSIDER), { [`reactions.${OUTSIDER}`]: "👍" }));
    await assertFails(updateDoc(m1(COACH), { [`reactions.${COACH}`]: "😂", text: "x" }));
  });

  it("a chat reply carries a valid quote", async () => {
    const quote = { id: "m1", authorId: CAPTAIN, authorName: "Cap", text: "Hi" };
    await assertSucceeds(setDoc(doc(messages(CAPTAIN)), message(CAPTAIN, { replyTo: quote })));
    await assertFails(setDoc(doc(messages(CAPTAIN)), message(CAPTAIN, { replyTo: { ...quote, id: "" } })));
  });

  it("owners, coaches and captains create rooms; players cannot", async () => {
    await assertSucceeds(setDoc(roomRef(COACH, "r2"), room()));
    await assertSucceeds(setDoc(roomRef(CAPTAIN, "r3"), room({ createdBy: CAPTAIN })));
    await assertFails(setDoc(roomRef(PLAYER, "r4"), room({ createdBy: PLAYER })));
    await assertFails(setDoc(roomRef(OUTSIDER, "r5"), room({ createdBy: OUTSIDER })));
  });

  it("validates rooms: writers must be readers, roles are known", async () => {
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ writeRoles: ["player"] })));
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ writeUsers: [PLAYER] })));
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ readRoles: Array.from({ length: 61 }, (_, i) => `r${i}`) })));
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ folderId: 7 })));
    await assertFails(setDoc(roomRef(COACH, "r2"), room({ position: "first" })));
    await assertSucceeds(setDoc(roomRef(COACH, "r2"), room({ folderId: "f1", position: 2 })));
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
    batch.set(doc(fs, "teams", "t2", "chats", "general"), {
      name: "General",
      readRoles: ["owner", "coach", "captain", "player"],
      writeRoles: ["owner", "coach", "captain", "player"],
      readUsers: [], writeUsers: [], createdBy: OUTSIDER, createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it("new teams get a voice folder and voice channels in the same batch", async () => {
    const fs = db(OUTSIDER);
    const batch = writeBatch(fs);
    batch.set(doc(fs, "teams", "t3"), {
      name: "New", division: "mixed", level: "club", city: "",
      ownerId: OUTSIDER, members: { [OUTSIDER]: "owner" }, memberIds: [OUTSIDER],
      memberNames: { [OUTSIDER]: "X" }, createdAt: serverTimestamp(),
    });
    batch.set(doc(fs, "teams", "t3", "chatFolders", "voice"), {
      name: "Voice Channels", position: 1000, readRoles: ["everyone"], writeRoles: ["everyone"],
      readUsers: [], writeUsers: [], createdBy: OUTSIDER, createdAt: serverTimestamp(),
    });
    batch.set(doc(fs, "teams", "t3", "chats", "voice-lounge"), {
      name: "Lounge", kind: "voice", folderId: "voice", position: 0,
      readRoles: ["everyone"], writeRoles: ["everyone"],
      readUsers: [], writeUsers: [], createdBy: OUTSIDER, createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it("rooms are text or voice, and keep their kind", async () => {
    await assertSucceeds(setDoc(roomRef(COACH, "v1"), room({ kind: "voice" })));
    await assertSucceeds(setDoc(roomRef(COACH, "t1"), room({ kind: "text" })));
    await assertFails(setDoc(roomRef(COACH, "x1"), room({ kind: "video" })));
    await assertFails(updateDoc(roomRef(COACH, "v1"), { kind: "text" }));
    await assertSucceeds(updateDoc(roomRef(COACH, "v1"), { name: "Lounge" }));
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

  it("authors delete their own messages; the owner and moderators who read the room delete any", async () => {
    const m1 = (uid: string) => doc(db(uid), "teams", TEAM, "chats", "r1", "messages", "m1");
    const restore = () =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "teams", TEAM, "chats", "r1", "messages", "m1"), {
          ...message(CAPTAIN),
          createdAt: new Date(),
        }),
      );
    await assertFails(deleteDoc(m1(PLAYER)));
    await assertSucceeds(deleteDoc(m1(CAPTAIN)));
    await restore();
    // Coaches moderate rooms they can read.
    await assertSucceeds(deleteDoc(m1(COACH)));
    await restore();
    await assertSucceeds(deleteDoc(m1(OWNER)));
  });

  it("chat managers change access and delete rooms they can read", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "chats", "secret"), {
        ...room({ readRoles: ["owner"], writeRoles: ["owner"], readUsers: [] }),
        createdAt: new Date(),
      }),
    );
    await assertSucceeds(updateDoc(roomRef(COACH), { readUsers: [STATS, PLAYER] }));
    await assertSucceeds(updateDoc(roomRef(COACH), { folderId: "f1", position: 3 }));
    await assertFails(updateDoc(roomRef(PLAYER), { readUsers: [PLAYER] }));
    await assertFails(updateDoc(roomRef(COACH), { createdBy: OWNER }));
    await assertFails(deleteDoc(roomRef(PLAYER)));
    await assertFails(deleteDoc(roomRef(COACH, "secret")));
    await assertSucceeds(deleteDoc(roomRef(COACH)));
    await assertSucceeds(deleteDoc(roomRef(OWNER, "secret")));
  });

  it("everyone means every member", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "teams", TEAM, "chats", "open"), {
        ...room({ readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [] }),
        createdAt: new Date(),
      }),
    );
    await assertSucceeds(getDoc(roomRef(PLAYER, "open")));
    await assertSucceeds(setDoc(doc(messages(PLAYER, "open")), message(PLAYER)));
    await assertFails(getDoc(roomRef(OUTSIDER, "open")));
    const chats = collection(db(PLAYER), "teams", TEAM, "chats");
    await assertSucceeds(getDocs(query(chats, where("readRoles", "array-contains", "everyone"))));
  });
});

describe("chat folders", () => {
  const folder = (overrides: Record<string, unknown> = {}) => ({
    name: "Coaching",
    position: 0,
    readRoles: ["coach"],
    writeRoles: ["coach"],
    readUsers: [],
    writeUsers: [],
    createdBy: COACH,
    createdAt: serverTimestamp(),
    ...overrides,
  });
  const ref = (uid: string, id = "f1") => doc(db(uid), "teams", TEAM, "chatFolders", id);

  it("chat managers create, edit and delete folders; members read them", async () => {
    await assertFails(setDoc(ref(PLAYER), folder({ createdBy: PLAYER })));
    await assertFails(setDoc(ref(COACH), folder({ name: "" })));
    await assertFails(setDoc(ref(COACH), folder({ writeRoles: ["player"] })));
    await assertFails(setDoc(ref(COACH), folder({ createdBy: OWNER })));
    await assertSucceeds(setDoc(ref(COACH), folder()));
    await assertSucceeds(getDoc(ref(PLAYER)));
    await assertFails(getDoc(ref(OUTSIDER)));
    await assertSucceeds(updateDoc(ref(CAPTAIN), { name: "Coaches", position: 2 }));
    await assertFails(updateDoc(ref(PLAYER), { name: "Mine" }));
    await assertFails(updateDoc(ref(COACH), { createdBy: PLAYER }));
    await assertFails(deleteDoc(ref(PLAYER)));
    await assertSucceeds(deleteDoc(ref(COACH)));
  });
});

describe("custom roles", () => {
  const roles = {
    h: { name: "Handlers", color: 0, position: 0, perms: [] },
    m: { name: "Chat mods", color: 0, position: 1, perms: ["manageChats", "moderate"] },
  };
  const assign = (memberRoles: Record<string, string[]>, memberPerms: Record<string, string[]>) => ({
    roles,
    memberRoles,
    memberPerms,
  });

  it("only the owner edits roles and assigns them, to members", async () => {
    const write = assign({ [PLAYER]: ["m"] }, { [PLAYER]: ["manageChats", "moderate"] });
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), write));
    await assertFails(updateDoc(doc(db(PLAYER), "teams", TEAM), write));
    await assertFails(
      updateDoc(doc(db(OWNER), "teams", TEAM), assign({ [OUTSIDER]: ["m"] }, {})),
    );
    await assertFails(
      updateDoc(doc(db(OWNER), "teams", TEAM), assign({}, { [OUTSIDER]: ["manageTeam"] })),
    );
    // Tiers don't go up in a role write.
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { ...write, [`members.${PLAYER}`]: "coach" }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), write));
  });

  it("the owner moves coaches and captains into roles, all at once", async () => {
    const tiers = {
      c: { name: "Coach", color: 0, position: 0, perms: ["manageTeam", "manageMembers", "keepStats"] },
      k: { name: "Captain", color: 0, position: 1, perms: ["manageTeam", "manageMembers", "keepStats"] },
    };
    const write = {
      roles: tiers,
      memberRoles: { [COACH]: ["c"], [CAPTAIN]: ["k"] },
      memberPerms: { [COACH]: tiers.c.perms, [CAPTAIN]: tiers.k.perms },
    };
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), write));
    // Only the owner, and not leaving one behind.
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), {
      [`members.${COACH}`]: "player", [`members.${CAPTAIN}`]: "player",
    }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), {
      [`members.${COACH}`]: "player", [`members.${CAPTAIN}`]: "player",
    }));
    // Their roles keep their powers.
    await assertSucceeds(updateDoc(doc(db(COACH), "teams", TEAM), { name: "Renamed" }));
    await assertFails(updateDoc(doc(db(PLAYER), "teams", TEAM), { name: "Nope" }));
  });

  it("permissions from roles open the matching powers", async () => {
    await assertFails(setDoc(doc(db(PLAYER), "teams", TEAM, "chats", "r9"), {
      name: "Mine", readRoles: ["everyone"], writeRoles: [], readUsers: [], writeUsers: [],
      createdBy: PLAYER, createdAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), assign(
      { [PLAYER]: ["m"] },
      { [PLAYER]: ["manageChats", "moderate"] },
    )));
    await assertSucceeds(setDoc(doc(db(PLAYER), "teams", TEAM, "chats", "r9"), {
      name: "Mine", readRoles: ["everyone"], writeRoles: [], readUsers: [], writeUsers: [],
      createdBy: PLAYER, createdAt: serverTimestamp(),
    }));
    // Chat powers only: no team details.
    await assertFails(updateDoc(doc(db(PLAYER), "teams", TEAM), { name: "Renamed" }));
  });

  it("a room that lets a role in lets its members read, list and post", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", TEAM, "chats", "handlers"), {
        name: "Handlers", readRoles: ["h"], writeRoles: ["h"], readUsers: [], writeUsers: [],
        createdBy: OWNER, createdAt: new Date(),
      });
    });
    const room = (uid: string) => doc(db(uid), "teams", TEAM, "chats", "handlers");
    const msgs = (uid: string) => collection(db(uid), "teams", TEAM, "chats", "handlers", "messages");
    const post = (uid: string) =>
      setDoc(doc(msgs(uid)), { authorId: uid, authorName: "N", text: "Hi", attachments: [], createdAt: serverTimestamp() });
    await assertFails(getDoc(room(PLAYER)));
    await assertFails(post(PLAYER));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), assign({ [PLAYER]: ["h"] }, {})));
    await assertSucceeds(getDoc(room(PLAYER)));
    await assertSucceeds(post(PLAYER));
    await assertSucceeds(getDocs(msgs(PLAYER)));
    const chats = collection(db(PLAYER), "teams", TEAM, "chats");
    await assertSucceeds(getDocs(query(chats, where("readRoles", "array-contains", "h"))));
    // Someone else's role doesn't open it.
    await assertFails(getDocs(query(chats, where("readRoles", "array-contains", "m"))));
    await assertFails(getDoc(room(STATS)));
  });

  it("removing a member takes their roles too; Manage members removes plain members only", async () => {
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), assign(
      { [PLAYER]: ["h"], [STATS]: ["m"] },
      { [STATS]: ["manageMembers"] },
    )));
    const removal = (uid: string) => ({
      [`members.${uid}`]: deleteField(),
      [`memberNames.${uid}`]: deleteField(),
      memberIds: arrayRemove(uid),
      statKeepers: arrayRemove(uid),
      [`memberRoles.${uid}`]: deleteField(),
      [`memberPerms.${uid}`]: deleteField(),
    });
    // Keeping their roles behind isn't allowed.
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), {
      [`members.${PLAYER}`]: deleteField(),
      [`memberNames.${PLAYER}`]: deleteField(),
      memberIds: arrayRemove(PLAYER),
    }));
    // STATS has Manage members but can't remove a coach.
    await assertFails(updateDoc(doc(db(STATS), "teams", TEAM), removal(COACH)));
    await assertSucceeds(updateDoc(doc(db(STATS), "teams", TEAM), removal(PLAYER)));
    // Coaches can't remove someone who holds permissions.
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), removal(STATS)));
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), removal(STATS)));
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

  it("profiles may carry a header photo URL", async () => {
    const ref = doc(db(PLAYER), "profiles", PLAYER);
    await assertSucceeds(setDoc(ref, { ...profile(), headerUrl: "https://example.test/h.jpg" }));
    await assertSucceeds(setDoc(ref, { ...profile(), headerUrl: null }));
    await assertFails(setDoc(ref, { ...profile(), headerUrl: 42 }));
    await assertFails(setDoc(ref, { ...profile(), headerUrl: "x".repeat(2001) }));
  });

  it("profiles carry player details and a published summary", async () => {
    const ref = doc(db(PLAYER), "profiles", PLAYER);
    const full = {
      ...profile(),
      tags: ["denver", "state"],
      bio: "Handler. Hucks.",
      pronouns: "they/them",
      hometown: "Denver",
      school: "State",
      throwingHand: "left",
      playingSince: 2015,
      visibility: { stats: true, teams: true, games: false },
      teams: [{ id: TEAM, name: "Tide", kind: "team", subtitle: "", role: "Player", number: 4, position: "Cutter" }],
      stats: { "2026": { games: 1, points: 10, goals: 2, assists: 1, blocks: 0, completions: 9, throwaways: 1, catches: 8, drops: 0 } },
      games: [],
      summaryUpdatedAt: serverTimestamp(),
    };
    await assertSucceeds(setDoc(ref, full));
    await assertFails(setDoc(ref, { ...full, bio: "x".repeat(281) }));
    await assertFails(setDoc(ref, { ...full, throwingHand: "foot" }));
    await assertFails(setDoc(ref, { ...full, playingSince: "long ago" }));
    await assertFails(setDoc(ref, { ...full, visibility: { email: true } }));
    await assertFails(setDoc(ref, { ...full, games: [1, 2, 3, 4, 5, 6] }));
    await assertFails(setDoc(ref, { ...full, followers: 10 }));
    await assertFails(setDoc(doc(db(OUTSIDER), "profiles", PLAYER), full));
  });

  it("participants start a conversation with a listed user", async () => {
    await assertSucceeds(getDoc(conv(PLAYER))); // checking it exists
    await assertSucceeds(setDoc(conv(PLAYER), newConv({ status: "request", requestedOf: OWNER })));
  });

  describe("who may start one", () => {
    const follow = (follower: string, followed: string) =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "users", follower, "follows", `user_${followed}`), {
          key: `user_${followed}`, type: "user", targetId: followed, name: "N", notify: true, createdAt: new Date(),
        }),
      );
    const policy = (uid: string, messagePolicy: string) =>
      env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), "users", uid), { messagePolicy }));
    const accepted = () => setDoc(conv(PLAYER), newConv({ status: "accepted" }));
    const request = (to = OWNER) => setDoc(conv(PLAYER), newConv({ status: "request", requestedOf: to }));

    it("someone who follows you reaches your inbox; anyone else is a request", async () => {
      await assertFails(accepted());
      await assertFails(setDoc(conv(PLAYER), newConv()));
      // A request is waiting on the other person, not on yourself.
      await assertFails(request(PLAYER));
      await assertSucceeds(request());
    });

    it("people the recipient follows go straight to their inbox", async () => {
      await follow(OWNER, PLAYER);
      await assertSucceeds(accepted());
    });

    it("'followers' takes requests only from followers", async () => {
      await policy(OWNER, "followers");
      await assertFails(request());
      await follow(PLAYER, OWNER);
      await assertSucceeds(request());
    });

    it("'following' takes nothing from people they don't follow", async () => {
      await policy(OWNER, "following");
      await follow(PLAYER, OWNER);
      await assertFails(request());
      await follow(OWNER, PLAYER);
      await assertSucceeds(accepted());
    });

    it("'nobody' takes nothing new", async () => {
      await policy(OWNER, "nobody");
      await follow(OWNER, PLAYER);
      await assertFails(accepted());
      await assertFails(request());
    });
  });

  it("muted users can't message until the mute ends; limits are server-only", async () => {
    const mute = (until: Date) =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "limits", PLAYER), { mutedUntil: until, counts: {} }),
      );
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "conversations", CONV), { ...newConv(), createdAt: new Date() }),
    );
    await assertSucceeds(setDoc(doc(msgs(PLAYER)), msg(PLAYER)));
    await mute(new Date(Date.now() + 10 * 60 * SECOND));
    await assertFails(setDoc(doc(msgs(PLAYER)), msg(PLAYER)));
    await assertSucceeds(setDoc(doc(msgs(OWNER)), msg(OWNER)));
    await mute(new Date(Date.now() - SECOND));
    await assertSucceeds(setDoc(doc(msgs(PLAYER)), msg(PLAYER)));
    // Users read only their own limits and can never clear a mute.
    await assertSucceeds(getDoc(doc(db(PLAYER), "limits", PLAYER)));
    await assertFails(getDoc(doc(db(OWNER), "limits", PLAYER)));
    await assertFails(setDoc(doc(db(PLAYER), "limits", PLAYER), { mutedUntil: new Date(0) }));
    await assertFails(deleteDoc(doc(db(PLAYER), "limits", PLAYER)));
  });

  it("participants say they're typing, only as themselves", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "conversations", CONV), { ...newConv(), createdAt: new Date() }),
    );
    const typing = (uid: string, who = uid, id = CONV) => doc(db(uid), "conversations", id, "typing", who);
    await assertSucceeds(setDoc(typing(PLAYER), { at: serverTimestamp() }));
    await assertSucceeds(setDoc(typing(PLAYER), { at: serverTimestamp() }));
    await assertSucceeds(getDoc(typing(OWNER, PLAYER)));
    await assertFails(getDoc(typing(OUTSIDER, PLAYER)));
    // Not as someone else, not with a made-up time or extra fields.
    await assertFails(setDoc(typing(OWNER, PLAYER), { at: serverTimestamp() }));
    await assertFails(setDoc(typing(OWNER), { at: new Date(2000, 0, 1) }));
    await assertFails(setDoc(typing(OWNER), { at: serverTimestamp(), text: "secret" }));
    // Not in someone else's conversation, or one that doesn't exist yet.
    await assertFails(setDoc(typing(OUTSIDER), { at: serverTimestamp() }));
    await assertFails(setDoc(typing(PLAYER, PLAYER, `${OUTSIDER}_${PLAYER}`), { at: serverTimestamp() }));
    await assertFails(deleteDoc(typing(OWNER, PLAYER)));
    await assertSucceeds(deleteDoc(typing(PLAYER)));
  });

  it("each user's read times are private to them", async () => {
    const read = (uid: string, owner = uid, id = CONV) => doc(db(uid), "users", owner, "dmReads", id);
    await assertSucceeds(setDoc(read(PLAYER), { readAt: serverTimestamp() }));
    await assertSucceeds(getDoc(read(PLAYER)));
    await assertFails(getDoc(read(OWNER, PLAYER)));
    await assertFails(setDoc(read(OWNER, PLAYER), { readAt: serverTimestamp() }));
    // Only conversations they're in, only a server time.
    await assertFails(setDoc(read(PLAYER, PLAYER, `${OWNER}_${OUTSIDER}`), { readAt: serverTimestamp() }));
    await assertFails(setDoc(read(PLAYER), { readAt: new Date(2000, 0, 1) }));
    await assertFails(setDoc(read(PLAYER), { readAt: serverTimestamp(), seen: true }));
  });

  it("the read receipts setting is the user's own", async () => {
    await assertSucceeds(setDoc(doc(db(PLAYER), "users", PLAYER), { readReceipts: false }, { merge: true }));
    await assertFails(setDoc(doc(db(OWNER), "users", PLAYER), { readReceipts: true }, { merge: true }));
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

    it("a reply carries a short quote of the message it answers", async () => {
      const quote = { id: "m1", authorId: OWNER, authorName: "Olive", text: "Ride?" };
      await assertSucceeds(setDoc(doc(msgs(PLAYER)), { ...msg(PLAYER), replyTo: quote }));
      await assertFails(setDoc(doc(msgs(PLAYER)), { ...msg(PLAYER), replyTo: { ...quote, text: "x".repeat(201) } }));
      await assertFails(setDoc(doc(msgs(PLAYER)), { ...msg(PLAYER), replyTo: { ...quote, extra: 1 } }));
      await assertFails(setDoc(doc(msgs(PLAYER)), { ...msg(PLAYER), replyTo: "m1" }));
    });

    it("participants react as themselves, and change nothing else", async () => {
      await env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "conversations", CONV, "messages", "m1"), {
          ...msg(OWNER), createdAt: new Date(), reactions: { [OWNER]: "👍" },
        }),
      );
      const m1 = (uid: string) => doc(db(uid), "conversations", CONV, "messages", "m1");
      await assertSucceeds(updateDoc(m1(PLAYER), { [`reactions.${PLAYER}`]: "❤️" }));
      await assertSucceeds(updateDoc(m1(PLAYER), { [`reactions.${PLAYER}`]: deleteField() }));
      await assertFails(updateDoc(m1(PLAYER), { [`reactions.${OWNER}`]: deleteField() }));
      await assertFails(updateDoc(m1(PLAYER), { [`reactions.${PLAYER}`]: "x".repeat(17) }));
      await assertFails(updateDoc(m1(PLAYER), { [`reactions.${PLAYER}`]: "❤️", text: "Edited" }));
      await assertFails(updateDoc(m1(COACH), { [`reactions.${COACH}`]: "❤️" }));
    });
  });

  describe("a message request", () => {
    // PLAYER asked OWNER.
    beforeEach(() =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "conversations", CONV), {
          ...newConv({ status: "request", requestedOf: OWNER }),
          createdAt: new Date(),
        }),
      ),
    );

    it("the sender keeps writing; the recipient reads without a receipt or reply", async () => {
      await assertSucceeds(setDoc(doc(msgs(PLAYER)), msg(PLAYER)));
      await assertSucceeds(getDocs(msgs(OWNER)));
      await assertFails(setDoc(doc(msgs(OWNER)), msg(OWNER)));
      await assertFails(updateDoc(conv(OWNER), { [`readAt.${OWNER}`]: serverTimestamp() }));
      // Their private read time is fine.
      await assertSucceeds(setDoc(doc(db(OWNER), "users", OWNER, "dmReads", CONV), { readAt: serverTimestamp() }));
    });

    it("only the recipient accepts or declines it", async () => {
      await assertFails(updateDoc(conv(PLAYER), { status: "accepted" }));
      await assertFails(updateDoc(conv(OWNER), { status: "request", requestedOf: PLAYER }));
      await assertFails(updateDoc(conv(OWNER), { status: "pending" }));
      await assertSucceeds(updateDoc(conv(OWNER), { status: "accepted" }));
      // Once accepted, they reply and send receipts, and it stays accepted.
      await assertSucceeds(setDoc(doc(msgs(OWNER)), msg(OWNER)));
      await assertSucceeds(updateDoc(conv(OWNER), { [`readAt.${OWNER}`]: serverTimestamp() }));
      await assertFails(updateDoc(conv(OWNER), { status: "declined" }));
    });

    it("declining it is quiet: the sender can still write", async () => {
      await assertSucceeds(updateDoc(conv(OWNER), { status: "declined" }));
      await assertSucceeds(setDoc(doc(msgs(PLAYER)), msg(PLAYER)));
      await assertFails(updateDoc(conv(OWNER), { status: "accepted" }));
    });
  });

  describe("groups", () => {
    const GROUP = "g-abcDEF123";
    const group = (uid: string, id = GROUP) => doc(db(uid), "conversations", id);
    const newGroup = (uid: string, overrides: Record<string, unknown> = {}) => ({
      kind: "group",
      name: "Hat league carpool",
      createdBy: uid,
      participants: [uid],
      names: { [uid]: "N" },
      lastMessage: "",
      lastMessageAt: null,
      lastSenderId: "",
      readAt: {},
      createdAt: serverTimestamp(),
      ...overrides,
    });
    const follow = (follower: string, followed: string) =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "users", follower, "follows", `user_${followed}`), {
          key: `user_${followed}`, type: "user", targetId: followed, name: "N", notify: true, createdAt: new Date(),
        }),
      );
    const add = (adder: string, before: string[], added: string) =>
      updateDoc(group(adder), { participants: [...before, added], [`names.${added}`]: "New" });
    const seed = (participants: string[], createdBy = OWNER) =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "conversations", GROUP), {
          ...newGroup(createdBy, { participants, names: Object.fromEntries(participants.map((p) => [p, "N"])) }),
          createdAt: new Date(),
        }),
      );

    beforeEach(() =>
      env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "profiles", COACH), { name: "Cory Coach", keywords: ["cory"], photoUrl: null });
        await setDoc(doc(ctx.firestore(), "profiles", OUTSIDER), { name: "Oz", keywords: ["oz"], photoUrl: null });
      }),
    );

    it("starts with just its creator", async () => {
      await assertFails(setDoc(group(OWNER), newGroup(OWNER, { participants: [OWNER, PLAYER] })));
      await assertFails(setDoc(group(OWNER), newGroup(PLAYER)));
      await assertFails(setDoc(group(OWNER), newGroup(OWNER, { name: "x".repeat(61) })));
      await assertFails(setDoc(group(OWNER, "g_bad"), newGroup(OWNER)));
      await assertFails(setDoc(group(OWNER), newGroup(OWNER, { status: "accepted" })));
      await assertSucceeds(setDoc(group(OWNER), newGroup(OWNER)));
    });

    it("members add people who follow them, one at a time", async () => {
      await seed([OWNER]);
      await assertFails(add(OWNER, [OWNER], PLAYER));
      await follow(PLAYER, OWNER);
      await follow(COACH, OWNER);
      await assertFails(updateDoc(group(OWNER), {
        participants: [OWNER, PLAYER, COACH], [`names.${PLAYER}`]: "P", [`names.${COACH}`]: "C",
      }));
      await assertSucceeds(add(OWNER, [OWNER], PLAYER));
      // Now a member, PLAYER adds people who follow PLAYER, not OWNER.
      await assertFails(add(PLAYER, [OWNER, PLAYER], COACH));
      await follow(COACH, PLAYER);
      await assertSucceeds(add(PLAYER, [OWNER, PLAYER], COACH));
      // Outsiders can't add themselves, or read it.
      await follow(OUTSIDER, OWNER);
      await assertFails(add(OUTSIDER, [OWNER, PLAYER, COACH], OUTSIDER));
      await assertFails(getDoc(group(OUTSIDER)));
      await assertSucceeds(getDoc(group(COACH)));
    });

    it("nobody is added who turned messages off, or past 10", async () => {
      await seed([OWNER]);
      await follow(PLAYER, OWNER);
      await env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), "users", PLAYER), { messagePolicy: "nobody" }),
      );
      await assertFails(add(OWNER, [OWNER], PLAYER));
      const ten = [OWNER, "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9"];
      await seed(ten);
      await follow(COACH, OWNER);
      await assertFails(add(OWNER, ten, COACH));
    });

    it("members leave; its creator removes anyone; nobody else does", async () => {
      await seed([OWNER, PLAYER, COACH]);
      await assertFails(updateDoc(group(PLAYER), { participants: arrayRemove(COACH) }));
      await assertSucceeds(updateDoc(group(PLAYER), { participants: arrayRemove(PLAYER) }));
      await assertFails(getDoc(group(PLAYER)));
      await assertSucceeds(updateDoc(group(OWNER), { participants: arrayRemove(COACH) }));
    });

    it("members post, rename it and keep private read records", async () => {
      await seed([OWNER, PLAYER]);
      const fs = db(PLAYER);
      const batch = writeBatch(fs);
      batch.set(doc(collection(fs, "conversations", GROUP, "messages")), msg(PLAYER));
      batch.update(doc(fs, "conversations", GROUP), {
        lastMessage: "Hi", lastMessageAt: serverTimestamp(), lastSenderId: PLAYER,
        [`readAt.${PLAYER}`]: serverTimestamp(), [`names.${PLAYER}`]: "Pat",
      });
      await assertSucceeds(batch.commit());
      await assertFails(setDoc(doc(collection(db(COACH), "conversations", GROUP, "messages")), msg(COACH)));
      await assertSucceeds(getDocs(collection(db(OWNER), "conversations", GROUP, "messages")));
      await assertFails(getDocs(collection(db(COACH), "conversations", GROUP, "messages")));
      await assertSucceeds(updateDoc(group(PLAYER), { name: "Carpool" }));
      await assertFails(updateDoc(group(COACH), { name: "Mine" }));
      await assertSucceeds(
        setDoc(doc(db(PLAYER), "users", PLAYER, "dmReads", GROUP), { readAt: serverTimestamp() }, { merge: true }),
      );
      await assertFails(
        setDoc(doc(db(COACH), "users", COACH, "dmReads", GROUP), { readAt: serverTimestamp() }, { merge: true }),
      );
      await assertSucceeds(setDoc(doc(db(PLAYER), "conversations", GROUP, "typing", PLAYER), { at: serverTimestamp() }));
    });
  });

  it("archive and delete-for-me are private, server-timed records", async () => {
    const mine = (uid: string, owner = uid) => doc(db(uid), "users", owner, "dmReads", CONV);
    await assertSucceeds(setDoc(mine(PLAYER), { archivedAt: serverTimestamp() }, { merge: true }));
    await assertSucceeds(setDoc(mine(PLAYER), { readAt: serverTimestamp() }, { merge: true }));
    // Unarchive by removing it.
    await assertSucceeds(updateDoc(mine(PLAYER), { archivedAt: deleteField() }));
    await assertSucceeds(setDoc(mine(PLAYER), { clearedAt: serverTimestamp() }, { merge: true }));
    await assertFails(setDoc(mine(PLAYER), { clearedAt: new Date(2000, 0, 1) }, { merge: true }));
    await assertFails(setDoc(mine(PLAYER), { archivedAt: new Date(2000, 0, 1) }, { merge: true }));
    // The deletion time and read time can't be taken back.
    await assertFails(updateDoc(mine(PLAYER), { clearedAt: deleteField() }));
    await assertFails(updateDoc(mine(PLAYER), { readAt: deleteField() }));
    await assertFails(setDoc(mine(PLAYER), { pinned: true }, { merge: true }));
    await assertFails(setDoc(mine(OWNER, PLAYER), { archivedAt: serverTimestamp() }, { merge: true }));
  });

  it("the message policy is the user's own", async () => {
    await assertSucceeds(setDoc(doc(db(PLAYER), "users", PLAYER), { messagePolicy: "nobody" }, { merge: true }));
    await assertFails(setDoc(doc(db(OWNER), "users", PLAYER), { messagePolicy: "everyone" }, { merge: true }));
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

  it("lets only the owner mark a team as being deleted, once it's theirs alone", async () => {
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { deletingAt: serverTimestamp() }));
    // Others are still on it.
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { deletingAt: serverTimestamp() }));
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "teams", TEAM), {
        members: { [OWNER]: "owner" },
        memberIds: [OWNER],
      }),
    );
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

describe("follows", () => {
  const ref = (uid: string, key: string, owner = uid) => doc(db(uid), "users", owner, "follows", key);
  const follow = (type: string, targetId: string, extra: Record<string, unknown> = {}) => ({
    key: `${type}_${targetId}`,
    type,
    targetId,
    name: "Hawks",
    notify: false,
    createdAt: serverTimestamp(),
    ...extra,
  });

  it("lets people follow users, teams and tournaments", async () => {
    await assertSucceeds(setDoc(ref(PLAYER, "user_u2"), follow("user", "u2", { photoUrl: "https://x.org/a.png" })));
    await assertSucceeds(setDoc(ref(PLAYER, `team_${TEAM}`), follow("team", TEAM, { notify: true })));
    await assertSucceeds(
      setDoc(ref(PLAYER, "tournament_g1_t1"), follow("tournament", "g1_t1", { groupId: "g1" })),
    );
  });

  it("keeps follows private and well-formed", async () => {
    await assertFails(setDoc(ref(OUTSIDER, "team_x", PLAYER), follow("team", "x")));
    await assertFails(setDoc(ref(PLAYER, "team_x"), follow("team", "y")));
    await assertFails(setDoc(ref(PLAYER, "page_x"), follow("page", "x")));
    // USA Ultimate events can't be followed any more.
    await assertFails(setDoc(ref(PLAYER, "event_123"), follow("event", "123")));
    await assertFails(setDoc(ref(PLAYER, `user_${PLAYER}`), follow("user", PLAYER)));
    await assertFails(setDoc(ref(PLAYER, "tournament_g1_t1"), follow("tournament", "g1_t1")));
    await assertFails(setDoc(ref(PLAYER, "tournament_g1_t1"), follow("tournament", "g1_t1", { groupId: "g2" })));
    await assertFails(setDoc(ref(PLAYER, "team_x"), follow("team", "x", { notify: "yes" })));
    await assertFails(setDoc(ref(PLAYER, "team_x"), follow("team", "x", { extra: 1 })));
    await assertFails(setDoc(ref(PLAYER, "team_x"), follow("team", "x", { createdAt: new Date("2020-01-01") })));

    await assertSucceeds(setDoc(ref(PLAYER, "team_x"), follow("team", "x")));
    await assertFails(getDoc(ref(OUTSIDER, "team_x", PLAYER)));
    await assertSucceeds(getDoc(ref(PLAYER, "team_x")));
  });

  it("lets the bell be switched but nothing else changed", async () => {
    await assertSucceeds(setDoc(ref(PLAYER, "team_x"), follow("team", "x")));
    await assertSucceeds(updateDoc(ref(PLAYER, "team_x"), { notify: true }));
    await assertFails(updateDoc(ref(PLAYER, "team_x"), { targetId: "y" }));
    await assertFails(updateDoc(ref(OUTSIDER, "team_x", PLAYER), { notify: false }));
    await assertSucceeds(deleteDoc(ref(PLAYER, "team_x")));
  });

  it("lets anyone signed in read follower counts, nobody write them", async () => {
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "followCounts", "team_x")));
    await assertFails(setDoc(doc(db(OUTSIDER), "followCounts", "team_x"), { followers: 1000 }));
  });

  it("accepts the posts notification category", async () => {
    await assertSucceeds(
      setDoc(doc(db(PLAYER), "users", PLAYER, "settings", "notifications"), {
        categories: { posts: false, social: false },
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe("rankings", () => {
  it("lets anyone signed in read rankings and results, and nobody write them", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "rankings", "club-mixed"), { teams: [] });
      await setDoc(doc(ctx.firestore(), "tournamentResults", "recent"), { tournaments: [] });
    });
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "rankings", "club-mixed")));
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "tournamentResults", "recent")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "rankings", "club-mixed")));
    await assertFails(setDoc(doc(db(OWNER), "rankings", "club-mixed"), { teams: [] }));
    await assertFails(setDoc(doc(db(OWNER), "tournamentResults", "recent"), { tournaments: [] }));
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "playerRankings", "all")));
    await assertFails(setDoc(doc(db(PLAYER), "playerRankings", "all"), { players: [] }));
  });
});

describe("user posts", () => {
  const ref = (uid: string, id = "p1") => doc(db(uid), "posts", id);
  const post = (uid: string, extra: Record<string, unknown> = {}) => ({
    kind: "text",
    body: "Good throws today",
    links: [],
    images: [],
    workout: null,
    tournamentKey: null,
    tournamentName: null,
    authorId: uid,
    authorName: "P",
    authorPhotoUrl: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  });
  const workout = (extra: Record<string, unknown> = {}) => ({
    activity: "gym",
    durationMinutes: 60,
    effort: 7,
    exercises: [{ name: "Squat", sets: 3, reps: 5, weight: "100 kg" }, { name: "Plank" }],
    ...extra,
  });

  it("lets anyone signed in post as themselves and read every post", async () => {
    await assertSucceeds(setDoc(ref(PLAYER), post(PLAYER)));
    await assertFails(setDoc(ref(PLAYER, "p2"), post(OUTSIDER)));
    await assertSucceeds(getDoc(ref(OUTSIDER)));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "posts", "p1")));
  });

  it("validates text posts", async () => {
    await assertFails(setDoc(ref(PLAYER), post(PLAYER, { body: "" })));
    await assertFails(setDoc(ref(PLAYER), post(PLAYER, { kind: "poll" })));
    await assertFails(setDoc(ref(PLAYER), post(PLAYER, { workout: workout() })));
    await assertFails(setDoc(ref(PLAYER), post(PLAYER, { links: ["ftp://x.org"] })));
    await assertFails(setDoc(ref(PLAYER), post(PLAYER, { pinned: true })));
    await assertFails(setDoc(ref(PLAYER), post(PLAYER, { createdAt: new Date("2020-01-01") })));
    await assertSucceeds(
      setDoc(ref(PLAYER), post(PLAYER, { tournamentKey: "tournament_g1_t1", tournamentName: "Fall Hat" })),
    );
    await assertFails(setDoc(ref(PLAYER, "p3"), post(PLAYER, { tournamentKey: "event_123" })));
    await assertFails(setDoc(ref(PLAYER, "p2"), post(PLAYER, { tournamentKey: "team_x" })));
  });

  it("validates workouts", async () => {
    await assertSucceeds(setDoc(ref(PLAYER), post(PLAYER, { kind: "workout", body: "", workout: workout() })));
    await assertSucceeds(
      setDoc(ref(PLAYER, "run"), post(PLAYER, {
        kind: "workout",
        workout: { activity: "run", durationMinutes: 40, distanceKm: 8.5, exercises: [] },
      })),
    );
    for (const bad of [
      workout({ activity: "nap" }),
      workout({ durationMinutes: 0 }),
      workout({ durationMinutes: 2000 }),
      workout({ distanceKm: -1 }),
      workout({ effort: 11 }),
      workout({ exercises: [{ name: "" }] }),
      workout({ exercises: [{ name: "Squat", sets: 0 }] }),
      workout({ exercises: Array(21).fill({ name: "Squat" }) }),
      workout({ calories: 500 }),
    ]) {
      await assertFails(setDoc(ref(PLAYER, "bad"), post(PLAYER, { kind: "workout", workout: bad })));
    }
    await assertFails(setDoc(ref(PLAYER, "bad"), post(PLAYER, { kind: "workout", workout: null })));
  });

  it("validates recorded routes", async () => {
    const route = (extra: Record<string, unknown> = {}) => ({
      path: "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
      splitsMi: [512, 498],
      splitsKm: [318, 310, 305],
      elevationGainM: 24,
      ...extra,
    });
    const ride = (extra: Record<string, unknown> = {}) => ({
      activity: "ride",
      durationMinutes: 17,
      durationSeconds: 1001,
      distanceKm: 3.4,
      exercises: [],
      route: route(),
      ...extra,
    });
    await assertSucceeds(setDoc(ref(PLAYER, "ride"), post(PLAYER, { kind: "workout", workout: ride() })));
    for (const activity of ["run", "walk", "hike"]) {
      await assertSucceeds(
        setDoc(ref(PLAYER, activity), post(PLAYER, { kind: "workout", workout: ride({ activity }) })),
      );
    }
    for (const bad of [
      ride({ durationSeconds: 0 }),
      ride({ durationSeconds: 90000 }),
      ride({ durationSeconds: 1.5 }),
      ride({ route: route({ path: "" }) }),
      ride({ route: route({ path: "a".repeat(80001) }) }),
      ride({ route: route({ splitsMi: Array(1001).fill(300) }) }),
      ride({ route: route({ elevationGainM: -5 }) }),
      ride({ route: route({ heartRate: [140] }) }),
      ride({ route: "not a map" }),
    ]) {
      await assertFails(setDoc(ref(PLAYER, "bad"), post(PLAYER, { kind: "workout", workout: bad })));
    }
  });

  it("validates shared events", async () => {
    const event = (extra: Record<string, unknown> = {}) => ({
      eventId: "e1",
      title: "Pickup at the park",
      type: "pickup",
      startsAt: new Date("2026-11-07T18:00:00Z"),
      endsAt: new Date("2026-11-07T20:00:00Z"),
      location: "City Park",
      teamId: TEAM,
      teamName: "Northside Flyers",
      ...extra,
    });
    const shared = (e: unknown, extra: Record<string, unknown> = {}) =>
      post(PLAYER, { kind: "event", body: "", event: e, ...extra });
    // A team event goes to its members' feeds, so only someone who runs
    // that schedule may share it.
    await assertFails(setDoc(ref(PLAYER, "ev"), shared(event())));
    await assertFails(setDoc(ref(PLAYER, "ev"), shared(event({ teamId: "no-such-team" }))));
    await assertSucceeds(
      setDoc(doc(db(COACH), "posts", "ev"), { ...shared(event()), authorId: COACH }),
    );
    await assertFails(
      updateDoc(doc(db(COACH), "posts", "ev"), { event: event({ teamId: "other" }), updatedAt: serverTimestamp() }),
    );
    await assertSucceeds(
      updateDoc(doc(db(COACH), "posts", "ev"), { body: "See you there", updatedAt: serverTimestamp() }),
    );
    await assertSucceeds(setDoc(ref(PLAYER, "ev"), shared(event({ teamId: null, teamName: null }))));
    // A personal event: no team, no end, no place.
    await assertSucceeds(
      setDoc(ref(PLAYER, "mine"), shared({ eventId: "m1", title: "Tempo run", type: "workout", startsAt: new Date() })),
    );
    for (const bad of [
      null,
      event({ title: "" }),
      event({ eventId: "" }),
      event({ type: "meeting" }),
      event({ startsAt: "tomorrow" }),
      event({ endsAt: 5 }),
      event({ location: "x".repeat(201) }),
      event({ rsvps: {} }),
    ]) {
      await assertFails(setDoc(ref(PLAYER, "bad"), shared(bad)));
    }
    // Only an event post carries an event, and not with a workout.
    await assertFails(setDoc(ref(PLAYER, "bad"), post(PLAYER, { event: event() })));
    await assertFails(setDoc(ref(PLAYER, "bad"), shared(event(), { workout: workout() })));
    await assertFails(
      setDoc(ref(PLAYER, "bad"), post(PLAYER, { kind: "workout", workout: workout(), event: event() })),
    );
    // Old posts without an event field can still be edited.
    await assertSucceeds(setDoc(ref(PLAYER), post(PLAYER)));
    await assertSucceeds(updateDoc(ref(PLAYER), { body: "Edited", event: null, updatedAt: serverTimestamp() }));
  });

  it("lets anyone like a post, toggling only themselves", async () => {
    await assertSucceeds(setDoc(ref(PLAYER), post(PLAYER)));
    const as = (uid: string) => doc(db(uid), "posts", "p1");
    await assertSucceeds(updateDoc(as(OUTSIDER), { likedBy: arrayUnion(OUTSIDER) }));
    await assertSucceeds(updateDoc(as(PLAYER), { likedBy: arrayUnion(PLAYER) }));
    await assertSucceeds(updateDoc(as(OUTSIDER), { likedBy: arrayRemove(OUTSIDER) }));
    // Not someone else, and nothing else at the same time.
    await assertFails(updateDoc(as(OUTSIDER), { likedBy: arrayRemove(PLAYER) }));
    await assertFails(updateDoc(as(OUTSIDER), { likedBy: [OUTSIDER, "fake"] }));
    await assertFails(updateDoc(as(OUTSIDER), { likedBy: arrayUnion(OUTSIDER), body: "Hijack" }));
    // repostedBy only comes with a repost.
    await assertFails(updateDoc(as(OUTSIDER), { repostedBy: arrayUnion(OUTSIDER) }));
  });

  it("lets people repost someone's post, once, with a note", async () => {
    await assertSucceeds(setDoc(ref(PLAYER, "orig"), post(PLAYER)));
    const repostRef = (uid: string, id = `r_orig_${uid}`) => doc(db(uid), "posts", id);
    const repost = (uid: string, extra: Record<string, unknown> = {}) => ({
      ...post(uid, { kind: "repost", body: "Look!" }),
      repostOf: { postId: "orig", authorId: PLAYER, authorName: "P" },
      ...extra,
    });
    const doRepost = (uid: string, data: Record<string, unknown>, id?: string) => {
      const batch = writeBatch(db(uid));
      batch.set(repostRef(uid, id), data);
      batch.update(doc(db(uid), "posts", "orig"), { repostedBy: arrayUnion(uid) });
      return batch.commit();
    };
    // The repost alone, without counting it, fails; so does the reverse.
    await assertFails(setDoc(repostRef(OUTSIDER), repost(OUTSIDER)));
    await assertSucceeds(doRepost(OUTSIDER, repost(OUTSIDER)));
    // Only the note can change.
    await assertSucceeds(updateDoc(repostRef(OUTSIDER), { body: "Carpool?", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(repostRef(OUTSIDER), { repostOf: null }));
    // Undo: delete it and drop yourself together.
    const undo = writeBatch(db(OUTSIDER));
    undo.delete(repostRef(OUTSIDER));
    undo.update(doc(db(OUTSIDER), "posts", "orig"), { repostedBy: arrayRemove(OUTSIDER) });
    await assertSucceeds(undo.commit());

    for (const [uid, data, id] of [
      [OUTSIDER, repost(OUTSIDER), "r_orig_someone"],
      [OUTSIDER, repost(OUTSIDER, { repostOf: { postId: "orig", authorId: OUTSIDER, authorName: "P" } }), undefined],
      [OUTSIDER, repost(OUTSIDER, { images: [{ path: "x" }] }), undefined],
      [OUTSIDER, repost(OUTSIDER, { kind: "text" }), undefined],
      [PLAYER, repost(PLAYER), undefined],
    ] as const) {
      await assertFails(doRepost(uid, data, id));
    }
  });

  it("lets anyone comment; the commenter or the post's author deletes", async () => {
    await assertSucceeds(setDoc(ref(PLAYER), post(PLAYER)));
    const comment = (uid: string, id = "c1") => doc(db(uid), "posts", "p1", "comments", id);
    const data = (uid: string, extra: Record<string, unknown> = {}) => ({
      body: "Nice!",
      authorId: uid,
      authorName: "O",
      authorPhotoUrl: null,
      createdAt: serverTimestamp(),
      ...extra,
    });
    await assertSucceeds(setDoc(comment(OUTSIDER), data(OUTSIDER)));
    await assertSucceeds(getDoc(comment(CAPTAIN)));
    // As themselves, with text, and nothing else.
    await assertFails(setDoc(comment(OUTSIDER, "c2"), data(PLAYER)));
    await assertFails(setDoc(comment(OUTSIDER, "c2"), data(OUTSIDER, { body: "" })));
    await assertFails(setDoc(comment(OUTSIDER, "c2"), data(OUTSIDER, { body: "x".repeat(1001) })));
    await assertFails(setDoc(comment(OUTSIDER, "c2"), data(OUTSIDER, { pinned: true })));
    await assertFails(setDoc(comment(OUTSIDER, "c2"), data(OUTSIDER, { createdAt: new Date("2020-01-01") })));
    // Only its author edits, with the server's time; nobody else deletes.
    await assertFails(updateDoc(comment(OUTSIDER), { body: "Edited" }));
    await assertFails(updateDoc(comment(CAPTAIN), { body: "Edited", editedAt: serverTimestamp() }));
    await assertFails(updateDoc(comment(OUTSIDER), { body: "", editedAt: serverTimestamp() }));
    await assertFails(updateDoc(comment(OUTSIDER), { body: "Edited", editedAt: serverTimestamp(), authorId: CAPTAIN }));
    await assertSucceeds(updateDoc(comment(OUTSIDER), { body: "Edited", editedAt: serverTimestamp() }));
    await assertFails(deleteDoc(comment(CAPTAIN)));
    // The commenter, or the post's author.
    await assertSucceeds(setDoc(comment(OUTSIDER, "c2"), data(OUTSIDER)));
    await assertSucceeds(deleteDoc(comment(OUTSIDER)));
    await assertSucceeds(deleteDoc(comment(PLAYER, "c2")));
    // Not on a post that doesn't exist, and nobody sets commentCount.
    await assertFails(setDoc(doc(db(OUTSIDER), "posts", "gone", "comments", "c1"), data(OUTSIDER)));
    await assertFails(updateDoc(ref(OUTSIDER), { commentCount: 5 }));
    await assertFails(updateDoc(ref(PLAYER), { commentCount: 5 }));
  });

  it("replies thread one level under a comment on the same post", async () => {
    await assertSucceeds(setDoc(ref(PLAYER), post(PLAYER)));
    const comment = (uid: string, id: string) => doc(db(uid), "posts", "p1", "comments", id);
    const data = (uid: string, extra: Record<string, unknown> = {}) => ({
      body: "Nice!",
      authorId: uid,
      authorName: "O",
      createdAt: serverTimestamp(),
      ...extra,
    });
    await assertSucceeds(setDoc(comment(OUTSIDER, "top"), data(OUTSIDER)));
    await assertSucceeds(setDoc(comment(CAPTAIN, "r1"), data(CAPTAIN, { parentId: "top" })));
    // Replying to a reply goes under the same top-level comment, naming whom.
    await assertSucceeds(setDoc(comment(PLAYER, "r2"), data(PLAYER, { parentId: "top", replyToName: "C" })));
    await assertFails(setDoc(comment(PLAYER, "r3"), data(PLAYER, { parentId: "r1" })));
    await assertFails(setDoc(comment(PLAYER, "r4"), data(PLAYER, { parentId: "missing" })));
    await assertFails(setDoc(comment(PLAYER, "r5"), data(PLAYER, { replyToName: "C" })));
    await assertFails(setDoc(comment(PLAYER, "r6"), data(PLAYER, { parentId: "top", replyToName: "x".repeat(81) })));
  });

  it("anyone likes a comment, toggling only themselves", async () => {
    await assertSucceeds(setDoc(ref(PLAYER), post(PLAYER)));
    const comment = (uid: string) => doc(db(uid), "posts", "p1", "comments", "c1");
    await assertSucceeds(
      setDoc(comment(OUTSIDER), { body: "Nice!", authorId: OUTSIDER, authorName: "O", createdAt: serverTimestamp() }),
    );
    await assertSucceeds(updateDoc(comment(CAPTAIN), { likedBy: arrayUnion(CAPTAIN) }));
    await assertSucceeds(updateDoc(comment(PLAYER), { likedBy: arrayUnion(PLAYER) }));
    await assertFails(updateDoc(comment(PLAYER), { likedBy: [PLAYER] }));
    await assertFails(updateDoc(comment(OUTSIDER), { likedBy: arrayUnion("someone-else") }));
    await assertFails(updateDoc(comment(CAPTAIN), { likedBy: arrayUnion(CAPTAIN), body: "Mine now" }));
    await assertSucceeds(updateDoc(comment(CAPTAIN), { likedBy: arrayRemove(CAPTAIN) }));
  });

  it("comments on a repost go on its original", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "posts", "r_p1_x"), {
        kind: "repost",
        authorId: OUTSIDER,
        repostOf: { postId: "p1", authorId: PLAYER, authorName: "P" },
      });
    });
    await assertFails(
      setDoc(doc(db(CAPTAIN), "posts", "r_p1_x", "comments", "c1"), {
        body: "Hi",
        authorId: CAPTAIN,
        authorName: "C",
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("lets only the author edit or delete", async () => {
    await assertSucceeds(setDoc(ref(PLAYER), post(PLAYER)));
    await assertSucceeds(updateDoc(ref(PLAYER), { body: "Great throws today", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(PLAYER), { authorId: OUTSIDER }));
    await assertFails(updateDoc(ref(OUTSIDER), { body: "Hijack" }));
    await assertFails(deleteDoc(ref(OUTSIDER)));
    await assertSucceeds(deleteDoc(ref(PLAYER)));
  });

  it("team posts may name one of the group's own tournaments", async () => {
    const teamPost = (key: string) => ({
      title: "",
      body: "Sign up!",
      public: true,
      tournamentKey: key,
      authorId: COACH,
      authorName: "C",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(setDoc(doc(db(COACH), "teams", TEAM, "posts", "a"), teamPost(`tournament_${TEAM}_t1`)));
    await assertFails(setDoc(doc(db(COACH), "teams", TEAM, "posts", "b"), teamPost("tournament_other_t1")));
  });
});

describe("tournament directory", () => {
  const GROUP = "group1";
  const ORGANIZER = "organizer";
  const MEMBER = "member";
  const ref = (uid: string, id = `${GROUP}_t1`) => doc(db(uid), "tournamentDirectory", id);
  const listing = (extra: Record<string, unknown> = {}) => ({
    groupId: GROUP,
    tournamentId: "t1",
    name: "Fall Hat",
    startsAt: new Date(),
    endsOn: null,
    status: "setup",
    format: "roundRobin",
    ...extra,
  });

  beforeEach(() =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "teams", GROUP), {
        name: "Pickup Crew",
        kind: "community",
        ownerId: OWNER,
        members: { [OWNER]: "owner", [ORGANIZER]: "captain", [MEMBER]: "player" },
        memberIds: [OWNER, ORGANIZER, MEMBER],
      });
    }),
  );

  it("lets organizers list their group's tournaments", async () => {
    await assertSucceeds(setDoc(ref(ORGANIZER), listing()));
    await assertSucceeds(updateDoc(ref(ORGANIZER), { status: "scheduled" }));
    await assertFails(setDoc(ref(MEMBER, `${GROUP}_t2`), listing({ tournamentId: "t2" })));
    await assertFails(setDoc(ref(OUTSIDER, `${GROUP}_t3`), listing({ tournamentId: "t3" })));
  });

  it("checks the id and fields, and teams can't list", async () => {
    await assertFails(setDoc(ref(ORGANIZER, `${GROUP}_t9`), listing()));
    await assertFails(setDoc(ref(ORGANIZER), listing({ status: "live" })));
    await assertFails(setDoc(ref(ORGANIZER), listing({ secret: 1 })));
    await assertFails(setDoc(ref(OWNER, `${TEAM}_t1`), listing({ groupId: TEAM })));
  });

  it("is public to anyone signed in; organizers delete", async () => {
    await assertSucceeds(setDoc(ref(ORGANIZER), listing()));
    await assertSucceeds(getDoc(ref(OUTSIDER)));
    await assertFails(deleteDoc(ref(MEMBER)));
    await assertSucceeds(deleteDoc(ref(ORGANIZER)));
  });
});

describe("usernames", () => {
  const profile = (extra: Record<string, unknown> = {}) => ({
    name: "Pat Player", keywords: ["pat"], photoUrl: null, updatedAt: serverTimestamp(), ...extra,
  });
  const claim = (uid: string, name: string, profileExtra: Record<string, unknown> = {}) => {
    const fs = db(uid);
    return writeBatch(fs)
      .set(doc(fs, "usernames", name), { uid, createdAt: serverTimestamp() })
      .set(doc(fs, "profiles", uid), profile({ username: name, ...profileExtra }), { merge: true })
      .commit();
  };

  it("an account claims one free username, with its profile", async () => {
    await assertSucceeds(getDoc(doc(db(PLAYER), "usernames", "pat")));
    await assertSucceeds(claim(PLAYER, "pat.player"));
    // Taken: by someone else, or a second one for the same account.
    await assertFails(claim(OWNER, "pat.player"));
    await assertFails(claim(PLAYER, "pat2"));
    await assertSucceeds(claim(OWNER, "olive_o"));
  });

  it("signed out, you can only see that a name is free", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, "usernames", "pat.player")));
    await assertSucceeds(claim(PLAYER, "pat.player"));
    // Taken: refused, so whose it is never leaks.
    await assertFails(getDoc(doc(anon, "usernames", "pat.player")));
    await assertSucceeds(getDoc(doc(db(OWNER), "usernames", "pat.player")));
    await assertFails(setDoc(doc(anon, "usernames", "olive"), { uid: OWNER, createdAt: serverTimestamp() }));
  });

  it("rejects bad names and claims that don't match the profile", async () => {
    for (const bad of ["Pat", "pa", "a".repeat(21), ".pat", "pat.", "pa..t", "pat lee", "pat!"]) {
      await assertFails(claim(PLAYER, bad));
    }
    const fs = db(PLAYER);
    // A claim alone, or for someone else.
    await assertFails(setDoc(doc(fs, "usernames", "pat"), { uid: PLAYER, createdAt: serverTimestamp() }));
    await assertFails(writeBatch(fs)
      .set(doc(fs, "usernames", "pat"), { uid: OWNER, createdAt: serverTimestamp() })
      .set(doc(fs, "profiles", PLAYER), profile({ username: "pat" }))
      .commit());
    // A profile naming a username nobody claimed.
    await assertFails(setDoc(doc(fs, "profiles", PLAYER), profile({ username: "ghost" })));
  });

  it("a username can't be changed, deleted or taken over", async () => {
    await assertSucceeds(claim(PLAYER, "pat"));
    const fs = db(PLAYER);
    await assertFails(setDoc(doc(fs, "profiles", PLAYER), { username: "other" }, { merge: true }));
    // Other profile writes keep it.
    await assertSucceeds(setDoc(doc(fs, "profiles", PLAYER), profile({ bio: "Cutter" }), { merge: true }));
    await assertFails(deleteDoc(doc(fs, "usernames", "pat")));
    await assertFails(setDoc(doc(db(OWNER), "usernames", "pat"), { uid: OWNER, createdAt: serverTimestamp() }));
  });
});

describe("private profiles", () => {
  const followDoc = (follower: string, target: string, as = follower) =>
    doc(db(as), "users", follower, "follows", `user_${target}`);
  const userFollow = (target: string, extra: Record<string, unknown> = {}) => ({
    key: `user_${target}`,
    type: "user",
    targetId: target,
    name: "Pat Player",
    photoUrl: null,
    notify: false,
    createdAt: serverTimestamp(),
    ...extra,
  });
  const request = (requester: string, owner = PLAYER, as = requester) =>
    doc(db(as), "profiles", owner, "followRequests", requester);
  const requestData = { name: "Olive Owner", username: "olive", photoUrl: null, createdAt: serverTimestamp() };
  const details = (as: string) => doc(db(as), "profiles", PLAYER, "private", "details");

  beforeEach(async () => {
    const fs = db(PLAYER);
    await assertSucceeds(
      writeBatch(fs)
        .set(doc(fs, "profiles", PLAYER), {
          name: "Pat Player", keywords: ["pat"], photoUrl: null, tags: [], updatedAt: serverTimestamp(), private: true,
        })
        .set(doc(fs, "profiles", PLAYER, "private", "details"), {
          bio: "Handler", tags: ["hawks"], teams: [], updatedAt: serverTimestamp(),
        })
        .commit(),
    );
  });

  it("shows strangers only the public doc, and won't let them just follow", async () => {
    await assertSucceeds(getDoc(doc(db(OUTSIDER), "profiles", PLAYER)));
    await assertFails(getDoc(details(OUTSIDER)));
    await assertFails(setDoc(followDoc(OUTSIDER, PLAYER), userFollow(PLAYER)));
    // Nor approve themselves.
    await assertFails(setDoc(followDoc(OUTSIDER, PLAYER), userFollow(PLAYER, { approved: true })));
    await assertSucceeds(getDoc(details(PLAYER)));
  });

  it("an accepted request lets them follow and see everything", async () => {
    await assertSucceeds(setDoc(request(OUTSIDER), requestData));
    await assertSucceeds(getDoc(request(OUTSIDER)));
    await assertFails(getDoc(request(OUTSIDER, PLAYER, OWNER)));
    await assertSucceeds(getDocs(collection(db(PLAYER), "profiles", PLAYER, "followRequests")));

    // Without removing the request, or for someone who didn't ask: no.
    await assertFails(setDoc(followDoc(OUTSIDER, PLAYER, PLAYER), userFollow(PLAYER, { approved: true })));
    const fs = db(PLAYER);
    await assertFails(
      writeBatch(fs)
        .set(doc(fs, "users", OWNER, "follows", `user_${PLAYER}`), userFollow(PLAYER, { approved: true }))
        .delete(doc(fs, "profiles", PLAYER, "followRequests", OUTSIDER))
        .commit(),
    );
    await assertSucceeds(
      writeBatch(fs)
        .set(doc(fs, "users", OUTSIDER, "follows", `user_${PLAYER}`), userFollow(PLAYER, { approved: true }))
        .delete(doc(fs, "profiles", PLAYER, "followRequests", OUTSIDER))
        .commit(),
    );
    await assertSucceeds(getDoc(details(OUTSIDER)));
    // Already following: no second request.
    await assertFails(setDoc(request(OUTSIDER), requestData));
    // The player can remove them again.
    await assertSucceeds(deleteDoc(followDoc(OUTSIDER, PLAYER, PLAYER)));
    await assertFails(getDoc(details(OUTSIDER)));
  });

  it("requests are well-formed, and declined or taken back by deleting", async () => {
    await assertFails(setDoc(request(OUTSIDER, PLAYER, OWNER), requestData));
    await assertFails(setDoc(request(PLAYER), requestData));
    await assertFails(setDoc(request(OUTSIDER), { ...requestData, uid: OWNER }));
    await assertFails(setDoc(request(OUTSIDER), { ...requestData, createdAt: new Date("2020-01-01") }));
    await assertSucceeds(setDoc(request(OUTSIDER), requestData));
    await assertFails(deleteDoc(request(OUTSIDER, PLAYER, OWNER)));
    await assertSucceeds(deleteDoc(request(OUTSIDER, PLAYER, PLAYER)));
    await assertSucceeds(setDoc(request(OUTSIDER), requestData));
    await assertSucceeds(deleteDoc(request(OUTSIDER)));
  });

  it("public profiles take no requests and are followed directly", async () => {
    await assertSucceeds(
      setDoc(doc(db(PLAYER), "profiles", PLAYER), { private: false }, { merge: true }),
    );
    await assertFails(setDoc(request(OUTSIDER), requestData));
    await assertSucceeds(setDoc(followDoc(OUTSIDER, PLAYER), userFollow(PLAYER)));
  });

  it("only the player writes the private doc, with profile fields only", async () => {
    await assertFails(setDoc(details(OUTSIDER), { bio: "hacked" }));
    await assertFails(setDoc(details(PLAYER), { email: "x@y.z" }));
    await assertFails(setDoc(doc(db(PLAYER), "profiles", PLAYER, "private", "other"), { bio: "x" }));
    await assertFails(setDoc(doc(db(PLAYER), "profiles", PLAYER), { private: "yes" }, { merge: true }));
  });
});

describe("school and club communities", () => {
  const ORG = "org1";
  const ADMIN = "orgAdmin";
  const WOOF = "woofer";
  const OTHER = "otherMember";

  beforeEach(() =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", ORG), {
        name: "Tech Ultimate",
        division: "mixed",
        level: "college",
        city: "",
        kind: "organization",
        description: "",
        requiresApproval: true,
        location: null,
        ownerId: OWNER,
        members: { [OWNER]: "owner", [ADMIN]: "player", [WOOF]: "player", [OTHER]: "player" },
        memberIds: [OWNER, ADMIN, WOOF, OTHER],
        memberNames: { [OWNER]: "O", [ADMIN]: "A", [WOOF]: "W", [OTHER]: "X" },
        roles: {
          admins: { name: "Officers", color: 0, position: 0, perms: ["manageTeam", "manageEvents"] },
          woof: { name: "Woof", color: 0, position: 1, perms: [] },
        },
        memberRoles: { [ADMIN]: ["admins"], [WOOF]: ["woof"] },
        memberPerms: { [ADMIN]: ["manageTeam", "manageEvents"] },
        linkedTeams: {},
      });
    }),
  );

  const event = (audience: string[]) => ({
    title: "Woof practice",
    type: "practice",
    startsAt: new Date("2026-11-02T18:00:00Z"),
    endsAt: null,
    location: "",
    notes: "",
    poll: null,
    rsvps: {},
    reactions: {},
    votes: {},
    createdBy: ADMIN,
    audience,
  });

  it("can be created like a group", async () => {
    await assertSucceeds(
      setDoc(doc(db(OUTSIDER), "teams", "org2"), {
        name: "State U",
        division: "mixed",
        level: "college",
        city: "",
        kind: "organization",
        description: "",
        requiresApproval: false,
        location: null,
        ownerId: OUTSIDER,
        members: { [OUTSIDER]: "owner" },
        memberIds: [OUTSIDER],
        memberNames: { [OUTSIDER]: "Me" },
      }),
    );
  });

  it("a team asks to join with its orgId and a request, in one batch", async () => {
    const fs = db(OWNER);
    const batch = writeBatch(fs);
    batch.update(doc(fs, "teams", TEAM), { orgId: ORG, orgName: "Tech Ultimate" });
    batch.set(doc(fs, "teams", ORG, "linkRequests", TEAM), {
      teamName: "Team",
      division: "mixed",
      requestedBy: OWNER,
      requestedByName: "O",
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    // Its players can't, and only Cloud Functions mark it linked.
    await assertFails(updateDoc(doc(db(PLAYER), "teams", TEAM), { orgId: null }));
    await assertFails(updateDoc(doc(db(OWNER), "teams", TEAM), { orgLinked: true }));
  });

  it("a request needs the team to name the community", async () => {
    await assertFails(
      setDoc(doc(db(OWNER), "teams", ORG, "linkRequests", TEAM), {
        teamName: "Team",
        division: "mixed",
        requestedBy: OWNER,
        requestedByName: "O",
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("community admins list teams; plain members can't", async () => {
    const links = { linkedTeams: { [TEAM]: { name: "Team", division: "mixed", roles: ["woof"] } } };
    await assertSucceeds(updateDoc(doc(db(ADMIN), "teams", ORG), links));
    await assertFails(updateDoc(doc(db(WOOF), "teams", ORG), links));
  });

  it("a community event shows only to its audience and event managers", async () => {
    await assertSucceeds(
      setDoc(doc(db(ADMIN), "teams", ORG, "events", "e1"), event(["woof"])),
    );
    await assertSucceeds(getDoc(doc(db(WOOF), "teams", ORG, "events", "e1")));
    await assertSucceeds(getDoc(doc(db(OWNER), "teams", ORG, "events", "e1")));
    await assertFails(getDoc(doc(db(OTHER), "teams", ORG, "events", "e1")));
    // The app's queries: one per id the member holds.
    const events = collection(db(WOOF), "teams", ORG, "events");
    await assertSucceeds(getDocs(query(events, where("audience", "array-contains", "woof"))));
    await assertSucceeds(getDocs(query(events, where("audience", "array-contains", "everyone"))));
    await assertFails(getDocs(events));
    await assertSucceeds(getDocs(collection(db(ADMIN), "teams", ORG, "events")));
    // Those outside it can't answer either.
    await assertFails(
      updateDoc(doc(db(OTHER), "teams", ORG, "events", "e1"), { [`rsvps.${OTHER}`]: "going" }),
    );
    await assertSucceeds(
      updateDoc(doc(db(WOOF), "teams", ORG, "events", "e1"), { [`rsvps.${WOOF}`]: "going" }),
    );
  });

  it("a community event must say who sees it", async () => {
    const { audience: _, ...noAudience } = event([]);
    await assertFails(setDoc(doc(db(ADMIN), "teams", ORG, "events", "e2"), noAudience));
    await assertFails(setDoc(doc(db(ADMIN), "teams", ORG, "events", "e2"), event([])));
  });

  it("only a team's owner marks its roles as copies of community roles", async () => {
    const copies = {
      roles: { cap: { name: "Woof Captain", color: 0, position: 0, perms: [] } },
      orgRoles: { cap: "woof" },
    };
    await assertSucceeds(updateDoc(doc(db(OWNER), "teams", TEAM), copies));
    await assertFails(updateDoc(doc(db(COACH), "teams", TEAM), { orgRoles: { x: "y" } }));
  });

  it("removing a member also drops them from orgMembers", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "teams", TEAM), { orgMembers: [PLAYER] }),
    );
    const leave = {
      [`members.${PLAYER}`]: deleteField(),
      memberIds: arrayRemove(PLAYER),
      [`memberNames.${PLAYER}`]: deleteField(),
    };
    await assertFails(updateDoc(doc(db(PLAYER), "teams", TEAM), leave));
    await assertSucceeds(
      updateDoc(doc(db(PLAYER), "teams", TEAM), { ...leave, orgMembers: arrayRemove(PLAYER) }),
    );
  });
});

describe("hosted tournaments", () => {
  const HOST = "host1";
  const DIRECTOR = "director";
  const HOST_MEMBER = "hostMember";
  const T = "x1";
  const DIV = "d1";
  const tRef = (uid: string, id = T) => doc(db(uid), "tournaments", id);
  const divRef = (uid: string) => doc(db(uid), "tournaments", T, "divisions", DIV);
  const entryRef = (uid: string, teamId = TEAM) => doc(db(uid), "tournaments", T, "entries", teamId);
  const payRef = (uid: string, teamId = TEAM) => doc(db(uid), "tournaments", T, "payments", teamId);
  const gameRef = (uid: string, id: string) => doc(db(uid), "tournaments", T, "divisions", DIV, "games", id);

  const tournament = (extra: Record<string, unknown> = {}) => ({
    hostId: HOST,
    hostName: "Denver Ultimate",
    hostKind: "community",
    name: "Spring Fling",
    startsOn: new Date(2027, 4, 1),
    endsOn: null,
    description: "",
    location: "City Park",
    visibility: "public",
    entryType: "teams",
    status: "registration",
    bidFee: { amountCents: 25000, currency: "USD", instructions: "Venmo", dueAt: null },
    divisions: [{ id: DIV, division: "mixed", level: "club" }],
    createdBy: DIRECTOR,
    createdAt: new Date(2026, 10, 1),
    ...extra,
  });
  const division = (extra: Record<string, unknown> = {}) => ({
    division: "mixed",
    level: "club",
    settings: {},
    maxTeams: 8,
    seeds: [TEAM, "team2"],
    captains: { [TEAM]: [CAPTAIN], team2: ["cap2"] },
    placements: [],
    ...extra,
  });
  const entry = (extra: Record<string, unknown> = {}) => ({
    teamName: "Team",
    divisionId: DIV,
    status: "applied",
    captainIds: [CAPTAIN],
    updatedAt: serverTimestamp(),
    ...extra,
  });
  const game = (extra: Record<string, unknown> = {}) => ({
    order: 1, stage: "pool", round: 1, label: "Pool A, round 1", pool: "A", field: 1,
    startsAt: null, teamA: TEAM, teamB: "team2", sourceA: null, sourceB: null,
    status: "scheduled", scoreA: null, scoreB: null, report: null, ifNeeded: false,
    ...extra,
  });

  const seed = (t: Record<string, unknown> = {}) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "tournaments", T), tournament(t));
      await setDoc(doc(fs, "tournaments", T, "divisions", DIV), division());
    });

  beforeEach(() =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(doc(fs, "teams", HOST), {
        name: "Denver Ultimate",
        kind: "community",
        ownerId: DIRECTOR,
        members: { [DIRECTOR]: "owner", [HOST_MEMBER]: "player" },
        memberIds: [DIRECTOR, HOST_MEMBER],
      });
      await setDoc(doc(fs, "teams", "team2"), {
        name: "Other", ownerId: "cap2", members: { cap2: "owner" }, memberIds: ["cap2"],
      });
    }),
  );

  it("only the host's managers create and edit it", async () => {
    const fresh = { ...tournament({ status: "draft" }), createdAt: serverTimestamp() };
    await assertFails(setDoc(tRef(HOST_MEMBER), { ...fresh, createdBy: HOST_MEMBER }));
    await assertFails(setDoc(tRef(OUTSIDER), { ...fresh, createdBy: OUTSIDER }));
    await assertSucceeds(setDoc(tRef(DIRECTOR), fresh));
    await assertSucceeds(updateDoc(tRef(DIRECTOR), { status: "registration" }));
    await assertFails(updateDoc(tRef(HOST_MEMBER), { name: "Mine" }));
    await assertFails(updateDoc(tRef(DIRECTOR), { hostId: TEAM }));
    await assertFails(updateDoc(tRef(DIRECTOR), { status: "cancelled" }));
    await assertFails(
      updateDoc(tRef(DIRECTOR), { bidFee: { amountCents: -5, currency: "USD", instructions: "", dueAt: null } }),
    );
    await assertSucceeds(updateDoc(tRef(DIRECTOR), { bidFee: null }));
  });

  it("drafts are hidden; published tournaments are public to signed-in users", async () => {
    await seed({ status: "draft" });
    await assertFails(getDoc(tRef(OUTSIDER)));
    await assertFails(getDoc(divRef(OUTSIDER)));
    await assertSucceeds(getDoc(tRef(DIRECTOR)));
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), "tournaments", T), { status: "registration" }),
    );
    await assertSucceeds(getDoc(tRef(OUTSIDER)));
    await assertSucceeds(getDoc(divRef(OUTSIDER)));
    await assertSucceeds(getDoc(entryRef(OUTSIDER)));
  });

  it("team admins apply to public tournaments taking entries; players can't", async () => {
    await seed();
    await assertFails(setDoc(entryRef(PLAYER), entry()));
    await assertFails(setDoc(entryRef(CAPTAIN), entry({ status: "accepted" })));
    await assertFails(setDoc(entryRef(CAPTAIN), entry({ captainIds: [OUTSIDER] })));
    await assertSucceeds(setDoc(entryRef(CAPTAIN), entry()));
    await assertSucceeds(
      updateDoc(entryRef(CAPTAIN), { captainIds: [CAPTAIN, COACH], updatedAt: serverTimestamp() }),
    );
    await assertSucceeds(updateDoc(entryRef(CAPTAIN), { status: "withdrawn", updatedAt: serverTimestamp() }));
  });

  it("invite-only: teams can only answer an invite", async () => {
    await seed({ visibility: "inviteOnly" });
    await assertFails(setDoc(entryRef(CAPTAIN), entry()));
    await assertSucceeds(setDoc(entryRef(DIRECTOR), entry({ status: "invited", captainIds: [] })));
    await assertSucceeds(setDoc(entryRef(CAPTAIN), entry()));
  });

  it("no applying once registration closes", async () => {
    await seed({ status: "seeding" });
    await assertFails(setDoc(entryRef(CAPTAIN), entry()));
  });

  it("only managers seed divisions and accept teams", async () => {
    await seed();
    await assertFails(updateDoc(divRef(CAPTAIN), { seeds: [TEAM] }));
    await assertSucceeds(updateDoc(divRef(DIRECTOR), { seeds: ["team2", TEAM] }));
    await assertFails(updateDoc(divRef(DIRECTOR), { maxTeams: 1 }));
    await assertSucceeds(setDoc(entryRef(DIRECTOR), entry({ status: "accepted" })));
  });

  it("payments: managers mark them; a team's admins read only their own", async () => {
    await seed();
    await assertFails(setDoc(payRef(CAPTAIN), { paid: true, paidAt: null, note: "" }));
    await assertSucceeds(setDoc(payRef(DIRECTOR), { paid: true, paidAt: new Date(), note: "Venmo" }));
    await assertFails(setDoc(payRef(DIRECTOR), { paid: "yes", paidAt: null, note: "" }));
    await assertSucceeds(getDoc(payRef(CAPTAIN)));
    await assertFails(getDoc(payRef(PLAYER)));
    await assertFails(getDoc(payRef(OUTSIDER)));
    await assertFails(getDoc(payRef("cap2")));
    await assertSucceeds(getDoc(payRef("cap2", "team2")));
  });

  describe("leagues and player entry", () => {
    const signupRef = (uid: string, who = uid) => doc(db(uid), "tournaments", T, "signups", who);
    const draftRef = (uid: string) => doc(db(uid), "tournaments", T, "drafts", DIV);
    const signup = (extra: Record<string, unknown> = {}) => ({
      name: "Pat",
      divisionId: DIV,
      skill: 3,
      gender: "mmp",
      status: "applied",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...extra,
    });
    const season = (extra: Record<string, unknown> = {}) => ({
      weeks: 8, playoffWeeks: 1, playoffTeams: 4, gamesPerNight: 1, skipDates: [], ...extra,
    });
    const seedPlayers = (t: Record<string, unknown> = {}) =>
      seed({ entryType: "players", ...t });
    type ServerDb = Parameters<typeof doc>[0];
    const asServer = (fn: (fs: ServerDb) => Promise<unknown>) =>
      env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore() as unknown as ServerDb));

    it("a league carries a valid season; a plain tournament doesn't", async () => {
      const fresh = { ...tournament({ status: "draft" }), createdAt: serverTimestamp() };
      await assertSucceeds(setDoc(tRef(DIRECTOR), { ...fresh, kind: "league", season: season() }));
      await assertSucceeds(updateDoc(tRef(DIRECTOR), { season: season({ weeks: 10, playoffTeams: 8 }) }));
      await assertFails(updateDoc(tRef(DIRECTOR), { season: season({ weeks: 0 }) }));
      await assertFails(updateDoc(tRef(DIRECTOR), { season: season({ weeks: 27 }) }));
      await assertFails(updateDoc(tRef(DIRECTOR), { season: season({ playoffTeams: 3 }) }));
      await assertFails(updateDoc(tRef(DIRECTOR), { season: season({ playoffWeeks: 4 }) }));
      await assertFails(updateDoc(tRef(DIRECTOR), { season: season({ gamesPerNight: 3 }) }));
      await assertFails(updateDoc(tRef(DIRECTOR), { season: { ...season(), extra: 1 } }));
      await assertFails(updateDoc(tRef(DIRECTOR), { kind: "season" }));
      await assertSucceeds(updateDoc(tRef(DIRECTOR), { draftMode: "captains" }));
      await assertFails(updateDoc(tRef(DIRECTOR), { draftMode: "lottery" }));
      await assertFails(setDoc(tRef(DIRECTOR, "x2"), { ...fresh, kind: "tournament", season: season() }));
    });

    it("divisions take a min roster and drafted teams", async () => {
      await seedPlayers();
      await assertSucceeds(updateDoc(divRef(DIRECTOR), { minRoster: 4 }));
      await assertSucceeds(updateDoc(divRef(DIRECTOR), { minRoster: null }));
      await assertFails(updateDoc(divRef(DIRECTOR), { minRoster: 1 }));
      await assertFails(updateDoc(divRef(DIRECTOR), { minRoster: 31 }));
      await assertFails(updateDoc(divRef(DIRECTOR), { minRoster: "7" }));
      const team = { id: "a", name: "Red", captainId: "p1", playerIds: ["p1"], playerNames: { p1: "Pat" } };
      await assertSucceeds(updateDoc(divRef(DIRECTOR), { teams: [team] }));
      await assertFails(updateDoc(divRef(CAPTAIN), { teams: [team] }));
      await assertFails(updateDoc(divRef(DIRECTOR), { teams: Array.from({ length: 33 }, () => team) }));
    });

    it("players sign up for themselves while registration is open", async () => {
      await seedPlayers();
      await assertFails(setDoc(signupRef(PLAYER, OUTSIDER), signup()));
      await assertFails(setDoc(signupRef(PLAYER), signup({ status: "accepted" })));
      await assertFails(setDoc(signupRef(PLAYER), signup({ skill: 6 })));
      await assertFails(setDoc(signupRef(PLAYER), signup({ skill: 0 })));
      await assertFails(setDoc(signupRef(PLAYER), signup({ gender: "x" })));
      await assertFails(setDoc(signupRef(PLAYER), signup({ divisionId: "nope" })));
      await assertFails(setDoc(signupRef(PLAYER), { ...signup(), paid: true }));
      await assertSucceeds(setDoc(signupRef(PLAYER), signup()));
      await assertSucceeds(setDoc(signupRef(OUTSIDER), signup({ gender: null })));
    });

    it("no signups for team-entry tournaments, invite-only ones or once registration closes", async () => {
      await seed();
      await assertFails(setDoc(signupRef(PLAYER), signup()));
      await asServer((fs) => setDoc(doc(fs, "tournaments", T), tournament({ entryType: "players", visibility: "inviteOnly" })));
      await assertFails(setDoc(signupRef(PLAYER), signup()));
      await asServer((fs) => setDoc(doc(fs, "tournaments", T), tournament({ entryType: "players", status: "seeding" })));
      await assertFails(setDoc(signupRef(PLAYER), signup()));
    });

    it("signups are private to the player and the host's managers", async () => {
      await seedPlayers();
      await assertSucceeds(setDoc(signupRef(PLAYER), signup()));
      await assertSucceeds(getDoc(signupRef(PLAYER)));
      await assertSucceeds(getDoc(signupRef(DIRECTOR, PLAYER)));
      await assertFails(getDoc(signupRef(OUTSIDER, PLAYER)));
      await assertFails(getDoc(signupRef(HOST_MEMBER, PLAYER)));
    });

    it("a player can edit while waiting and withdraw, but not accept or change anything else", async () => {
      await seedPlayers();
      await assertSucceeds(setDoc(signupRef(PLAYER), signup()));
      await assertSucceeds(updateDoc(signupRef(PLAYER), { skill: 4, updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(signupRef(PLAYER), { status: "accepted", updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(signupRef(PLAYER), { createdAt: new Date(), updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(signupRef(OUTSIDER, PLAYER), { skill: 5, updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(signupRef(PLAYER), { status: "withdrawn", updatedAt: serverTimestamp() }));
      // Back in while registration is open.
      await assertSucceeds(updateDoc(signupRef(PLAYER), { status: "applied", updatedAt: serverTimestamp() }));
    });

    it("an accepted player can withdraw but can't re-rate themselves", async () => {
      await seedPlayers();
      await assertSucceeds(setDoc(signupRef(PLAYER), signup()));
      await assertSucceeds(updateDoc(signupRef(DIRECTOR, PLAYER), { status: "accepted", updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(signupRef(PLAYER), { skill: 1, updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(signupRef(PLAYER), { status: "withdrawn", updatedAt: serverTimestamp() }));
    });

    it("managers decide signups and nothing else on them", async () => {
      await seedPlayers();
      await assertSucceeds(setDoc(signupRef(PLAYER), signup()));
      await assertFails(updateDoc(signupRef(HOST_MEMBER, PLAYER), { status: "accepted", updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(signupRef(DIRECTOR, PLAYER), { skill: 5, updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(signupRef(DIRECTOR, PLAYER), { status: "waitlisted", updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(signupRef(DIRECTOR, PLAYER), { status: "accepted", updatedAt: serverTimestamp() }));
      await assertFails(deleteDoc(signupRef(PLAYER)));
      await assertSucceeds(deleteDoc(signupRef(DIRECTOR, PLAYER)));
    });

    it("a player reads their own entry-fee payment but can't write it", async () => {
      await seedPlayers();
      await assertFails(setDoc(payRef(PLAYER, PLAYER), { paid: true, paidAt: null, note: "" }));
      await assertSucceeds(setDoc(payRef(DIRECTOR, PLAYER), { paid: true, paidAt: new Date(), note: "Venmo" }));
      await assertSucceeds(getDoc(payRef(PLAYER, PLAYER)));
      await assertFails(getDoc(payRef(OUTSIDER, PLAYER)));
      await assertSucceeds(getDoc(payRef(DIRECTOR, PLAYER)));
      await assertFails(updateDoc(payRef(PLAYER, PLAYER), { paid: false }));
    });

    it("drafts are read-only: managers and accepted players in the division watch", async () => {
      await seedPlayers();
      await asServer(async (fs) => {
        await setDoc(doc(fs, "tournaments", T, "drafts", DIV), { status: "live", picks: [] });
        await setDoc(doc(fs, "tournaments", T, "signups", PLAYER), { ...signup(), status: "accepted", createdAt: new Date(), updatedAt: new Date() });
        await setDoc(doc(fs, "tournaments", T, "signups", COACH), { ...signup(), status: "applied", createdAt: new Date(), updatedAt: new Date() });
      });
      await assertSucceeds(getDoc(draftRef(DIRECTOR)));
      await assertSucceeds(getDoc(draftRef(PLAYER)));
      await assertFails(getDoc(draftRef(COACH)));
      await assertFails(getDoc(draftRef(OUTSIDER)));
      await assertFails(setDoc(draftRef(DIRECTOR), { status: "done", picks: [] }));
      await assertFails(updateDoc(draftRef(PLAYER), { picks: ["p"] }));
      // Only managers can clear it (deleting the tournament).
      await assertFails(deleteDoc(draftRef(PLAYER)));
      await assertSucceeds(deleteDoc(draftRef(DIRECTOR)));
    });

    it("a draft's skills and genders are for managers and its captains only", async () => {
      await seedPlayers();
      const pool = (uid: string) => doc(db(uid), "tournaments", T, "drafts", DIV, "details", "pool");
      await asServer(async (fs) => {
        await setDoc(doc(fs, "tournaments", T, "drafts", DIV), { status: "live", picks: [], captainIds: [PLAYER] });
        await setDoc(doc(fs, "tournaments", T, "drafts", DIV, "details", "pool"), { players: { x: { skill: 5 } } });
        await setDoc(doc(fs, "tournaments", T, "signups", COACH), { ...signup(), status: "accepted", createdAt: new Date(), updatedAt: new Date() });
      });
      await assertSucceeds(getDoc(pool(DIRECTOR)));
      await assertSucceeds(getDoc(pool(PLAYER)));
      // An accepted player who isn't a captain sees the board but not the skills.
      await assertSucceeds(getDoc(draftRef(COACH)));
      await assertFails(getDoc(pool(COACH)));
      await assertFails(getDoc(pool(OUTSIDER)));
      await assertFails(setDoc(pool(DIRECTOR), { players: {} }));
      // Only managers clear it, when the division or tournament goes.
      await assertFails(deleteDoc(pool(PLAYER)));
      await assertSucceeds(deleteDoc(pool(DIRECTOR)));
    });
  });

  it("captains report and confirm; others can't; managers override", async () => {
    await seed();
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "tournaments", T, "divisions", DIV, "games", "g1"), game()),
    );
    const report = { report: { scoreA: 15, scoreB: 10, byTeam: TEAM }, status: "reported" };
    await assertFails(updateDoc(gameRef(PLAYER, "g1"), report));
    await assertFails(updateDoc(gameRef("cap2", "g1"), report));
    await assertSucceeds(updateDoc(gameRef(CAPTAIN, "g1"), report));
    await assertFails(updateDoc(gameRef(CAPTAIN, "g1"), { status: "done", scoreA: 15, scoreB: 10, report: null }));
    await assertSucceeds(updateDoc(gameRef("cap2", "g1"), { status: "done", scoreA: 15, scoreB: 10, report: null }));
    await assertSucceeds(updateDoc(gameRef(DIRECTOR, "g1"), { scoreA: 15, scoreB: 12 }));
    await assertFails(updateDoc(gameRef(DIRECTOR, "g1"), { scoreA: 12, scoreB: 12 }));
  });

  it("a captain of a finished game moves its winner on", async () => {
    await seed();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await setDoc(
        doc(fs, "tournaments", T, "divisions", DIV, "games", "g1"),
        game({ status: "done", scoreA: 15, scoreB: 9 }),
      );
      await setDoc(
        doc(fs, "tournaments", T, "divisions", DIV, "games", "g2"),
        game({
          stage: "winners", label: "Final", teamA: null, teamB: null,
          sourceA: { type: "winner", game: "g1" }, sourceB: null,
        }),
      );
    });
    await assertFails(updateDoc(gameRef(CAPTAIN, "g2"), { teamA: "team2" }));
    await assertFails(updateDoc(gameRef(OUTSIDER, "g2"), { teamA: TEAM }));
    await assertSucceeds(updateDoc(gameRef(CAPTAIN, "g2"), { teamA: TEAM }));
  });

  it("placement games carry their place", async () => {
    await seed();
    await assertSucceeds(
      setDoc(gameRef(DIRECTOR, "g5"), game({ stage: "placement", label: "5th place", place: 5 })),
    );
    await assertFails(setDoc(gameRef(DIRECTOR, "g6"), game({ place: 0 })));
    await assertFails(setDoc(gameRef(DIRECTOR, "g7"), game({ place: "5th" })));
  });

  it("a team withdraws itself without touching the division", async () => {
    await seed();
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "tournaments", T, "entries", TEAM), {
        ...entry({ status: "accepted" }),
        updatedAt: new Date(),
      }),
    );
    await assertFails(updateDoc(divRef(CAPTAIN), { seeds: ["team2"] }));
    await assertSucceeds(
      updateDoc(entryRef(CAPTAIN), { status: "withdrawn", updatedAt: serverTimestamp() }),
    );
  });
});
