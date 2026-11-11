// Callables for the captains' live draft, exported with the `tournaments`
// group. The host picks captains, who take turns picking players in snake
// order. Every write goes through here, in a transaction, because "only
// the captain on the clock may pick one player nobody has picked" can't be
// enforced by rules, and because signups are private: `startDraft` copies
// the pool into the draft docs, which accepted players can read (names and
// picks) and only the host and the captains can read in full (skill and
// gender, in `details/pool`).
//
//   tournaments/{t}/drafts/{division}          the board everyone sees
//   tournaments/{t}/drafts/{division}/details/pool   skill and gender

import { FieldValue, getFirestore, type Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall, type CallableRequest } from "firebase-functions/v2/https";

import { enforceAppCheck } from "../options";
import {
  autoPick,
  available,
  onTheClock,
  type Pick,
  pickProblem,
  type PoolPlayer,
  startProblem,
  teamsFromDraft,
} from "./draft_model";
import { canManageEvents, type Data, teamsCreated, draftTeams } from "./league";

const idPattern = /^[A-Za-z0-9_-]{1,60}$/;
const clipName = (s: unknown): string => (typeof s === "string" ? s.trim().slice(0, 100) : "");

interface Ctx {
  uid: string;
  tournamentId: string;
  divisionId: string;
  tournament: Data;
  division: Data;
  manager: boolean;
  data: Data;
}

/** Signed in, and a real captains' draft in a real division. */
async function context(req: CallableRequest): Promise<Ctx> {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to use the draft.");
  const data = (req.data ?? {}) as Data;
  const { tournamentId, divisionId } = data;
  if (typeof tournamentId !== "string" || !idPattern.test(tournamentId)) {
    throw new HttpsError("invalid-argument", "Pick an event.");
  }
  if (typeof divisionId !== "string" || !idPattern.test(divisionId)) {
    throw new HttpsError("invalid-argument", "Pick a division.");
  }
  const db = getFirestore();
  const tournamentRef = db.doc(`tournaments/${tournamentId}`);
  const [tournamentSnap, divisionSnap] = await Promise.all([
    tournamentRef.get(),
    tournamentRef.collection("divisions").doc(divisionId).get(),
  ]);
  const tournament = tournamentSnap.data() as Data | undefined;
  const division = divisionSnap.data() as Data | undefined;
  if (!tournament || !division) throw new HttpsError("not-found", "That event or division doesn't exist.");
  if (tournament.entryType !== "players" || tournament.draftMode !== "captains") {
    throw new HttpsError("failed-precondition", "This event doesn't use a captains' draft.");
  }
  const host = await db.doc(`teams/${String(tournament.hostId)}`).get();
  const manager = canManageEvents(host.data() as Data | undefined, uid);
  return { uid, tournamentId, divisionId, tournament, division, manager, data };
}

const requireManager = (c: Ctx) => {
  if (!c.manager) throw new HttpsError("permission-denied", "Only the event's organizers can do that.");
};

const draftRef = (c: Ctx) => getFirestore().doc(`tournaments/${c.tournamentId}/drafts/${c.divisionId}`);
const poolRef = (c: Ctx) => draftRef(c).collection("details").doc("pool");

/** Teams can't be redrafted once the schedule or the real teams exist. */
async function requireOpen(c: Ctx): Promise<void> {
  const games = await getFirestore()
    .collection(`tournaments/${c.tournamentId}/divisions/${c.divisionId}/games`)
    .limit(1)
    .get();
  if (!games.empty) throw new HttpsError("failed-precondition", "The schedule is published.");
  if (teamsCreated(draftTeams(c.division.teams))) {
    throw new HttpsError("failed-precondition", "The teams have already been created.");
  }
}

interface Loaded {
  draft: Data;
  captainIds: string[];
  picks: Pick[];
  pool: PoolPlayer[];
  /** Everyone's skill and gender, captains included. */
  everyone: Map<string, PoolPlayer>;
}

async function load(tx: Transaction, c: Ctx): Promise<Loaded> {
  const [draftSnap, poolSnap] = await Promise.all([tx.get(draftRef(c)), tx.get(poolRef(c))]);
  const draft = draftSnap.data();
  if (!draft) throw new HttpsError("failed-precondition", "The draft hasn't started.");
  const names = (draft.pool ?? {}) as Record<string, string>;
  const details = ((poolSnap.data()?.players ?? {}) as Record<string, { skill?: number; gender?: string | null }>);
  const player = (uid: string, name: string): PoolPlayer => ({
    uid,
    name,
    skill: Number(details[uid]?.skill ?? 3),
    gender: details[uid]?.gender === "mmp" || details[uid]?.gender === "wmp" ? details[uid].gender : null,
  } as PoolPlayer);
  const captains = (draft.captains ?? []) as { uid: string; name: string }[];
  return {
    draft,
    captainIds: (draft.captainIds ?? []) as string[],
    picks: (draft.picks ?? []) as Pick[],
    pool: Object.entries(names).map(([uid, name]) => player(uid, name)),
    everyone: new Map([
      ...captains.map((x) => [x.uid, player(x.uid, x.name)] as const),
      ...Object.entries(names).map(([uid, name]) => [uid, player(uid, name)] as const),
    ]),
  };
}

/** Adds [uid] to [captainId]'s team and passes the turn. */
function recordPick(tx: Transaction, c: Ctx, l: Loaded, uid: string): void {
  const picks = [...l.picks, { uid, captainId: onTheClock(l.captainIds, l.picks, l.pool.length) as string }];
  tx.update(draftRef(c), {
    picks,
    status: picks.length >= l.pool.length ? "done" : "live",
    turnStartedAt: FieldValue.serverTimestamp(),
  });
}

/**
 * The host starts a division's draft with the captains they chose. A draft
 * that's already there has to be cancelled first, so a second tap can't
 * wipe the picks.
 */
export const startDraft = onCall({ enforceAppCheck }, async (req) => {
  const c = await context(req);
  requireManager(c);
  await requireOpen(c);
  if ((await draftRef(c).get()).exists) {
    throw new HttpsError("failed-precondition", "This division already has a draft. Cancel it to start over.");
  }
  const captainIds = Array.isArray(c.data.captainIds) ? c.data.captainIds.map(String) : [];
  const pickSeconds = Math.min(600, Math.max(0, Math.floor(Number(c.data.pickSeconds ?? 0))));

  const db = getFirestore();
  const signups = await db
    .collection(`tournaments/${c.tournamentId}/signups`)
    .where("divisionId", "==", c.divisionId)
    .where("status", "==", "accepted")
    .get();
  const accepted = new Map(signups.docs.map((d) => [d.id, d.data()]));
  const problem = startProblem({
    captainIds,
    accepted: new Set(accepted.keys()),
    poolSize: accepted.size - captainIds.length,
  });
  if (problem) throw new HttpsError("failed-precondition", problem);

  // A random order, so nobody picks first just for being listed first.
  const order = shuffled(captainIds);
  const asCaptain = (id: string) => ({ uid: id, name: clipName(accepted.get(id)?.name) || "Captain" });
  const players = [...accepted.entries()].filter(([id]) => !captainIds.includes(id));
  const batch = db.batch();
  batch.set(draftRef(c), {
    status: "live",
    captains: order.map(asCaptain),
    captainIds: order,
    pool: Object.fromEntries(players.map(([id, s]) => [id, clipName(s.name) || "Player"])),
    picks: [],
    pickSeconds,
    mixed: c.division.division === "mixed",
    turnStartedAt: FieldValue.serverTimestamp(),
    startedBy: c.uid,
  });
  batch.set(poolRef(c), {
    players: Object.fromEntries(
      [...accepted.entries()].map(([id, s]) => [id, { skill: Number(s.skill ?? 3), gender: s.gender ?? null }]),
    ),
  });
  await batch.commit();
  logger.info("Draft started", { tournamentId: c.tournamentId, divisionId: c.divisionId, captains: order.length });
  return { captains: order.length, players: players.length };
});

/** The captain on the clock picks a player (the host can pick for them). */
export const draftPick = onCall({ enforceAppCheck }, async (req) => {
  const c = await context(req);
  const uid = typeof c.data.uid === "string" ? c.data.uid : "";
  await getFirestore().runTransaction(async (tx) => {
    const l = await load(tx, c);
    const clock = onTheClock(l.captainIds, l.picks, l.pool.length);
    if (clock !== c.uid && !c.manager) throw new HttpsError("permission-denied", "It's not your pick.");
    const problem = pickProblem({
      status: String(l.draft.status),
      captainIds: l.captainIds,
      picks: l.picks,
      pool: l.pool,
      uid,
    });
    if (problem) throw new HttpsError("failed-precondition", problem);
    recordPick(tx, c, l, uid);
  });
  return { ok: true };
});

/** Fisher-Yates: every order equally likely. */
function shuffled<T>(list: readonly T[]): T[] {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/**
 * The host pauses, resumes, undoes the last pick, picks for a captain
 * who's out of time, or cancels the draft (before it's finished) to start
 * over with other captains.
 */
export const draftControl = onCall({ enforceAppCheck }, async (req) => {
  const c = await context(req);
  requireManager(c);
  const action = c.data.action;
  if (!["pause", "resume", "undo", "autopick", "cancel"].includes(String(action))) {
    throw new HttpsError("invalid-argument", "Unknown action.");
  }
  await getFirestore().runTransaction(async (tx) => {
    const l = await load(tx, c);
    const status = String(l.draft.status);
    if (status === "finished") throw new HttpsError("failed-precondition", "The draft is finished.");
    switch (action) {
      case "cancel":
        tx.delete(poolRef(c));
        tx.delete(draftRef(c));
        break;
      case "pause":
        if (status !== "live") throw new HttpsError("failed-precondition", "The draft isn't running.");
        tx.update(draftRef(c), { status: "paused" });
        break;
      case "resume":
        if (status !== "paused") throw new HttpsError("failed-precondition", "The draft isn't paused.");
        tx.update(draftRef(c), { status: "live", turnStartedAt: FieldValue.serverTimestamp() });
        break;
      case "undo":
        if (l.picks.length === 0) throw new HttpsError("failed-precondition", "Nothing to undo.");
        tx.update(draftRef(c), {
          picks: l.picks.slice(0, -1),
          status: status === "paused" ? "paused" : "live",
          turnStartedAt: FieldValue.serverTimestamp(),
        });
        break;
      default: {
        const clock = onTheClock(l.captainIds, l.picks, l.pool.length);
        if (status !== "live" || clock === null) throw new HttpsError("failed-precondition", "Nobody is on the clock.");
        const team = [clock, ...l.picks.filter((p) => p.captainId === clock).map((p) => p.uid)]
          .map((id) => l.everyone.get(id))
          .filter((p): p is PoolPlayer => p !== undefined);
        const choice = autoPick(available(l.pool, l.picks), team, l.draft.mixed === true);
        if (!choice) throw new HttpsError("failed-precondition", "Nobody is left to pick.");
        recordPick(tx, c, l, choice.uid);
      }
    }
  });
  return { ok: true };
});

/**
 * The host turns the picks into the division's teams, the same shape the
 * balanced draft saves, so the host can still rename and move players
 * before publishing (or, for a league, creating the real teams). Players
 * nobody picked stay unassigned.
 */
export const finishDraft = onCall({ enforceAppCheck }, async (req) => {
  const c = await context(req);
  requireManager(c);
  await requireOpen(c);
  const db = getFirestore();
  let made = 0;
  await db.runTransaction(async (tx) => {
    const l = await load(tx, c);
    if (l.draft.status === "finished") throw new HttpsError("failed-precondition", "The draft is already finished.");
    const teams = teamsFromDraft({
      captains: (l.draft.captains ?? []) as { uid: string; name: string }[],
      picks: l.picks,
      names: (l.draft.pool ?? {}) as Record<string, string>,
    });
    made = teams.length;
    tx.update(db.doc(`tournaments/${c.tournamentId}/divisions/${c.divisionId}`), {
      teams,
      seeds: teams.map((t) => t.id),
      captains: Object.fromEntries(teams.map((t) => [t.id, t.captainId ? [t.captainId] : []])),
    });
    tx.update(draftRef(c), { status: "finished" });
  });
  logger.info("Draft finished", { tournamentId: c.tournamentId, divisionId: c.divisionId, teams: made });
  return { teams: made };
});
