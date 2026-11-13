// Runs the captains' draft callables and createLeagueTeams against the
// Firestore emulator (npm run test:server), so the transactions, queries
// and writes are exercised, not just the pure model.

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { beforeAll, describe, expect, it } from "vitest";

import { createLeagueTeams } from "../../src/tournaments/callables";
import { draftControl, draftPick, finishDraft, startDraft } from "../../src/tournaments/draft";

initializeApp({ projectId: "demo-frisbee" });
const db = getFirestore();

type Callable = { run: (req: never) => unknown };
const call = (fn: Callable, uid: string, data: Record<string, unknown>) =>
  Promise.resolve(fn.run({ auth: { uid, token: {} }, data, rawRequest: {} } as never));

const DIV = "div1";
let next = 0;

/** A captains'-draft league with six accepted players, p0-p5. */
async function league(): Promise<string> {
  const id = `league${++next}_${Date.now()}`;
  const batch = db.batch();
  batch.set(db.doc("teams/host"), {
    name: "Stall 10",
    kind: "organization",
    ownerId: "director",
    members: { director: "owner" },
    memberIds: ["director"],
    city: "Austin",
  });
  batch.set(db.doc(`tournaments/${id}`), {
    name: "Thursday Night",
    hostId: "host",
    hostName: "Stall 10",
    kind: "league",
    entryType: "players",
    draftMode: "captains",
    status: "registration",
  });
  batch.set(db.doc(`tournaments/${id}/divisions/${DIV}`), { division: "mixed", level: "league", teams: [] });
  for (let i = 0; i < 6; i++) {
    batch.set(db.doc(`tournaments/${id}/signups/p${i}`), {
      name: `Player ${i}`,
      divisionId: DIV,
      skill: 1 + (i % 5),
      gender: i % 2 === 0 ? "mmp" : "wmp",
      status: "accepted",
    });
  }
  await batch.commit();
  return id;
}

const draftOf = async (id: string) => (await db.doc(`tournaments/${id}/drafts/${DIV}`).get()).data();

describe("captains' draft callables", { timeout: 60_000 }, () => {
  beforeAll(() => {
    expect(process.env.FIRESTORE_EMULATOR_HOST, "run with npm run test:server").toBeTruthy();
  });

  it("runs a whole draft and makes the league's teams", async () => {
    const id = await league();
    const args = { tournamentId: id, divisionId: DIV };

    await expect(call(startDraft, "p0", { ...args, captainIds: ["p0", "p1"] })).rejects.toMatchObject({
      code: "permission-denied",
    });
    await call(startDraft, "director", { ...args, captainIds: ["p0", "p1"], pickSeconds: 60 });
    let draft = await draftOf(id);
    expect(draft?.status).toBe("live");
    expect(Object.keys(draft?.pool ?? {}).sort()).toEqual(["p2", "p3", "p4", "p5"]);
    const details = (await db.doc(`tournaments/${id}/drafts/${DIV}/details/pool`).get()).data();
    expect(Object.keys(details?.players ?? {})).toHaveLength(6);
    // A second start can't wipe it.
    await expect(call(startDraft, "director", { ...args, captainIds: ["p2", "p3"] })).rejects.toMatchObject({
      code: "failed-precondition",
    });

    const [first, second] = draft?.captainIds as string[];
    await expect(call(draftPick, second, { ...args, uid: "p2" })).rejects.toMatchObject({
      code: "permission-denied",
    });
    await call(draftPick, first, { ...args, uid: "p2" });
    await expect(call(draftPick, second, { ...args, uid: "p2" })).rejects.toMatchObject({
      code: "failed-precondition",
    });
    await expect(call(draftPick, second, { ...args, uid: first })).rejects.toMatchObject({
      code: "failed-precondition",
    });

    await expect(call(draftControl, first, { ...args, action: "undo" })).rejects.toMatchObject({
      code: "permission-denied",
    });
    await call(draftControl, "director", { ...args, action: "undo" });
    expect((await draftOf(id))?.picks).toEqual([]);

    await call(draftControl, "director", { ...args, action: "pause" });
    await expect(call(draftPick, first, { ...args, uid: "p2" })).rejects.toMatchObject({
      code: "failed-precondition",
    });
    await call(draftControl, "director", { ...args, action: "resume" });
    for (let i = 0; i < 4; i++) await call(draftControl, "director", { ...args, action: "autopick" });
    draft = await draftOf(id);
    expect(draft?.status).toBe("done");
    // Snake order: first, second, second, first.
    expect((draft?.picks as { captainId: string }[]).map((p) => p.captainId)).toEqual([first, second, second, first]);

    await call(finishDraft, "director", args);
    expect((await draftOf(id))?.status).toBe("finished");
    const division = (await db.doc(`tournaments/${id}/divisions/${DIV}`).get()).data();
    expect(division?.teams).toHaveLength(2);
    expect(division?.seeds).toEqual(["team1", "team2"]);
    expect(division?.teams[0].captainId).toBe(first);
    expect(division?.teams[0].playerIds).toHaveLength(3);

    const made = (await call(createLeagueTeams, "director", args)) as { created: number };
    expect(made.created).toBe(2);
    const after = (await db.doc(`tournaments/${id}/divisions/${DIV}`).get()).data();
    const teamId = after?.seeds[0] as string;
    expect(teamId.startsWith(`league_${id}_`)).toBe(true);
    const team = (await db.doc(`teams/${teamId}`).get()).data();
    expect(team?.ownerId).toBe(first);
    expect(team?.members[first]).toBe("owner");
    const entry = (await db.doc(`tournaments/${id}/entries/${teamId}`).get()).data();
    expect(entry?.status).toBe("accepted");
    // Calling again changes nothing.
    expect(((await call(createLeagueTeams, "director", args)) as { created: number }).created).toBe(0);
    // And the draft can't be started over once the teams exist.
    await expect(call(startDraft, "director", { ...args, captainIds: ["p0", "p1"] })).rejects.toMatchObject({
      code: "failed-precondition",
    });
  });

  it("keeps teams that registered on their own through the draft and team creation", async () => {
    const id = await league();
    const args = { tournamentId: id, divisionId: DIV };
    // A team reserved its spot before the draft.
    await db.doc(`tournaments/${id}/divisions/${DIV}`).update({
      seeds: ["reserved"],
      captains: { reserved: ["cap"] },
    });
    await call(startDraft, "director", { ...args, captainIds: ["p0", "p1"] });
    for (let i = 0; i < 4; i++) await call(draftControl, "director", { ...args, action: "autopick" });
    await call(finishDraft, "director", args);
    let division = (await db.doc(`tournaments/${id}/divisions/${DIV}`).get()).data();
    expect(division?.seeds).toEqual(["reserved", "team1", "team2"]);
    expect(division?.captains.reserved).toEqual(["cap"]);
    await call(createLeagueTeams, "director", args);
    division = (await db.doc(`tournaments/${id}/divisions/${DIV}`).get()).data();
    expect(division?.seeds).toEqual(["reserved", `league_${id}_team1`, `league_${id}_team2`]);
    expect(division?.captains.reserved).toEqual(["cap"]);
    expect(Object.keys(division?.captains ?? {})).toHaveLength(3);
  });

  it("cancelling clears the draft so it can start again", async () => {
    const id = await league();
    const args = { tournamentId: id, divisionId: DIV };
    await call(startDraft, "director", { ...args, captainIds: ["p0", "p1"] });
    await call(draftControl, "director", { ...args, action: "cancel" });
    expect(await draftOf(id)).toBeUndefined();
    expect((await db.doc(`tournaments/${id}/drafts/${DIV}/details/pool`).get()).exists).toBe(false);
    await call(startDraft, "director", { ...args, captainIds: ["p2", "p3"] });
    expect(((await draftOf(id))?.captainIds as string[]).sort()).toEqual(["p2", "p3"]);
  });

  it("refuses captains who aren't accepted and events without a captains' draft", async () => {
    const id = await league();
    const args = { tournamentId: id, divisionId: DIV };
    await expect(call(startDraft, "director", { ...args, captainIds: ["p0", "stranger"] })).rejects.toMatchObject({
      code: "failed-precondition",
    });
    await db.doc(`tournaments/${id}`).update({ draftMode: "balanced" });
    await expect(call(startDraft, "director", { ...args, captainIds: ["p0", "p1"] })).rejects.toMatchObject({
      code: "failed-precondition",
    });
  });
});
