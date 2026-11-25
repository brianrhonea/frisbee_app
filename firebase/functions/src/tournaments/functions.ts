// Hosted tournaments on team schedules (see model.ts), exported as the
// `tournaments` group:
//   firebase deploy --only functions:tournaments
// The host accepting an entry isn't on the team, so rules don't let the
// app write the team's schedule; these triggers do it.

import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { onDocumentDeleted, onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";

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
  onlyLiveChanged,
  recordUpdate,
} from "./model";
import { captainsOf, capMembers, activeEntry, entryChatChange, organizersOf } from "./chat_members";

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
    // A running score changes nothing on the teams' schedules.
    if (onlyLiveChanged(before, after)) return;
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
export { draftControl, draftPick, finishDraft, startDraft } from "./draft";

/**
 * Keeps a tournament's chats with its organizers (the Captains' channel and
 * the team's own thread, when they've been opened) to the captains of
 * entries still in it: a withdrawn or declined team's captains drop out, a
 * newly applied team's join, and changed captains follow. The API works out
 * the same people whenever someone opens a chat, which also picks up
 * organizer and team admin changes.
 */
export const chatMembers = onDocumentWritten("tournaments/{tournamentId}/entries/{teamId}", async (event) => {
  const { tournamentId, teamId } = event.params;
  const before = event.data?.before.data() as Data | undefined;
  const after = event.data?.after.data() as Data | undefined;
  if (!entryChatChange(before, after)) return;
  const db = getFirestore();
  const [captainsPtr, teamPtr] = await db.getAll(
    db.doc(`tournaments/${tournamentId}/chats/captains`),
    db.doc(`tournaments/${tournamentId}/chats/team_${teamId}`),
  );
  if (!captainsPtr.exists && !teamPtr.exists) return;
  const t = (await db.doc(`tournaments/${tournamentId}`).get()).data();
  if (!t) return;
  const host = (await db.doc(`teams/${String(t.hostId ?? "")}`).get()).data();
  const organizers = organizersOf(host);
  if (teamPtr.exists) {
    const team = (await db.doc(`teams/${teamId}`).get()).data();
    await setMembers(String(teamPtr.data()?.conversationId ?? ""), capMembers([...organizers, ...captainsOf(after, team, true)]));
  }
  if (captainsPtr.exists) {
    const entries = (await db.collection(`tournaments/${tournamentId}/entries`).limit(500).get()).docs.filter((d) =>
      activeEntry(d.data()),
    );
    const teams = entries.length ? await db.getAll(...entries.map((d) => db.doc(`teams/${d.id}`))) : [];
    const captains = entries.flatMap((d, i) => captainsOf(d.data(), teams[i].data()));
    await setMembers(String(captainsPtr.data()?.conversationId ?? ""), capMembers([...organizers, ...captains]));
  }
});

/** Sets a chat's people, naming newcomers from their profiles and keeping everyone else's name. */
async function setMembers(conversationId: string, participants: string[]): Promise<void> {
  if (!/^g-[A-Za-z0-9]+$/.test(conversationId)) return;
  const db = getFirestore();
  const ref = db.doc(`conversations/${conversationId}`);
  await db.runTransaction(async (tx) => {
    const conv = (await tx.get(ref)).data();
    if (!conv || conv.kind !== "tournament") return;
    const known = (conv.names ?? {}) as Record<string, unknown>;
    const missing = participants.filter((u) => typeof known[u] !== "string");
    const profiles = missing.length ? await tx.getAll(...missing.map((u) => db.doc(`profiles/${u}`))) : [];
    const names: Record<string, string> = {};
    for (const u of participants) {
      const was = known[u];
      if (typeof was === "string") names[u] = was;
      else {
        const name = profiles[missing.indexOf(u)]?.data()?.name;
        names[u] = typeof name === "string" && name ? name.slice(0, 80) : "Player";
      }
    }
    tx.update(ref, { participants, names });
  });
  logger.info("tournament chat members", { conversationId, count: participants.length });
}

/**
 * A tournament deleted: its chats with the organizers go too (the
 * Captains' channel and each team's thread: their conversations, messages
 * and attachments), so they leave everyone's inbox. The API deletes them
 * first (TournamentService.remove); this catches a deletion any other way.
 */
export const tournamentDeleted = onDocumentDeleted("tournaments/{tournamentId}", async (event) => {
  const { tournamentId } = event.params;
  const db = getFirestore();
  const chats = await db.collection(`tournaments/${tournamentId}/chats`).get();
  for (const chat of chats.docs) {
    const id = String(chat.get("conversationId") ?? "");
    if (!/^g-[A-Za-z0-9]+$/.test(id)) continue;
    const ref = db.doc(`conversations/${id}`);
    const conv = (await ref.get()).data();
    // Only the tournament's own chat, never a conversation a pointer names wrongly.
    if (conv && (conv.kind !== "tournament" || conv.tournamentId !== tournamentId)) continue;
    await getStorage().bucket().deleteFiles({ prefix: `conversations/${id}/`, force: true });
    await db.recursiveDelete(ref);
  }
  await db.recursiveDelete(db.collection(`tournaments/${tournamentId}/chats`));
  if (!chats.empty) logger.info("Deleted a tournament's chats", { tournamentId, chats: chats.size });
});
