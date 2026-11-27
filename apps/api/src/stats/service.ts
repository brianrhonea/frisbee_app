// Team stats and roster spots: the statsGames, statsTournaments, roster and
// rosterStatus rules in firebase/firestore.rules, ported. Games and
// tournaments are saved whole (StatsGame.toMap / StatsTournament.toMap),
// by owners, coaches, captains and members with stats access
// (canKeepStats); roster spots by admins who manage the team, and a member
// may claim an unlinked spot for themselves or let go of their own. The
// Admin SDK skips the rules, so every conjunct is checked here.
import {
  linkRosterPlayerSchema,
  rosterLineOf,
  type SaveStatsGameInput,
  type SaveStatsTournamentInput,
  saveRosterPlayerSchema,
  saveStatsGameSchema,
  saveStatsTournamentSchema,
} from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { DocQueries } from "../queries.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, isMember, own, roleIn, strings } from "../teams/access.js";

/** canKeepStats(team) in the rules. */
export function canKeepStats(t: Data, uid: string): boolean {
  return can(t, uid, "keepStats") || roleIn(t, uid) === "stats" || (isMember(t, uid) && strings(t.statKeepers).includes(uid));
}

/** Deletes per transaction (Firestore allows 500 writes). */
const deleteChunk = 400;

const paths = {
  team: (t: string) => `teams/${t}`,
  games: (t: string) => `teams/${t}/statsGames`,
  game: (t: string, g: string) => `teams/${t}/statsGames/${g}`,
  tournament: (t: string, id: string) => `teams/${t}/statsTournaments/${id}`,
  player: (t: string, p: string) => `teams/${t}/roster/${p}`,
  status: (t: string, p: string) => `teams/${t}/rosterStatus/${p}`,
};

const noTeam = () => new ApiError("not_found", "That team doesn't exist.");
const noStats = () => new ApiError("permission_denied", "Only the team's stats keepers can change stats.");
const noRoster = () => new ApiError("permission_denied", "Only the team's admins can change the roster.");

/** The game as stored (StatsGame.toMap), with the date as a Date (a Firestore timestamp). */
function gameFields(g: SaveStatsGameInput): Data {
  return {
    opponent: g.opponent,
    date: new Date(g.date),
    gameTo: g.gameTo,
    tournamentId: g.tournamentId,
    eventId: g.eventId,
    points: g.points.map((p) => ({ line: p.line, startedOn: p.startedOn, actions: p.actions.map((a) => ({ ...a })), result: p.result })),
    finished: g.finished,
    lines: g.lines.map((l) => ({ id: l.id, name: l.name, players: l.players, side: l.side })),
    timeoutsPerHalf: g.timeoutsPerHalf,
    timeouts: g.timeouts.map((t) => ({ ours: t.ours, half: t.half, point: t.point, action: t.action })),
    updatedAt: serverTime,
  };
}

function tournamentFields(t: SaveStatsTournamentInput): Data {
  return {
    name: t.name,
    startDate: new Date(t.startDate),
    location: t.location,
    eventId: t.eventId,
    roster: t.roster,
    lines: t.lines.map((l) => ({ id: l.id, name: l.name, players: l.players, side: l.side })),
    updatedAt: serverTime,
  };
}

export class StatsService {
  constructor(
    private readonly store: DocStore,
    private readonly queries: DocQueries,
  ) {}

  /** The team, read in [tx], if the caller keeps its stats. */
  private async keeper(get: (path: string) => Promise<Data | null>, teamId: string, uid: string) {
    const team = await get(paths.team(teamId));
    if (!team) throw noTeam();
    if (!canKeepStats(team, uid)) throw noStats();
    return team;
  }

  // ---- Games ---------------------------------------------------------------

  async createGame(caller: Caller, rawTeam: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const game = parseBody(saveStatsGameSchema, body);
    const id = this.store.newId(paths.games(teamId));
    await this.store.transact(async (tx) => {
      await this.keeper((p) => tx.get(p), teamId, caller.uid);
      tx.create(paths.game(teamId, id), gameFields(game));
    });
    return { id };
  }

  async saveGame(caller: Caller, rawTeam: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawGame);
    const game = parseBody(saveStatsGameSchema, body);
    await this.store.transact(async (tx) => {
      await this.keeper((p) => tx.get(p), teamId, caller.uid);
      if (!(await tx.get(paths.game(teamId, id)))) throw new ApiError("not_found", "That game was deleted.");
      tx.set(paths.game(teamId, id), gameFields(game));
    });
  }

  async deleteGame(caller: Caller, rawTeam: unknown, rawGame: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawGame);
    await this.store.transact(async (tx) => {
      await this.keeper((p) => tx.get(p), teamId, caller.uid);
      tx.delete(paths.game(teamId, id));
    });
  }

  // ---- Tournaments -----------------------------------------------------------

  async createTournament(caller: Caller, rawTeam: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const t = parseBody(saveStatsTournamentSchema, body);
    const id = this.store.newId(`teams/${teamId}/statsTournaments`);
    await this.store.transact(async (tx) => {
      await this.keeper((p) => tx.get(p), teamId, caller.uid);
      tx.create(paths.tournament(teamId, id), tournamentFields(t));
    });
    return { id };
  }

  async saveTournament(caller: Caller, rawTeam: unknown, rawId: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    const t = parseBody(saveStatsTournamentSchema, body);
    await this.store.transact(async (tx) => {
      await this.keeper((p) => tx.get(p), teamId, caller.uid);
      if (!(await tx.get(paths.tournament(teamId, id)))) throw new ApiError("not_found", "That tournament was deleted.");
      tx.set(paths.tournament(teamId, id), tournamentFields(t));
    });
  }

  /**
   * Deletes a tournament and every game in it (deleteTournament in the
   * app): the games first, a chunk per transaction, then the tournament,
   * so a failure part way leaves the folder to try again.
   */
  async deleteTournament(caller: Caller, rawTeam: unknown, rawId: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    await this.keeper((p) => this.store.get(p), teamId, caller.uid);
    // Never leave games behind that would still count in season totals:
    // a page of the tournament's game ids at a time, until none are left.
    for (;;) {
      const games = (await this.queries.ids(paths.games(teamId), deleteChunk, { tournamentId: id })).map((g) => docIdParam(g));
      if (games.length === 0) break;
      await this.store.transact(async (tx) => {
        await this.keeper((p) => tx.get(p), teamId, caller.uid);
        for (const g of games) tx.delete(paths.game(teamId, g));
      });
    }
    await this.store.transact(async (tx) => {
      await this.keeper((p) => tx.get(p), teamId, caller.uid);
      tx.delete(paths.tournament(teamId, id));
    });
  }

  // ---- Roster spots ------------------------------------------------------------

  /**
   * Creates (no [rawPlayer]) or replaces a spot, and its paid mark when
   * given (savePlayer). validLink: no link, a member, or the link it
   * already had (someone who left).
   */
  async savePlayer(caller: Caller, rawTeam: unknown, rawPlayer: unknown | undefined, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const creating = rawPlayer === undefined;
    const p = parseBody(saveRosterPlayerSchema, body);
    // A client-chosen id makes a replay a 409 (tx.create below); an edit can't name a different one.
    const id = creating ? (p.id ?? this.store.newId(`teams/${teamId}/roster`)) : docIdParam(rawPlayer);
    if (!creating && p.id !== undefined && p.id !== id) throw new ApiError("invalid_argument", "A spot's id can't be changed.");
    await this.store.transact(async (tx) => {
      const team = await tx.get(paths.team(teamId));
      const existing = await tx.get(paths.player(teamId, id));
      if (!team) throw noTeam();
      if (!can(team, caller.uid, "manageTeam")) throw noRoster();
      if (!creating && !existing) throw new ApiError("not_found", "That player was removed.");
      const kept = existing && typeof existing.userId === "string" ? existing.userId : null;
      if (p.userId !== null && !strings(team.memberIds).includes(p.userId) && p.userId !== kept) {
        throw new ApiError("invalid_argument", "Link the spot to someone on the team.");
      }
      const fields: Data = { name: p.name, number: p.number, position: p.position, userId: p.userId };
      // Its line is set apart (PUT .../roster-lines); editing keeps it.
      const line = rosterLineOf(existing?.line);
      if (line) fields.line = line;
      if (creating) tx.create(paths.player(teamId, id), fields);
      else tx.set(paths.player(teamId, id), fields);
      if (p.paid !== undefined) tx.set(paths.status(teamId, id), { paid: p.paid });
    });
    return { id };
  }

  async deletePlayer(caller: Caller, rawTeam: unknown, rawPlayer: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawPlayer);
    await this.store.transact(async (tx) => {
      const team = await tx.get(paths.team(teamId));
      if (!team) throw noTeam();
      if (!can(team, caller.uid, "manageTeam")) throw noRoster();
      tx.delete(paths.player(teamId, id));
      tx.delete(paths.status(teamId, id));
    });
  }

  /**
   * Links a spot to an account or unlinks it (linkPlayer). Admins may link
   * any member or unlink anyone (the first update rule); any member may
   * claim an unlinked spot for themselves or let go of their own (the
   * second), changing nothing else.
   */
  async linkPlayer(caller: Caller, rawTeam: unknown, rawPlayer: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawPlayer);
    const { userId } = parseBody(linkRosterPlayerSchema, body);
    await this.store.transact(async (tx) => {
      const team = await tx.get(paths.team(teamId));
      const spot = await tx.get(paths.player(teamId, id));
      if (!team) throw noTeam();
      if (!isMember(team, caller.uid)) throw new ApiError("permission_denied", "Only the team's members can claim a spot.");
      if (!spot) throw new ApiError("not_found", "That player was removed.");
      const was = typeof spot.userId === "string" ? spot.userId : null;
      const admin = can(team, caller.uid, "manageTeam") && adminSpotValid(spot) && (userId === null || strings(team.memberIds).includes(userId) || userId === was);
      const self = (was === null && userId === caller.uid) || (was === caller.uid && userId === null);
      if (!admin && !self) {
        const manager = can(team, caller.uid, "manageTeam");
        const message =
          was !== null && was !== caller.uid && !manager
            ? "This spot is linked to someone else."
            : manager
              ? "Only one of the team's members can be linked to a spot."
              : was === caller.uid
                ? "You can only unlink yourself from your spot."
                : "You can only claim a spot for yourself.";
        throw new ApiError("permission_denied", message);
      }
      tx.update(paths.player(teamId, id), { userId });
    });
  }
}

/**
 * The first update rule checks the whole spot after the change, so an
 * admin's link only goes through on a spot that already passes it.
 */
function adminSpotValid(d: Data): boolean {
  const keys = Object.keys(d);
  const allowed = ["name", "number", "position", "userId", "line"];
  return (
    keys.every((k) => allowed.includes(k)) &&
    typeof d.name === "string" &&
    d.name.length > 0 &&
    d.name.length <= 80 &&
    "number" in d &&
    (d.number === null || Number.isInteger(d.number)) &&
    ["handler", "cutter", "hybrid"].includes(own(d, "position") as string) &&
    (!("line" in d) || rosterLineOf(d.line) !== undefined)
  );
}
