// A player's roster history (`GET /v1/players/:uid/team-history`): every
// team an admin linked them to, the ones they left included, with their
// season totals from each. The phone keeps no record of teams a person has
// left (their rosters and games are members' only), so the server reads
// them with the Admin SDK and decides who may see what here.
//
// Who sees what:
//  - the person: every team they are linked to, whatever the profile's
//    visibility settings say;
//  - anyone else signed in: only what the profile itself shows them (a
//    public profile with both `stats` and `teams` shown, as browse's
//    profileView), and still not a youth team, a team whose public page is
//    off, or a league's drafted team unless they're a member of it. A
//    private profile, or one hiding stats or teams, gives an empty history.
// Nothing here names another person: no uids, no roster, no members.
import {
  addSeasonTotals,
  orderTeamHistory,
  rosterIsPublic,
  type SeasonTotals,
  seasonTotalsForSpots,
  type TeamHistory,
  type TeamHistoryEntry,
  teamHistoryGameBudget,
  teamHistoryMaxGames,
  teamHistoryMaxSpots,
} from "@stall10/shared";
import type { AdultVisibility } from "../account/adult_visibility.js";
import { type Caller } from "../auth.js";
import { isPrivateProfile, validId } from "../browse/model.js";
import { isDraftedLeagueTeam } from "../browse/visibility.js";
import { ApiError } from "../errors.js";
import { blockedBetween } from "../moderation/service.js";
import type { DocQueries } from "../queries.js";
import type { Data, DocStore } from "../store.js";
import { isMember, kindOf, mapOf } from "./access.js";
import type { RosterService } from "./roster.js";

/** Games read per query (a stats game can be ~900 KB). */
const gamePage = 20;
/** How long a caller's history of one player is served from memory. */
const cacheMs = 60_000;
/** Most cached histories per instance; the oldest goes first. */
const cacheMax = 500;

/** Lets the event loop serve other requests between pages. */
const yieldLoop = () => new Promise<void>((resolve) => setImmediate(resolve));

const str = (v: unknown) => (typeof v === "string" ? v : "");

export class TeamHistoryService {
  /** Callers with a history request running on this instance. */
  private readonly running = new Set<string>();
  /** `caller:target` to a recent answer. */
  private readonly cache = new Map<string, { at: number; value: TeamHistory }>();

  constructor(
    private readonly store: DocStore,
    private readonly queries: DocQueries,
    private readonly roster: RosterService,
    private readonly adults?: AdultVisibility,
  ) {}

  /** Whether the profile of [uid] shows its teams and stats to a signed-in stranger. */
  private async shownToOthers(uid: string): Promise<boolean> {
    const profile = await this.store.get(`profiles/${uid}`);
    // The profile endpoint's refusals: no profile, or an account D-1317 hides.
    if (!profile) throw new ApiError("not_found", "No such player.");
    if (profile.adult !== true && this.adults && (await this.adults.hidden([uid])).has(uid)) {
      throw new ApiError("not_found", "No such player.");
    }
    if (isPrivateProfile(profile)) return false;
    const visibility = mapOf(profile.visibility);
    return visibility.stats !== false && visibility.teams !== false;
  }

  /**
   * The history of [rawUid] as [caller] may see it. One request per caller
   * runs at a time on an instance (a second answers resource_exhausted),
   * and an answer is kept for a minute per (caller, player), so a block
   * placed in that minute shows from the next one.
   */
  async history(caller: Caller, rawUid: unknown): Promise<TeamHistory> {
    if (!validId(rawUid)) throw new ApiError("not_found", "No such player.");
    const key = `${caller.uid}:${rawUid}`;
    const hit = this.cache.get(key);
    if (hit && Date.now() - hit.at < cacheMs) return hit.value;
    if (hit) this.cache.delete(key);
    if (this.running.has(caller.uid)) {
      throw new ApiError("resource_exhausted", "Too many requests. Try again in a few minutes.");
    }
    this.running.add(caller.uid);
    try {
      const value = await this.build(caller, rawUid);
      this.cache.delete(key);
      this.cache.set(key, { at: Date.now(), value });
      if (this.cache.size > cacheMax) this.cache.delete(this.cache.keys().next().value!);
      return value;
    } finally {
      this.running.delete(caller.uid);
    }
  }

  private async build(caller: Caller, uid: string): Promise<TeamHistory> {
    const self = caller.uid === uid;
    if (!self) {
      // Blocked either way: the same as a player who shows nothing.
      if (await blockedBetween(this.store, caller.uid, uid)) return { teams: [] };
      if (!(await this.shownToOthers(uid))) return { teams: [] };
    }

    if (!this.queries.group) throw new ApiError("failed_precondition", "Team history isn't available here.");
    const found = await this.queries.group("roster", teamHistoryMaxSpots + 1, { userId: uid });
    const spots = found
      .map((s) => ({ ...s, parts: s.path.split("/") }))
      .filter((s) => s.parts.length === 4 && s.parts[0] === "teams" && s.parts[2] === "roster")
      .sort((a, b) => (a.path < b.path ? -1 : 1))
      .slice(0, teamHistoryMaxSpots);
    if (spots.length === 0) return { teams: [] };

    const teamIds = [...new Set(spots.map((s) => s.parts[1]!))];
    const docs = await this.store.getAll(teamIds.map((t) => `teams/${t}`));
    const teams = new Map(teamIds.map((t, i) => [t, docs[i]] as const));

    const shown: Array<{ teamId: string; team: Data; spotId: string; spot: Data }> = [];
    for (const s of spots) {
      const teamId = s.parts[1]!;
      const team = teams.get(teamId);
      // Communities and groups keep no roster; a deleted team has no name to show.
      if (!team || kindOf(team) !== "team") continue;
      if (!self && !isMember(team, caller.uid)) {
        // The public-roster rule: an adult team with its page on (a team with no level stays private).
        if (!rosterIsPublic(team) || isDraftedLeagueTeam(teamId)) continue;
        if (await this.roster.inYouthLeague(team, teamId)) continue;
      }
      shown.push({ teamId, team, spotId: s.parts[3]!, spot: s.data });
    }

    // Current teams first (the order they're shown in), one at a time, until
    // the request's game budget is spent. A team cut short, or never reached,
    // is partial.
    const nameOf = (t: string) => str(teams.get(t)!.name);
    const need = [...new Set(shown.map((s) => s.teamId))].sort(
      (a, b) =>
        Number(isMember(teams.get(b)!, uid)) - Number(isMember(teams.get(a)!, uid)) ||
        (nameOf(a) < nameOf(b) ? -1 : nameOf(a) > nameOf(b) ? 1 : 0) ||
        (a < b ? -1 : 1),
    );
    const totals = new Map<string, { sums: Map<string, Record<string, SeasonTotals>>; partial: boolean }>();
    let budget = teamHistoryGameBudget;
    for (const teamId of need) {
      const spotIds = shown.filter((s) => s.teamId === teamId).map((s) => s.spotId);
      const sums = new Map(spotIds.map((id) => [id, {} as Record<string, SeasonTotals>]));
      totals.set(teamId, { sums, partial: true });
      if (budget <= 0) continue;
      // Games counted for this team; one more says there are more.
      const limit = Math.min(teamHistoryMaxGames, budget);
      let read = 0;
      let after: string | undefined;
      let partial = false;
      for (;;) {
        const size = Math.min(gamePage, limit + 1 - read);
        const page = await this.queries.fields(`teams/${teamId}/statsGames`, ["date", "points"], size, undefined, after);
        read += page.length;
        partial = read > limit;
        if (page.length > 0) after = page[page.length - 1]!.id;
        const counted = partial ? page.slice(0, page.length - 1) : page;
        const games = counted.map((d) => ({ ...d.data, id: d.id }));
        for (const [id, more] of seasonTotalsForSpots(spotIds, games)) addSeasonTotals(sums.get(id)!, more);
        if (partial || page.length < size) break;
        await yieldLoop();
      }
      budget -= partial ? limit : read;
      totals.get(teamId)!.partial = partial;
      await yieldLoop();
    }

    const entries: TeamHistoryEntry[] = shown.map(({ teamId, team, spotId, spot }) => ({
      teamId,
      teamName: str(team.name),
      teamKind: "team",
      current: isMember(team, uid),
      spot: {
        id: spotId,
        name: str(spot.name),
        number: typeof spot.number === "number" && Number.isInteger(spot.number) ? spot.number : null,
      },
      seasons: totals.get(teamId)!.sums.get(spotId)!,
      ...(totals.get(teamId)!.partial && { partial: true }),
    }));
    return { teams: orderTeamHistory(entries) };
  }
}
