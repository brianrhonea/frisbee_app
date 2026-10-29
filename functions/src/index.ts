import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { computeTeamElo, syncTeamGames } from "./usau/eloSync";
import { syncRankings, syncTournaments } from "./usau/sync";

initializeApp();

const schedule = {
  timeZone: "America/Denver",
  timeoutSeconds: 540,
  memory: "512MiB" as const,
  retryCount: 1,
};

/** Daily: refresh USA Ultimate tournaments into `usau_tournaments`. */
export const scrapeUsauTournaments = onSchedule(
  { ...schedule, schedule: "every day 05:00" },
  async () => {
    await syncTournaments(getFirestore());
  },
);

/** Daily: refresh USA Ultimate rankings into `usau_rankings`. */
export const scrapeUsauRankings = onSchedule(
  { ...schedule, schedule: "every day 05:30" },
  async () => {
    await syncRankings(getFirestore());
  },
);

/**
 * Hourly: scrape the next batch of ranked teams' game results into
 * `usau_team_games`. Batches cycle through every ranked team, so each team
 * is refreshed roughly every one to two days.
 */
export const scrapeUsauTeamGames = onSchedule(
  { ...schedule, schedule: "every 60 minutes" },
  async () => {
    await syncTeamGames(getFirestore());
  },
);

/** Daily: replay stored games into team Elo ratings in `usau_team_elo`. */
export const computeUsauTeamElo = onSchedule(
  { ...schedule, schedule: "every day 06:30" },
  async () => {
    await computeTeamElo(getFirestore());
  },
);

/**
 * Manual trigger for local development only (not exported in production):
 * `curl http://127.0.0.1:5001/<project>/us-central1/refreshUsau`
 * Add `?elo=1` to also scrape one batch of team games and recompute Elo.
 */
export const refreshUsau =
  process.env.FUNCTIONS_EMULATOR === "true"
    ? onRequest({ timeoutSeconds: 3600 }, async (req, res) => {
        const db = getFirestore();
        const tournaments = await syncTournaments(db);
        const rankSets = await syncRankings(db);
        if (req.query.elo !== "1") {
          res.json({ tournaments, rankSets });
          return;
        }
        const teams = await syncTeamGames(db);
        const eloDivisions = await computeTeamElo(db);
        res.json({ tournaments, rankSets, teams, eloDivisions });
      })
    : undefined;
