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
  isYouthTeam,
  orderTeamHistory,
  publicPageOn,
  seasonTotalsFor,
  type TeamHistory,
  type TeamHistoryEntry,
  teamHistoryMaxGames,
  teamHistoryMaxSpots,
} from "@stall10/shared";
import type { AdultVisibility } from "../account/adult_visibility.js";
import { type Caller } from "../auth.js";
import { isPrivateProfile, validId } from "../browse/model.js";
import { isDraftedLeagueTeam } from "../browse/visibility.js";
import { ApiError } from "../errors.js";
import type { DocQueries } from "../queries.js";
import type { Data, DocStore } from "../store.js";
import { isMember, kindOf, mapOf } from "./access.js";
import type { RosterService } from "./roster.js";

/** Teams whose games are read at once. */
const gameReads = 5;

const str = (v: unknown) => (typeof v === "string" ? v : "");

export class TeamHistoryService {
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

  async history(caller: Caller, rawUid: unknown): Promise<TeamHistory> {
    if (!validId(rawUid)) throw new ApiError("not_found", "No such player.");
    const uid = rawUid;
    const self = caller.uid === uid;
    if (!self && !(await this.shownToOthers(uid))) return { teams: [] };

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
        if (isYouthTeam(team) || !publicPageOn(team) || isDraftedLeagueTeam(teamId)) continue;
        if (await this.roster.inYouthLeague(team, teamId)) continue;
      }
      shown.push({ teamId, team, spotId: s.parts[3]!, spot: s.data });
    }

    const games = new Map<string, Data[]>();
    const need = [...new Set(shown.map((s) => s.teamId))];
    for (let i = 0; i < need.length; i += gameReads) {
      await Promise.all(
        need.slice(i, i + gameReads).map(async (teamId) => {
          const docs = await this.queries.fields(`teams/${teamId}/statsGames`, ["date", "points"], teamHistoryMaxGames);
          games.set(
            teamId,
            docs.map((d) => ({ ...d.data, id: d.id })),
          );
        }),
      );
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
      seasons: seasonTotalsFor(spotId, games.get(teamId) ?? []),
    }));
    return { teams: orderTeamHistory(entries) };
  }
}
