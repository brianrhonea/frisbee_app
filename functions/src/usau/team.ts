import * as cheerio from "cheerio";
import type { Element } from "domhandler";

import { PostBack, absolute, clean, parseDateRange, postBackFor } from "./parse";

/**
 * TS port of the team-page parts of `lib/data/services/usau/usau_parser.dart`
 * (games, events and the "Events & Schedule" tabs). Keep the two in sync.
 */

export interface TeamGame {
  tournament: string;
  /** As printed, e.g. "Aug 3"; USAU omits the year on schedules. */
  date: string;
  opponent: string;
  opponentUrl: string;
  /** Null until the game has a posted score. */
  scoreFor: number | null;
  scoreAgainst: number | null;
}

export interface TeamEvent {
  name: string;
  startDate: Date | null;
  endDate: Date | null;
}

export interface TeamPage {
  games: TeamGame[];
  events: TeamEvent[];
}

type Cheerio = cheerio.CheerioAPI;

/** Rows of `table` itself, not of tables nested in it. */
const ownRows = ($: Cheerio, table: Element) =>
  $(table)
    .find("tr")
    .filter((_, tr) => $(tr).closest("table")[0] === table);

/** Header index per column, from the header row matching the most columns. */
function matchHeaders<C extends string>(
  $: Cheerio,
  table: Element,
  patterns: [C, RegExp][],
): Map<C, number> {
  let best = new Map<C, number>();
  ownRows($, table).each((_, tr) => {
    const headers = $(tr).children("th");
    if (headers.length === 0) return;
    const cols = new Map<C, number>();
    headers.each((i, th) => {
      const text = clean($(th).text());
      for (const [col, re] of patterns) {
        if (!cols.has(col) && re.test(text)) {
          cols.set(col, i);
          break;
        }
      }
    });
    if (cols.size > best.size) best = cols;
  });
  return best;
}

type GameColumn = "date" | "score" | "opponent";
const GAME_PATTERNS: [GameColumn, RegExp][] = [
  ["date", /^date/i],
  ["score", /score|result/i],
  ["opponent", /^(opponent|vs\.?|versus)/i],
];

type EventColumn = "name" | "date";
const EVENT_PATTERNS: [EventColumn, RegExp][] = [
  ["name", /^(event|tournament)/i],
  ["date", /date/i],
];

/** "13 - 9" -> [13, 9]; anything else (blank, "TBD", "W - L") -> null. */
export function parseScore(text: string): [number, number] | null {
  const m = /(\d+)\s*-\s*(\d+)/.exec(text);
  return m ? [Number(m[1]), Number(m[2])] : null;
}

export function parseTeamPage(html: string): TeamPage {
  const $ = cheerio.load(html);
  const games: TeamGame[] = [];
  const events: TeamEvent[] = [];

  $("table").each((_, table) => {
    const gameCols = matchHeaders($, table, GAME_PATTERNS);
    const opponentIdx = gameCols.get("opponent");
    if (opponentIdx !== undefined) {
      let tournament = clean($(table).children("caption").text());
      ownRows($, table).each((_, tr) => {
        const all = $(tr).children("td, th");
        if (all.length === 1) {
          const text = clean(all.text());
          if (text) tournament = text;
          return;
        }
        const cells = $(tr).children("td");
        if (cells.length <= opponentIdx) return;
        const cell = (c: GameColumn) => {
          const i = gameCols.get(c);
          return i === undefined ? "" : clean(cells.eq(i).text());
        };
        const opponentCell = cells.eq(opponentIdx);
        const opponent = clean(opponentCell.text());
        if (!opponent) return;
        const score = parseScore(cell("score"));
        games.push({
          tournament,
          date: cell("date"),
          opponent,
          opponentUrl: absolute(opponentCell.find("a").attr("href")),
          scoreFor: score?.[0] ?? null,
          scoreAgainst: score?.[1] ?? null,
        });
      });
      return;
    }

    const eventCols = matchHeaders($, table, EVENT_PATTERNS);
    const nameIdx = eventCols.get("name");
    const dateIdx = eventCols.get("date");
    if (nameIdx === undefined || dateIdx === undefined) return;
    ownRows($, table).each((_, tr) => {
      const cells = $(tr).children("td");
      if (cells.length <= Math.max(nameIdx, dateIdx)) return;
      if (cells.find("table").length > 0) return;
      const name = clean(cells.eq(nameIdx).text());
      if (!name) return;
      const [startDate, endDate] = parseDateRange(cells.eq(dateIdx).text());
      events.push({ name, startDate, endDate });
    });
  });
  return { games, events };
}

/** A follow-up request for another tab: GET `url`, or POST `fields` to it. */
export interface TabRequest {
  url: string;
  fields: Record<string, string> | null;
}

const SCHEDULE_TAB = /\b(events?|schedule)\b/i;

/**
 * Finds the team page's separately loaded "Events" / "Schedule" tabs. In-page
 * anchors are skipped, and plain links count only when they stay on this team
 * (so the site's "Events" menu is ignored).
 */
export function parseTeamTabs(html: string, pageUrl: string): TabRequest[] {
  const $ = cheerio.load(html);
  const page = new URL(pageUrl);
  const teamId = page.searchParams.get("TeamId");
  const out: TabRequest[] = [];
  const seen = new Set<string>();
  $("a[href]").each((_, a) => {
    const text = clean($(a).text());
    if (!text || text.length > 30 || !SCHEDULE_TAB.test(text)) return;
    const href = ($(a).attr("href") ?? "").trim();
    if (href.startsWith("#")) return;
    if (href.includes("__doPostBack")) {
      const pb: PostBack | null = postBackFor($, a);
      if (!pb || seen.has(pb.fields.__EVENTTARGET)) return;
      seen.add(pb.fields.__EVENTTARGET);
      out.push({ url: new URL(pb.action, page).toString(), fields: pb.fields });
      return;
    }
    let target: URL;
    try {
      target = new URL(href, page);
    } catch {
      return;
    }
    target.hash = "";
    const url = target.toString();
    const sameTeam =
      teamId !== null &&
      target.host === page.host &&
      target.searchParams.get("TeamId") === teamId;
    if (!sameTeam || url === page.toString() || seen.has(url)) return;
    seen.add(url);
    out.push({ url, fields: null });
  });
  return out;
}

const MONTHS: Record<string, number> = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
  jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
};

/**
 * Resolves a schedule date like "Aug 3" or "Sat 8/3" to "YYYY-MM-DD", taking
 * the year from the game's event (or `fallbackYear`). A full date with a
 * year is used as printed. Returns null when the date can't be read.
 */
export function resolveGameDate(
  text: string,
  event: TeamEvent | undefined,
  fallbackYear: number,
): string | null {
  const iso = (y: number, m: number, d: number) =>
    `${y}-${String(m + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
  const year = (event?.startDate ?? event?.endDate)?.getUTCFullYear() ?? fallbackYear;

  const named = /([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})(?:,\s*(\d{4}))?/.exec(text);
  if (named && MONTHS[named[1].toLowerCase()] !== undefined) {
    return iso(named[3] ? Number(named[3]) : year, MONTHS[named[1].toLowerCase()], Number(named[2]));
  }
  const numeric = /(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?/.exec(text);
  if (numeric) {
    const y = numeric[3] ? Number(numeric[3].length === 2 ? `20${numeric[3]}` : numeric[3]) : year;
    return iso(y, Number(numeric[1]) - 1, Number(numeric[2]));
  }
  // No usable game date: fall back to the event's first day.
  const start = event?.startDate;
  return start ? iso(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate()) : null;
}
