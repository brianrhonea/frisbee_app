import { Firestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  RankingRecord,
  USAU_BASE,
  parseRankSets,
  parseRankingsPage,
  parseTournaments,
} from "./parse";

const USER_AGENT = "FrisbeeApp/1.0 (team management app; daily sync)";
export const REQUEST_DELAY_MS = 1500;
/** Safety cap on pages per ranking list (20 teams each). */
const MAX_RANKING_PAGES = 50;

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function fetchHtml(
  url: string,
  init: { form?: Record<string, string>; cookies?: Map<string, string> } = {},
  fetchFn: typeof fetch = fetch,
): Promise<string> {
  const { form, cookies } = init;
  const headers: Record<string, string> = { "User-Agent": USER_AGENT, Accept: "text/html" };
  if (cookies && cookies.size > 0) {
    headers.Cookie = [...cookies].map(([k, v]) => `${k}=${v}`).join("; ");
  }
  const res = await fetchFn(url, {
    method: form ? "POST" : "GET",
    headers,
    body: form ? new URLSearchParams(form) : undefined,
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) throw new Error(`${form ? "POST" : "GET"} ${url} -> ${res.status}`);
  if (cookies) {
    // ASP.NET postbacks may depend on the session cookie.
    for (const c of res.headers.getSetCookie()) {
      const [pair] = c.split(";");
      const eq = pair.indexOf("=");
      if (eq > 0) cookies.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
    }
  }
  return res.text();
}

/**
 * Fetches every page of a rank set. The list is paged 20 teams at a time
 * behind ASP.NET postbacks, so each "Next" link is replayed as a form post
 * carrying the previous page's view state.
 */
export async function fetchAllRankings(
  url: string,
  { fetchFn = fetch, delayMs = REQUEST_DELAY_MS }: { fetchFn?: typeof fetch; delayMs?: number } = {},
): Promise<RankingRecord[]> {
  const cookies = new Map<string, string>();
  const entries: RankingRecord[] = [];
  const seen = new Set<string>();
  let pageUrl = url;
  let page = parseRankingsPage(await fetchHtml(pageUrl, { cookies }, fetchFn));
  for (let n = 1; ; n++) {
    const fresh = page.entries.filter((e) => {
      const key = `${e.rank}|${e.teamName}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
    entries.push(...fresh);
    // Stop if the server ignored the postback and re-sent the same page.
    if (!page.next || fresh.length === 0 || n >= MAX_RANKING_PAGES) break;
    pageUrl = new URL(page.next.action, pageUrl).toString();
    await sleep(delayMs);
    page = parseRankingsPage(
      await fetchHtml(pageUrl, { form: page.next.fields, cookies }, fetchFn),
      entries.length,
    );
  }
  return entries;
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
      const entries = await fetchAllRankings(set.url);
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
