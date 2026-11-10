// Team rankings and recent results (see model.ts), exported as the
// `rankings` group:
//   firebase deploy --only functions:rankings
// Rebuilt nightly, and when a tournament goes final, into
// `rankings/{level-division}` and `tournamentResults/recent`; player
// ratings (players.ts) nightly into `playerRankings/all`. Any signed-in
// user can read them and nobody can write them.

import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  countsForRankings,
  type Data,
  divisionResult,
  rankingDoc,
  rankingKey,
  type RankedGame,
  rate,
  windowDays,
} from "./model";
import { type PlayerInput, playerInput, playerRankingDoc, ratePlayers } from "./players";

/** How many finished tournaments Explore's Recent results lists. */
const recentCount = 10;

const toDate = (v: unknown): Date | null => (v instanceof Timestamp ? v.toDate() : v instanceof Date ? v : null);

/** Reads the window's tournaments and writes every ranking and the recent results. */
export async function rebuildRankings(now = new Date()): Promise<void> {
  const db = getFirestore();
  const cutoff = new Date(now.getTime() - windowDays * 86_400_000);
  const snap = await db
    .collection("tournaments")
    .where("status", "in", ["live", "finished"])
    .where("startsOn", ">=", Timestamp.fromDate(cutoff))
    .get();
  const tournaments = snap.docs.filter((d) => countsForRankings(d.data()));

  const games = new Map<string, RankedGame[]>();
  // A team's newest name from its entries.
  const names = new Map<string, string>();
  const named = new Map<string, number>();
  const recent: Data[] = [];

  for (const t of tournaments) {
    const data = t.data();
    const startsOn = toDate(data.startsOn) ?? now;
    const [divisions, entries] = await Promise.all([
      t.ref.collection("divisions").get(),
      t.ref.collection("entries").get(),
    ]);
    const tournamentNames = new Map<string, string>();
    for (const e of entries.docs) {
      const name = String(e.data().teamName ?? "").trim();
      if (!name) continue;
      tournamentNames.set(e.id, name);
      if ((named.get(e.id) ?? 0) <= startsOn.getTime()) {
        names.set(e.id, name);
        named.set(e.id, startsOn.getTime());
      }
    }
    const results = [];
    for (const d of divisions.docs) {
      const div = d.data();
      const key = rankingKey(String(div.level ?? "club"), String(div.division ?? "mixed"));
      const done = await d.ref.collection("games").where("status", "==", "done").get();
      const list = games.get(key) ?? [];
      for (const g of done.docs) {
        const x = g.data();
        if (typeof x.teamA !== "string" || typeof x.teamB !== "string") continue;
        list.push({
          teamA: x.teamA,
          teamB: x.teamB,
          scoreA: Number(x.scoreA),
          scoreB: Number(x.scoreB),
          playedAt: toDate(x.startsAt) ?? startsOn,
        });
      }
      games.set(key, list);
      if (data.status === "finished") results.push(divisionResult(div, tournamentNames));
    }
    if (data.status === "finished") {
      recent.push({
        tournamentId: t.id,
        name: data.name ?? "",
        hostName: data.hostName ?? "",
        location: data.location ?? "",
        startsOn: data.startsOn ?? null,
        endsOn: data.endsOn ?? data.startsOn ?? null,
        divisions: results.filter((r) => r.champion),
      });
    }
  }

  const writer = db.bulkWriter();
  const keys = new Set<string>();
  for (const [key, list] of games) {
    const [level, division] = key.split("-");
    const doc = rankingDoc(level, division, rate(list, now), names);
    if ((doc.teams as unknown[]).length === 0) continue;
    keys.add(key);
    void writer.set(db.doc(`rankings/${key}`), { ...doc, updatedAt: FieldValue.serverTimestamp() });
  }
  // Divisions with nobody ranked any more.
  for (const old of (await db.collection("rankings").get()).docs) {
    if (!keys.has(old.id)) void writer.delete(old.ref);
  }
  const ends = (r: Data) => toDate(r.endsOn)?.getTime() ?? 0;
  recent.sort((a, b) => ends(b) - ends(a));
  void writer.set(db.doc("tournamentResults/recent"), {
    tournaments: recent.slice(0, recentCount),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await writer.close();
  logger.info("Rankings rebuilt", { tournaments: tournaments.length, divisions: keys.size });
}

/** Rates every public profile that shows stats and writes the top players. */
export async function rebuildPlayerRankings(now = new Date()): Promise<void> {
  const db = getFirestore();
  // Reads every profile: fine while the app is small; past tens of
  // thousands of players, keep a rated-players index instead.
  const snap = await db.collection("profiles").select("name", "username", "photoUrl", "private", "visibility", "stats").get();
  const players: PlayerInput[] = [];
  for (const d of snap.docs) {
    const p = playerInput(d.id, d.data());
    if (p) players.push(p);
  }
  const doc = playerRankingDoc(ratePlayers(players, now));
  await db.doc("playerRankings/all").set({ ...doc, updatedAt: FieldValue.serverTimestamp() });
  logger.info("Player rankings rebuilt", { profiles: snap.size, rated: (doc.players as unknown[]).length });
}

/** Nightly, so recency weights and the window move on. */
export const nightly = onSchedule(
  { schedule: "15 9 * * *", timeZone: "Etc/UTC", timeoutSeconds: 540, retryCount: 1 },
  async () => {
    // One failing shouldn't keep the other from updating.
    const results = await Promise.allSettled([rebuildRankings(), rebuildPlayerRankings()]);
    const failed = results.filter((r) => r.status === "rejected");
    for (const r of failed) logger.error("Rankings rebuild failed", { error: String((r as PromiseRejectedResult).reason) });
    if (failed.length) throw new Error("Rankings rebuild failed");
  },
);

/** A tournament went final (or stopped being final, or public): rebuild now. */
export const onTournamentFinal = onDocumentUpdated("tournaments/{tournamentId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  const final = (t: Data) => t.status === "finished" && countsForRankings(t);
  if (final(before) === final(after)) return;
  await rebuildRankings();
});
