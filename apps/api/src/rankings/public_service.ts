// Stall 10's team rankings for signed-out visitors (the website's
// /rankings): what `match /rankings/{key}` in firebase/firestore.rules lets
// anyone signed in read, minus youth and anything about people.
//
// Youth is never shown: the `rankings` functions no longer write youth
// rankings or list youth teams, and on top of that a youth (or unknown)
// key, a doc whose level or division doesn't match its key, and any team
// whose listing or team doc is youth are left out here. So is a team
// whose listing is a private group, disagrees with its team doc, or is
// missing (isPrivateHost), and a drafted league team (its name is its
// players'). The rest are numbered again from 1, without gaps.
//
// Every answer is built field by field: rank, team id and name, rating,
// wins and losses. Never players.
import {
  orderedRankingKeys,
  parseRankingKey,
  type PublicDivisionRanking,
  type PublicRankedTeam,
  type PublicRankings,
} from "@stall10/shared";
import { validId } from "../browse/model.js";
import { isDraftedLeagueTeam, isPrivateHost, isYouthHost } from "../browse/visibility.js";
import { TtlCache } from "../ttl_cache.js";
import type { Data, PublicRankingRepository } from "./public_repository.js";

/**
 * The answer is kept this long in each instance: rankings change nightly
 * (or when a tournament goes final), and one answer reads every ranked
 * team's listing and team doc (up to 200 a division).
 */
export const publicRankingsCacheMs = 5 * 60_000;

/** Most teams a division lists (the functions' maxRanked). */
export const rankedTeamsMax = 200;

const whole = (v: unknown, min = Number.NEGATIVE_INFINITY): number | null =>
  typeof v === "number" && Number.isFinite(v) ? Math.max(min, Math.round(v)) : null;
const iso = (v: unknown): string | null => (typeof v === "string" && !Number.isNaN(Date.parse(v)) ? v : null);

type Candidate = Omit<PublicRankedTeam, "rank">;

/** A doc's teams in its order, the fields visitors get only; malformed ones and drafted league teams left out. */
function candidates(raw: unknown): Candidate[] {
  if (!Array.isArray(raw)) return [];
  const out: Candidate[] = [];
  for (const t of raw.slice(0, rankedTeamsMax)) {
    if (!t || typeof t !== "object") continue;
    const d = t as Data;
    const rating = whole(d.rating);
    if (!validId(d.teamId) || isDraftedLeagueTeam(d.teamId) || rating === null) continue;
    const name = typeof d.name === "string" && d.name.trim() ? d.name.trim().slice(0, 100) : "Team";
    out.push({ teamId: d.teamId, name, rating, wins: whole(d.wins, 0) ?? 0, losses: whole(d.losses, 0) ?? 0 });
  }
  return out;
}

export class PublicRankingService {
  private readonly cache: TtlCache<PublicRankings>;

  constructor(
    private readonly repo: PublicRankingRepository,
    now: () => number = Date.now,
  ) {
    this.cache = new TtlCache(publicRankingsCacheMs, 1, now);
  }

  /** Every ranking with teams visitors may see, by level then division. */
  list(): Promise<PublicRankings> {
    return this.cache.get("all", () => this.load());
  }

  private async load(): Promise<PublicRankings> {
    const docs = await this.repo.rankings();
    const byKey = new Map<string, { data: Data; teams: Candidate[] }>();
    for (const d of docs) {
      const p = parseRankingKey(d.id);
      // Never youth; and the doc must say the same as its id.
      if (!p || d.data.level !== p.level || d.data.division !== p.division) continue;
      byKey.set(d.id, { data: d.data, teams: candidates(d.data.teams) });
    }
    const ids = [...byKey.values()].flatMap((r) => r.teams.map((t) => t.teamId));
    const [listings, teams] = await Promise.all([this.repo.listings(ids), this.repo.teams(ids)]);
    const shown = (id: string) => {
      const listing = listings.get(id);
      const team = teams.get(id);
      return !isPrivateHost(listing, team) && !isYouthHost(listing, team);
    };

    const rankings: PublicDivisionRanking[] = [];
    for (const key of orderedRankingKeys(byKey.keys())) {
      const { data, teams: list } = byKey.get(key)!;
      const p = parseRankingKey(key)!;
      const visible: PublicRankedTeam[] = list
        .filter((t) => shown(t.teamId))
        .map((t, i) => ({ rank: i + 1, teamId: t.teamId, name: t.name, rating: t.rating, wins: t.wins, losses: t.losses }));
      if (visible.length === 0) continue;
      rankings.push({
        key,
        level: p.level,
        division: p.division,
        minGames: whole(data.minGames, 0) ?? 5,
        updatedAt: iso(data.updatedAt),
        teams: visible,
      });
    }
    return { rankings };
  }
}
