import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { syncRankings, syncTournaments } from "./usau/sync";

export * as notifications from "./notifications/triggers";

initializeApp();

const schedule = {
  timeZone: "America/Denver",
  timeoutSeconds: 540,
  memory: "512MiB" as const,
  retryCount: 1,
};

// Every two months (1st of Jan, Mar, May, Jul, Sep, Nov) while the user
// base is small; run more often as it grows.

/** Refreshes USA Ultimate tournaments into `usau_tournaments`. */
export const scrapeUsauTournaments = onSchedule(
  { ...schedule, schedule: "0 5 1 */2 *" },
  async () => {
    await syncTournaments(getFirestore());
  },
);

/** Refreshes USA Ultimate rankings into `usau_rankings`. */
export const scrapeUsauRankings = onSchedule(
  { ...schedule, schedule: "30 5 1 */2 *" },
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
