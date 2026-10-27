import * as cheerio from "cheerio";
import type { Element } from "domhandler";

export const USAU_BASE = "https://play.usaultimate.org";

export interface TournamentRecord {
  id: string;
  name: string;
  url: string;
  /** UTC noon on the event day, so it renders as the same date in US zones. */
  startDate: Date | null;
  endDate: Date | null;
  city: string;
  state: string;
  competitionLevel: string;
  divisions: string[];
}

export interface RankSet {
  /** e.g. "Club-Men"; also the Firestore document id. */
  key: string;
  /** e.g. "Club Men". */
  label: string;
  /** e.g. "2026 Men's Final Rankings". */
  title: string;
  url: string;
}

export interface RankingRecord {
  rank: number;
  teamName: string;
  rating: number | null;
  wins: number | null;
  losses: number | null;
  region: string;
  teamUrl: string;
}

const clean = (s: string | undefined): string =>
  (s ?? "").replace(/\s+/g, " ").trim();

const absolute = (href: string | undefined): string => {
  if (!href) return "";
  try {
    return new URL(href, USAU_BASE).toString();
  } catch {
    return "";
  }
};

const MONTHS: Record<string, number> = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
  jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
};

/** Parses "Nov 07, 2026". */
export function parseUsauDate(text: string): Date | null {
  const m = /([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),\s*(\d{4})/.exec(text);
  if (!m) return null;
  const month = MONTHS[m[1].toLowerCase()];
  if (month === undefined) return null;
  return new Date(Date.UTC(Number(m[3]), month, Number(m[2]), 12));
}

/** Parses "Nov 07, 2026 - Nov 08, 2026" (end optional). */
export function parseDateRange(text: string): [Date | null, Date | null] {
  const [start, end] = clean(text).split(/\s+-\s+/);
  const s = parseUsauDate(start ?? "");
  const e = end ? parseUsauDate(end) : s;
  return [s, e];
}

const titleCase = (s: string): string =>
  s.toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase());

const DIVISION_WORDS = ["Mixed", "Women", "Men", "Girls", "Boys", "Open"];

/**
 * Splits a competition group such as "College - Women",
 * "High School - Mixed DI" or "Club - Mixed Division 3" into
 * level ("College") and division ("Women").
 */
export function parseCompetitionGroup(
  group: string,
): { level: string; division: string } {
  const g = clean(group);
  const dash = g.indexOf(" - ");
  const level = dash >= 0 ? titleCase(g.slice(0, dash)) : "";
  const rest = dash >= 0 ? g.slice(dash + 3) : g;
  const division =
    DIVISION_WORDS.find((w) => new RegExp(`\\b${w}\\b`, "i").test(rest)) ??
    "";
  return { level, division };
}

const slugFromHref = (href: string): string =>
  href
    .replace(/^.*\/events\//i, "")
    .replace(/[/?#].*$/, "")
    .replace(/[^A-Za-z0-9_-]/g, "-")
    .slice(0, 200);

/**
 * Parses the "Current/Upcoming Events" and "Past Events" tables on
 * play.usaultimate.org/events/tournament/.
 */
export function parseTournaments(html: string): TournamentRecord[] {
  const $ = cheerio.load(html);
  const out = new Map<string, TournamentRecord>();

  $("table[id$='gvCurrentUpcomingEvents'], table[id$='gvPastEvents']")
    .find("tr")
    .each((_, tr) => {
      const cells = $(tr).children("td");
      if (cells.length < 6) return;
      const link = cells.eq(1).find("a[href*='/events/']").first();
      const href = link.attr("href");
      if (!href) return;
      const id = slugFromHref(href);
      if (!id) return;

      const levels = new Map<string, number>();
      const divisions = new Set<string>();
      cells
        .eq(4)
        .find("li")
        .each((_, li) => {
          // Strip the "[24]" team count.
          const text = clean($(li).clone().children("span").remove().end().text());
          const { level, division } = parseCompetitionGroup(text);
          if (level) levels.set(level, (levels.get(level) ?? 0) + 1);
          if (division) divisions.add(division);
        });
      const competitionLevel =
        [...levels.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "";
      const [startDate, endDate] = parseDateRange(cells.eq(5).text());

      out.set(id, {
        id,
        name: clean(link.text()),
        url: absolute(href),
        startDate,
        endDate,
        city: clean(cells.eq(2).text()),
        state: clean(cells.eq(3).text()),
        competitionLevel,
        divisions: [...divisions].sort(),
      });
    });

  return [...out.values()];
}

/**
 * Parses the published rank sets listed on
 * play.usaultimate.org/teams/events/rankings/. Keeps the first (newest)
 * entry per rank set.
 */
export function parseRankSets(html: string): RankSet[] {
  const $ = cheerio.load(html);
  const out = new Map<string, RankSet>();
  $("table[id$='gvRankSetList'] tr").each((_, tr) => {
    const cells = $(tr).children("td");
    if (cells.length < 5) return;
    const status = clean(cells.eq(1).text());
    if (!/published/i.test(status)) return;
    const href = cells.eq(4).find("a[href*='RankSet=']").attr("href");
    if (!href) return;
    const url = absolute(href);
    const key = new URL(url).searchParams.get("RankSet");
    if (!key || out.has(key)) return;
    out.set(key, {
      key: key.replace(/[^A-Za-z0-9_-]/g, "-"),
      label: clean(cells.eq(2).text()) || key.replace(/-/g, " "),
      title: clean(cells.eq(0).text()),
      url,
    });
  });
  return [...out.values()];
}

const toInt = (s: string): number | null => {
  const n = parseInt(s.replace(/[^\d-]/g, ""), 10);
  return Number.isFinite(n) ? n : null;
};

const toFloat = (s: string): number | null => {
  const n = parseFloat(s.replace(/[^\d.-]/g, ""));
  return Number.isFinite(n) ? n : null;
};

type Column = "rank" | "team" | "rating" | "wins" | "losses" | "record" | "region";

const COLUMN_PATTERNS: [Column, RegExp][] = [
  ["rank", /^rank$|^#$|^place$/i],
  ["team", /^team/i],
  ["rating", /rating|power/i],
  ["wins", /^wins?$|^w$/i],
  ["losses", /^loss(es)?$|^l$/i],
  ["record", /record|w\s*-\s*l/i],
  ["region", /region|section|conference/i],
];

/**
 * Parses a team rankings page (team_rankings/?RankSet=...).
 *
 * The layout is matched by header names rather than positions so it keeps
 * working if columns are added or reordered. Rows without an explicit rank
 * column are ranked by order.
 */
export function parseRankings(html: string): RankingRecord[] {
  const $ = cheerio.load(html);

  let best: { table: Element; columns: Map<Column, number> } | null = null;
  $("table").each((_, table) => {
    const headerRow = $(table).find("tr").filter((_, tr) => $(tr).children("th").length > 0).first();
    const columns = new Map<Column, number>();
    headerRow.children("th").each((i, th) => {
      const text = clean($(th).text());
      for (const [col, re] of COLUMN_PATTERNS) {
        if (!columns.has(col) && re.test(text)) {
          columns.set(col, i);
          break;
        }
      }
    });
    if (columns.has("team") && (columns.has("rank") || columns.has("rating"))) {
      if (!best || columns.size > best.columns.size) best = { table, columns };
    }
  });
  if (!best) return [];
  const { table, columns } = best as { table: Element; columns: Map<Column, number> };

  const out: RankingRecord[] = [];
  $(table)
    .find("tr")
    .each((_, tr) => {
      const cells = $(tr).children("td");
      const teamIdx = columns.get("team")!;
      if (cells.length <= teamIdx) return;
      const cell = (c: Column): string => {
        const i = columns.get(c);
        return i === undefined ? "" : clean(cells.eq(i).text());
      };
      const teamCell = cells.eq(teamIdx);
      const teamName = clean(teamCell.text());
      if (!teamName) return;

      let wins = toInt(cell("wins"));
      let losses = toInt(cell("losses"));
      const record = /(\d+)\s*-\s*(\d+)/.exec(cell("record"));
      if (record && wins === null && losses === null) {
        wins = Number(record[1]);
        losses = Number(record[2]);
      }

      out.push({
        rank: toInt(cell("rank")) ?? out.length + 1,
        teamName,
        rating: toFloat(cell("rating")),
        wins,
        losses,
        region: cell("region"),
        teamUrl: absolute(teamCell.find("a").attr("href")),
      });
    });
  return out;
}
