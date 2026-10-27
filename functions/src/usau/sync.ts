import { Firestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  USAU_BASE,
  parseRankSets,
  parseRankings,
  parseTournaments,
} from "./parse";

const USER_AGENT = "FrisbeeApp/1.0 (team management app; daily sync)";
const REQUEST_DELAY_MS = 1500;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function fetchHtml(url: string): Promise<string> {
  const res = await fetch(url, {
    headers: { "User-Agent": USER_AGENT, Accept: "text/html" },
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) throw new Error(`GET ${url} -> ${res.status}`);
  return res.text();
}

const ts = (d: Date | null) => (d ? Timestamp.fromDate(d) : null);

/** Scrapes the tournament list and upserts `usau_tournaments`. */
export async function syncTournaments(db: Firestore): Promise<number> {
  const html = await fetchHtml(`${USAU_BASE}/events/tournament/`);
  const tournaments = parseTournaments(html);
  if (tournaments.length === 0) {
    // Likely a layout change; keep existing data rather than wiping it.
    throw new Error("Parsed 0 tournaments; USAU page layout may have changed");
  }

  const now = Timestamp.now();
  const writer = db.bulkWriter();
  for (const t of tournaments) {
    writer.set(
      db.collection("usau_tournaments").doc(t.id),
      { ...t, startDate: ts(t.startDate), endDate: ts(t.endDate), syncedAt: now },
      { merge: true },
    );
  }
  writer.set(
    db.collection("meta").doc("usau"),
    { tournamentsSyncedAt: now, tournamentCount: tournaments.length },
    { merge: true },
  );
  await writer.close();
  logger.info(`Synced ${tournaments.length} tournaments`);
  return tournaments.length;
}

/** Scrapes every published rank set and writes `usau_rankings/{key}`. */
export async function syncRankings(db: Firestore): Promise<number> {
  const sets = parseRankSets(
    await fetchHtml(`${USAU_BASE}/teams/events/rankings/`),
  );
  if (sets.length === 0) {
    throw new Error("Parsed 0 rank sets; USAU page layout may have changed");
  }

  let synced = 0;
  for (const set of sets) {
    await sleep(REQUEST_DELAY_MS);
    try {
      const entries = parseRankings(await fetchHtml(set.url));
      if (entries.length === 0) {
        logger.warn(`No ranking rows parsed for ${set.key}`, { url: set.url });
        continue;
      }
      await db.collection("usau_rankings").doc(set.key).set({
        label: set.label,
        title: set.title,
        sourceUrl: set.url,
        updatedAt: Timestamp.now(),
        entries,
      });
      synced++;
    } catch (e) {
      logger.error(`Failed to sync rankings for ${set.key}`, e);
    }
  }
  await db
    .collection("meta")
    .doc("usau")
    .set({ rankingsSyncedAt: Timestamp.now(), rankSetCount: synced }, { merge: true });
  logger.info(`Synced ${synced}/${sets.length} rank sets`);
  return synced;
}
