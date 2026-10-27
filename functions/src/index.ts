import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

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
 * Manual trigger for local development only (not exported in production):
 * `curl http://127.0.0.1:5001/<project>/us-central1/refreshUsau`
 */
export const refreshUsau =
  process.env.FUNCTIONS_EMULATOR === "true"
    ? onRequest({ timeoutSeconds: 540 }, async (_req, res) => {
        const db = getFirestore();
        const tournaments = await syncTournaments(db);
        const rankSets = await syncRankings(db);
        res.json({ tournaments, rankSets });
      })
    : undefined;
