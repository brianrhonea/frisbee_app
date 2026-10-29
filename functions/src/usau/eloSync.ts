import { Firestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import { EloGame, rateTeams } from "../elo/teamElo";
import { REQUEST_DELAY_MS, fetchHtml, sleep } from "./sync";
import { TeamEvent, TeamGame, parseTeamPage, parseTeamTabs, resolveGameDate } from "./team";

/** Teams scraped per run: two requests each at 1.5s keeps a run near 3 min. */
const TEAMS_PER_RUN = 60;
/** Cap on extra tab requests per team page. */
const MAX_TEAM_TABS = 3;
/** Teams need this many games before they're listed. */
const MIN_GAMES = 3;

/** A played game from one team's point of view, as stored per team. */
export interface StoredGame {
  playedOn: string;
  tournament: string;
  opponent: string;
  opponentUrl: string;
  scoreFor: number;
  scoreAgainst: number;
}

export interface RankedTeam {
  teamName: string;
  teamUrl: string;
}

export interface TeamGamesDoc {
  teamName: string;
  teamUrl: string;
  games: StoredGame[];
}

export interface EloEntry {
  rank: number;
  teamName: string;
  teamUrl: string;
  elo: number;
  games: number;
  wins: number;
  losses: number;
}

type FetchOptions = { fetchFn?: typeof fetch; delayMs?: number; year?: number };

/**
 * Scrapes a team page plus its "Events & Schedule" tabs and returns its
 * played games, dated and de-duplicated. Unplayed games are dropped.
 */
export async function fetchTeamGames(
  url: string,
  { fetchFn = fetch, delayMs = REQUEST_DELAY_MS, year = new Date().getUTCFullYear() }: FetchOptions = {},
): Promise<StoredGame[]> {
  const cookies = new Map<string, string>();
  const html = await fetchHtml(url, { cookies }, fetchFn);
  const pages = [parseTeamPage(html)];
  for (const tab of parseTeamTabs(html, url).slice(0, MAX_TEAM_TABS)) {
    await sleep(delayMs);
    try {
      const tabHtml = await fetchHtml(
        tab.url,
        { form: tab.fields ?? undefined, cookies },
        fetchFn,
      );
      pages.push(parseTeamPage(tabHtml));
    } catch (e) {
      logger.warn(`Failed to load team tab ${tab.url}`, e);
    }
  }

  const events = new Map<string, TeamEvent>();
  for (const p of pages) for (const e of p.events) if (!events.has(e.name)) events.set(e.name, e);

  const out: StoredGame[] = [];
  const seen = new Set<string>();
  const games: TeamGame[] = pages.flatMap((p) => p.games);
  for (const g of games) {
    if (g.scoreFor === null || g.scoreAgainst === null) continue;
    const key = `${g.tournament}|${g.date}|${g.opponent}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const playedOn = resolveGameDate(g.date, events.get(g.tournament), year);
    if (!playedOn) continue;
    out.push({
      playedOn,
      tournament: g.tournament,
      opponent: g.opponent,
      opponentUrl: g.opponentUrl,
      scoreFor: g.scoreFor,
      scoreAgainst: g.scoreAgainst,
    });
  }
  return out;
}

const normalizeName = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

const teamIdOf = (url: string): string | null => {
  try {
    return url ? new URL(url).searchParams.get("TeamId") : null;
  } catch {
    return null;
  }
};

/**
 * Rates one division from its teams' stored games.
 *
 * Teams are identified by USAU TeamId where a link exists, else by name
 * (matched to a ranked team's name when possible). Each game appears on both
 * teams' pages, so it is de-duplicated on date, event, the pair of teams and
 * the score before the replay. Opponents outside the rankings still count
 * toward the replay but are listed only if they have a link.
 */
export function buildDivisionElo(ranked: RankedTeam[], docs: TeamGamesDoc[]): EloEntry[] {
  const idByName = new Map<string, string>();
  const info = new Map<string, RankedTeam>();
  const keyFor = (name: string, url: string): string => {
    const id = teamIdOf(url);
    const key = id ? `id:${id}` : (idByName.get(normalizeName(name)) ?? `name:${normalizeName(name)}`);
    if (!info.has(key) || (!info.get(key)!.teamUrl && url)) info.set(key, { teamName: name, teamUrl: url });
    return key;
  };
  for (const t of ranked) {
    const key = keyFor(t.teamName, t.teamUrl);
    idByName.set(normalizeName(t.teamName), key);
    info.set(key, t);
  }

  const games: EloGame[] = [];
  const seen = new Set<string>();
  for (const doc of docs) {
    const self = keyFor(doc.teamName, doc.teamUrl);
    for (const g of doc.games) {
      const opp = keyFor(g.opponent, g.opponentUrl);
      if (opp === self) continue;
      const [a, b, sa, sb] =
        self < opp ? [self, opp, g.scoreFor, g.scoreAgainst] : [opp, self, g.scoreAgainst, g.scoreFor];
      const key = `${g.playedOn}|${g.tournament}|${a}|${b}|${sa}-${sb}`;
      if (seen.has(key)) continue;
      seen.add(key);
      games.push({ playedOn: g.playedOn, a, b, scoreA: sa, scoreB: sb });
    }
  }

  return rateTeams(games)
    .filter((r) => r.games >= MIN_GAMES && info.get(r.team)?.teamUrl)
    .map((r, i) => ({
      rank: i + 1,
      teamName: info.get(r.team)!.teamName,
      teamUrl: info.get(r.team)!.teamUrl,
      elo: Math.round(r.elo * 10) / 10,
      games: r.games,
      wins: r.wins,
      losses: r.losses,
    }));
}

const teamDocId = (division: string, url: string) =>
  `${division}__${(teamIdOf(url) ?? url).replace(/[^A-Za-z0-9_-]/g, "-")}`.slice(0, 1400);

async function rankedDivisions(db: Firestore) {
  const snap = await db.collection("usau_rankings").get();
  return snap.docs
    .map((d) => ({
      key: d.id,
      label: (d.get("label") as string) ?? d.id,
      teams: ((d.get("entries") as RankedTeam[] | undefined) ?? [])
        .filter((e) => e.teamUrl)
        .map((e) => ({ teamName: e.teamName, teamUrl: e.teamUrl })),
    }))
    .sort((a, b) => a.key.localeCompare(b.key));
}

/**
 * Scrapes the next `TEAMS_PER_RUN` ranked teams' games into
 * `usau_team_games`, resuming from a cursor so repeated runs cycle through
 * every ranked team.
 */
export async function syncTeamGames(db: Firestore): Promise<number> {
  const queue = (await rankedDivisions(db)).flatMap((d) =>
    d.teams.map((t) => ({ division: d.key, ...t })),
  );
  if (queue.length === 0) {
    logger.warn("No ranked teams to scrape; run syncRankings first");
    return 0;
  }
  const meta = db.collection("meta").doc("usau");
  const start = (((await meta.get()).get("teamGamesCursor") as number | undefined) ?? 0) % queue.length;

  let done = 0;
  for (let i = 0; i < Math.min(TEAMS_PER_RUN, queue.length); i++) {
    const team = queue[(start + i) % queue.length];
    await sleep(REQUEST_DELAY_MS);
    try {
      const games = await fetchTeamGames(team.teamUrl);
      await db.collection("usau_team_games").doc(teamDocId(team.division, team.teamUrl)).set({
        division: team.division,
        teamName: team.teamName,
        teamUrl: team.teamUrl,
        games,
        fetchedAt: Timestamp.now(),
      });
      done++;
    } catch (e) {
      logger.error(`Failed to scrape games for ${team.teamName}`, e);
    }
  }
  await meta.set(
    { teamGamesCursor: (start + TEAMS_PER_RUN) % queue.length, teamGamesSyncedAt: Timestamp.now() },
    { merge: true },
  );
  logger.info(`Scraped games for ${done} teams (cursor ${start}/${queue.length})`);
  return done;
}

/** Replays each division's stored games and writes `usau_team_elo/{key}`. */
export async function computeTeamElo(db: Firestore): Promise<number> {
  const divisions = await rankedDivisions(db);
  let written = 0;
  for (const d of divisions) {
    const snap = await db.collection("usau_team_games").where("division", "==", d.key).get();
    const docs = snap.docs.map((s) => s.data() as TeamGamesDoc);
    const entries = buildDivisionElo(d.teams, docs);
    if (entries.length === 0) continue;
    await db.collection("usau_team_elo").doc(d.key).set({
      label: d.label,
      updatedAt: Timestamp.now(),
      teamsScraped: docs.length,
      entries,
    });
    written++;
  }
  logger.info(`Wrote Elo for ${written}/${divisions.length} divisions`);
  return written;
}
