// Rebuilding the rankings against the Firestore emulator (npm run
// test:server): youth divisions skipped, a youth team (by its listing
// only) left out of an adult division, a stale youth ranking deleted, and
// nobody on a youth team rated bar its coach.

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { beforeAll, describe, expect, it } from "vitest";

import { rebuildPlayerRankings, rebuildRankings } from "../../src/rankings/functions";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();
const now = new Date("2026-11-15T12:00:00Z");
const day = 86_400_000;

const adult = ["rk_a", "rk_b", "rk_c", "rk_d", "rk_e", "rk_yl"];
const youth = ["rk_y1", "rk_y2", "rk_y3", "rk_y4", "rk_y5", "rk_y6"];

async function roundRobin(divisionPath: string, ids: string[]) {
  const batch = db.batch();
  let n = 0;
  ids.forEach((a, i) =>
    ids.slice(i + 1).forEach((b, j) => {
      batch.set(db.doc(`${divisionPath}/games/g${n++}`), {
        teamA: a,
        teamB: b,
        scoreA: 13,
        scoreB: 7 + ((i + j) % 5),
        status: "done",
        startsAt: Timestamp.fromMillis(now.getTime() - 10 * day),
      });
    }),
  );
  await batch.commit();
}

const stats = { games: 12, points: 120, goals: 10, assists: 8, blocks: 3, completions: 60, catches: 50, throwaways: 4, drops: 1 };

beforeAll(async () => {
  const batch = db.batch();
  batch.set(db.doc("tournaments/rk_t1"), {
    name: "Fall Classic",
    hostName: "Host",
    status: "finished",
    visibility: "public",
    entryType: "teams",
    kind: "tournament",
    startsOn: Timestamp.fromMillis(now.getTime() - 10 * day),
  });
  batch.set(db.doc("tournaments/rk_t1/divisions/club"), { level: "club", division: "mixed", placements: ["rk_a", "rk_b"] });
  batch.set(db.doc("tournaments/rk_t1/divisions/youth"), { level: "youth", division: "mixed", placements: ["rk_y1"] });
  for (const id of [...adult, ...youth]) batch.set(db.doc(`tournaments/rk_t1/entries/${id}`), { teamName: id.toUpperCase() });
  // Youth by its directory listing only: the team doc says club.
  batch.set(db.doc("teams/rk_yl"), { name: "YL", level: "club" });
  batch.set(db.doc("teamDirectory/rk_yl"), { name: "YL", level: "youth" });
  batch.set(db.doc("teams/rk_a"), { name: "A", level: "club" });
  // A ranking left from before youth stopped being ranked.
  batch.set(db.doc("rankings/youth-open"), { level: "youth", division: "open", teams: [{ rank: 1, teamId: "rk_y1", name: "Y1" }] });
  // A youth team's coach and player, and an adult player.
  batch.set(db.doc("teams/rk_youthteam"), {
    name: "Juniors",
    level: "youth",
    members: { rk_coach: "coach", rk_kid: "player" },
    memberIds: ["rk_coach", "rk_kid"],
  });
  for (const uid of ["rk_coach", "rk_kid", "rk_adult"]) {
    batch.set(db.doc(`profiles/${uid}`), { name: uid, username: uid, stats: { "2026": stats } });
  }
  await batch.commit();
  await roundRobin("tournaments/rk_t1/divisions/club", adult);
  await roundRobin("tournaments/rk_t1/divisions/youth", youth);
  await rebuildRankings(now);
  await rebuildPlayerRankings(now);
});

describe("rebuildRankings", () => {
  it("never writes a youth ranking, and deletes the stale one", async () => {
    const ids = (await db.collection("rankings").get()).docs.map((d) => d.id);
    expect(ids).toEqual(["club-mixed"]);
  });

  it("leaves a youth team (by its listing) out of an adult division, numbering the rest", async () => {
    const doc = (await db.doc("rankings/club-mixed").get()).data()!;
    const teams = doc.teams as { rank: number; teamId: string }[];
    expect(teams.map((t) => t.teamId)).not.toContain("rk_yl");
    expect(teams.map((t) => t.rank)).toEqual([1, 2, 3, 4, 5]);
  });
});

describe("rebuildPlayerRankings", () => {
  it("rates nobody on a youth team but its coach", async () => {
    const doc = (await db.doc("playerRankings/all").get()).data()!;
    const uids = (doc.players as { uid: string }[]).map((p) => p.uid).sort();
    expect(uids).toEqual(["rk_adult", "rk_coach"]);
  });
});
