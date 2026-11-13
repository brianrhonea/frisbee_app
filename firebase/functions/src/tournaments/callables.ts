// Callables for hosted tournaments, exported with the `tournaments` group.

import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { enforceAppCheck } from "../options";
import {
  canManageEvents,
  type Data,
  defaultChat,
  directoryDoc,
  draftTeams,
  leagueEntry,
  leagueProblem,
  leagueTeamId,
  madeTeams,
  teamDoc,
  teamsCreated,
} from "./league";

const idPattern = /^[A-Za-z0-9_-]{1,60}$/;

/**
 * Turns a league's drafted teams into real teams: the captain owns each,
 * the other players are its members, and it gets a General room, voice
 * rooms, a directory listing and an accepted entry in the league. The
 * division's teams, seeds and captains switch to the real ids in the same
 * batch, so it's all or nothing, and calling it again changes nothing.
 *
 * It's a function, not a rule, because the app can't put other people on a
 * team it creates (a team starts with its creator as the only member), and
 * letting it would let anyone add anyone. The server instead checks the
 * caller manages the league and that every player has an accepted signup.
 */
export const createLeagueTeams = onCall({ enforceAppCheck }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to create teams.");
  const { tournamentId, divisionId } = (req.data ?? {}) as { tournamentId?: unknown; divisionId?: unknown };
  if (typeof tournamentId !== "string" || !idPattern.test(tournamentId)) {
    throw new HttpsError("invalid-argument", "Pick a league.");
  }
  if (typeof divisionId !== "string" || !idPattern.test(divisionId)) {
    throw new HttpsError("invalid-argument", "Pick a division.");
  }

  const db = getFirestore();
  const tournamentRef = db.doc(`tournaments/${tournamentId}`);
  const divisionRef = tournamentRef.collection("divisions").doc(divisionId);
  const [tournamentSnap, divisionSnap] = await Promise.all([tournamentRef.get(), divisionRef.get()]);
  const tournament = tournamentSnap.data() as Data | undefined;
  const division = divisionSnap.data() as Data | undefined;
  if (!tournament || !division) throw new HttpsError("not-found", "That league or division doesn't exist.");

  const host = await db.doc(`teams/${String(tournament.hostId)}`).get();
  if (!canManageEvents(host.data() as Data | undefined, uid)) {
    throw new HttpsError("permission-denied", "Only the league's organizers can create its teams.");
  }

  const drafted = draftTeams(division.teams);
  if (teamsCreated(drafted)) {
    return { created: 0, teams: drafted.map((t) => ({ teamId: t.id, name: t.name })) };
  }

  const [signups, games] = await Promise.all([
    tournamentRef
      .collection("signups")
      .where("divisionId", "==", divisionId)
      .where("status", "==", "accepted")
      .get(),
    divisionRef.collection("games").limit(1).get(),
  ]);
  const problem = leagueProblem({
    tournament,
    division,
    teams: drafted,
    accepted: new Set(signups.docs.map((d) => d.id)),
    hasGames: !games.empty,
  });
  if (problem) throw new HttpsError("failed-precondition", problem);

  const city = typeof host.get("city") === "string" ? (host.get("city") as string) : "";
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  // A team made by an earlier, interrupted attempt keeps its own doc.
  const refs = drafted.map((t) => db.doc(`teams/${leagueTeamId(tournamentId, t.id)}`));
  const existing = new Set((await db.getAll(...refs)).filter((s) => s.exists).map((s) => s.id));

  for (const [i, team] of drafted.entries()) {
    const teamId = refs[i].id;
    if (!existing.has(teamId)) {
      const doc = teamDoc({ team, tournamentId, tournament, division, city, createdAt: now });
      batch.set(refs[i], doc);
      batch.set(db.doc(`teamDirectory/${teamId}`), directoryDoc(doc));
      const chat = defaultChat(team.captainId as string, now);
      for (const [id, room] of Object.entries(chat.rooms)) batch.set(refs[i].collection("chats").doc(id), room);
      for (const [id, folder] of Object.entries(chat.folders)) {
        batch.set(refs[i].collection("chatFolders").doc(id), folder);
      }
    }
    batch.set(tournamentRef.collection("entries").doc(teamId), leagueEntry(team, divisionId, now));
  }
  batch.update(divisionRef, madeTeams(drafted, tournamentId, division));
  await batch.commit();
  logger.info("League teams created", { tournamentId, divisionId, teams: drafted.length, by: uid });
  return { created: drafted.length - existing.size, teams: refs.map((r, i) => ({ teamId: r.id, name: drafted[i].name })) };
});
