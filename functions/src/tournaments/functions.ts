// Hosted tournaments on team schedules (see model.ts), exported as the
// `tournaments` group:
//   firebase deploy --only functions:tournaments
// The host accepting an entry isn't on the team, so rules don't let the
// app write the team's schedule; these triggers do it.

import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";

import {
  changedDetails,
  changedGameEvent,
  type Data,
  entryChange,
  entryRecord,
  eventIdFor,
  gameTeams,
  leagueEventId,
  leagueGameEvent,
  newEvent,
  newLeagueGameEvent,
  recordUpdate,
} from "./model";

/**
 * Keeps the team's record of the entry (its Tournaments tab lists them),
 * and puts an accepted tournament on the team's schedule; no longer
 * accepted, it comes off.
 */
export const entrySchedule = onDocumentWritten("tournaments/{tournamentId}/entries/{teamId}", async (event) => {
  const { tournamentId, teamId } = event.params;
  const after = event.data?.after.data() as Data | undefined;
  const db = getFirestore();
  await syncRecord(tournamentId, teamId, after);
  const change = entryChange(event.data?.before.data() as Data | undefined, after);
  if (!change) return;
  const ref = db.doc(`teams/${teamId}/events/${eventIdFor(tournamentId)}`);
  if (change === "remove") {
    await ref.delete();
    logger.info("Tournament taken off a team's schedule", { tournamentId, teamId });
    return;
  }
  const [tournament, team] = await Promise.all([
    db.doc(`tournaments/${tournamentId}`).get(),
    db.doc(`teams/${teamId}`).get(),
  ]);
  if (!tournament.exists || !team.exists) return;
  // A league's games go on the schedule one by one (leagueGameEvents), not
  // as a single event spanning the season.
  if (tournament.get("kind") === "league") return;
  await db.runTransaction(async (tx) => {
    // Accepted again after a withdrawal, say: keep the responses it has.
    if ((await tx.get(ref)).exists) return;
    tx.set(ref, {
      ...newEvent(tournamentId, tournament.data() as Data, team.data() as Data),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  logger.info("Tournament added to a team's schedule", { tournamentId, teamId });
});

async function syncRecord(tournamentId: string, teamId: string, entry: Data | undefined): Promise<void> {
  const db = getFirestore();
  const ref = db.doc(`teams/${teamId}/tournamentEntries/${tournamentId}`);
  if (!entry) {
    await ref.delete();
    return;
  }
  const [tournament, team] = await Promise.all([
    db.doc(`tournaments/${tournamentId}`).get(),
    db.doc(`teams/${teamId}`).get(),
  ]);
  if (!team.exists) return;
  // The tournament itself is being deleted: its entries go with it.
  if (!tournament.exists) {
    await ref.delete();
    return;
  }
  const record = entryRecord(tournament.data() as Data, entry);
  if (record) await ref.set({ ...record, updatedAt: FieldValue.serverTimestamp() });
}

/** The host renamed, moved or re-dated it: the teams' events and records follow. */
export const tournamentSchedule = onDocumentUpdated("tournaments/{tournamentId}", async (event) => {
  const { tournamentId } = event.params;
  const before = event.data?.before.data() as Data | undefined;
  const after = event.data?.after.data() as Data | undefined;
  if (!before || !after) return;
  const db = getFirestore();
  const records = recordUpdate(before, after);
  if (records) {
    const entries = await db.collection(`tournaments/${tournamentId}/entries`).get();
    const writer = db.bulkWriter();
    for (const entry of entries.docs) {
      const ref = db.doc(`teams/${entry.id}/tournamentEntries/${tournamentId}`);
      void writer.update(ref, records).catch(() => undefined);
    }
    await writer.close();
  }
  const update = changedDetails(before, after);
  if (!update) return;
  const accepted = await db
    .collection(`tournaments/${tournamentId}/entries`)
    .where("status", "==", "accepted")
    .get();
  const writer = db.bulkWriter();
  for (const entry of accepted.docs) {
    const ref = db.doc(`teams/${entry.id}/events/${eventIdFor(tournamentId)}`);
    // A team that deleted the event keeps it deleted.
    void writer.update(ref, { ...update, updatedAt: FieldValue.serverTimestamp() }).catch(() => undefined);
  }
  await writer.close();
});

/**
 * Keeps each league game on both teams' schedules: added once the game is
 * between two known teams with a start time, moved or renamed when it
 * changes, and taken off when the game, the league or a team's place in the
 * game goes away.
 *
 * It works from the game as it is now, not from the event's before and
 * after: publishing a schedule deletes and rewrites games under the same
 * ids, and triggers for those can arrive in any order. Notifications skip
 * these events (see isLeagueGameEvent).
 */
export const leagueGameEvents = onDocumentWritten(
  "tournaments/{tournamentId}/divisions/{divisionId}/games/{gameId}",
  async (event) => {
    const { tournamentId, divisionId, gameId } = event.params;
    const db = getFirestore();
    const before = event.data?.before.data() as Data | undefined;
    const after = event.data?.after.data() as Data | undefined;
    const tournamentRef = db.doc(`tournaments/${tournamentId}`);
    const [tournamentSnap, divisionSnap, gameSnap] = await Promise.all([
      tournamentRef.get(),
      tournamentRef.collection("divisions").doc(divisionId).get(),
      tournamentRef.collection("divisions").doc(divisionId).collection("games").doc(gameId).get(),
    ]);
    const tournament = tournamentSnap.data() as Data | undefined;
    const game = gameSnap.data() as Data | undefined;
    // Only leagues; a deleted tournament's events go too (deleting one that
    // was never made does nothing).
    if (tournament && tournament.kind !== "league") return;

    const eventId = leagueEventId(tournamentId, divisionId, gameId);
    const staying = new Set(tournament && game ? gameTeams(game) : []);
    const involved = new Set([...gameTeams(before), ...gameTeams(after), ...staying]);
    if (involved.size === 0) return;

    const names: Record<string, string> = {};
    if (staying.size > 0) {
      const entries = await db.getAll(...[...staying].map((t) => tournamentRef.collection("entries").doc(t)));
      for (const e of entries) names[e.id] = String(e.get("teamName") ?? "");
    }
    const settings = (divisionSnap.get("settings") ?? {}) as Data;
    const minutes = typeof settings.gameMinutes === "number" ? settings.gameMinutes : 60;

    for (const teamId of involved) {
      const ref = db.doc(`teams/${teamId}/events/${eventId}`);
      const wanted =
        tournament && game
          ? leagueGameEvent({ tournamentId, tournament, game, teamId, names, minutes })
          : null;
      const [existing, team] = await Promise.all([ref.get(), db.doc(`teams/${teamId}`).get()]);
      if (!wanted) {
        if (existing.exists) {
          await ref.delete();
          logger.info("League game taken off a team's schedule", { tournamentId, divisionId, gameId, teamId });
        }
        continue;
      }
      if (!team.exists) continue;
      if (!existing.exists) {
        await ref.set({
          ...newLeagueGameEvent(wanted, team.data() as Data),
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        continue;
      }
      const update = changedGameEvent(existing.data() as Data, wanted);
      if (update) await ref.update({ ...update, updatedAt: FieldValue.serverTimestamp() });
    }
  },
);

export { createLeagueTeams } from "./callables";
