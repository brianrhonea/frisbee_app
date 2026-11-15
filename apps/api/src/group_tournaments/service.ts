// A community's own tournaments (teams/{groupId}/groupTournaments/{id},
// its games, and its public listing tournamentDirectory/{groupId}_{id}):
// ports of those rules in firebase/firestore.rules. Organizers
// (manageEvents, in a group) set tournaments up and publish schedules;
// captains report and confirm scores; anyone playing moves winners and
// losers on. Schedules, bracket moves and confirmed scores are worked out
// here with the app's engine (groupEngine), never taken from the body.
import {
  type GroupGame,
  type GroupSlotFill,
  type GroupTournamentStatus,
  GroupScheduleError,
  groupEngine,
  groupGameScoreRequestSchema,
  groupGameStages,
  readGroupGame,
  readGroupSettings,
  saveGroupTournamentRequestSchema,
} from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import type { z } from "zod";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { hubLimits } from "../hub/routes.js";
import { docIdParam } from "../ids.js";
import type { MemoryRateLimiter } from "../limits/memory.js";
import type { DocQueries } from "../queries.js";
import { type Data, type DocStore, serverTime, type Tx } from "../store.js";
import { can, isGroup, mapOf, own, strings } from "../teams/access.js";
import type { TeamRepository } from "../teams/repository.js";

const p = {
  team: (t: string) => `teams/${t}`,
  tournaments: (t: string) => `teams/${t}/groupTournaments`,
  tournament: (t: string, id: string) => `teams/${t}/groupTournaments/${id}`,
  games: (t: string, id: string) => `teams/${t}/groupTournaments/${id}/games`,
  game: (t: string, id: string, g: string) => `teams/${t}/groupTournaments/${id}/games/${g}`,
  listing: (t: string, id: string) => `tournamentDirectory/${t}_${id}`,
};

/** More games than any schedule makes (a 64-team round robin is 2,016). */
const maxGames = 5000;
/** The fields readGroupGame reads: games are listed with only these. */
const gameKeys = ["order", "stage", "round", "label", "pool", "field", "startsAt", "teamA", "teamB", "sourceA", "sourceB", "status", "scoreA", "scoreB", "report", "ifNeeded", "place"] as const;
/** Writes per transaction when a schedule is too big for one. */
const chunk = 400;

const noTeam = () => new ApiError("not_found", "That group doesn't exist.");
const noTournament = () => new ApiError("not_found", "That tournament doesn't exist.");
const noGame = () => new ApiError("not_found", "That game doesn't exist.");
const notOrganizer = () => new ApiError("permission_denied", "Only the group's organizers can run its tournaments.");
const notPlaying = () => new ApiError("permission_denied", "Only people playing in it can move teams on.");

/**
 * The listing rule's update conjuncts (resource.data.groupId and
 * tournamentId unchanged): a listing already at this id has to be this
 * tournament's. Ids join with "_", so group "a" with tournament "b_c" and
 * group "a_b" with tournament "c" would share one.
 */
function requireOwnListing(listing: Data | null, groupId: string, id: string) {
  if (listing && (listing.groupId !== groupId || listing.tournamentId !== id)) {
    throw new ApiError("failed_precondition", "This tournament's public listing belongs to another tournament.");
  }
}

type Draft = z.output<typeof saveGroupTournamentRequestSchema>;

/** can(team, 'manageEvents'), and for create and update isGroup(team). */
function requireOrganizer(team: Data | null, uid: string, group: boolean): Data {
  if (!team) throw noTeam();
  if (group && !isGroup(team)) throw new ApiError("failed_precondition", "Only groups and communities run tournaments.");
  if (!can(team, uid, "manageEvents")) throw notOrganizer();
  return team;
}

/**
 * GroupTournament.toMap for [d] (without createdBy/createdAt), checked
 * like validTournament: players must be members, captains among them.
 * Names come from the group's member list where it has them.
 */
function tournamentFields(team: Data, d: Draft, status: GroupTournamentStatus): Data {
  const members = new Set(strings(team.memberIds));
  const names = mapOf(team.memberNames);
  const teams = d.teams.map((t) => ({
    id: t.id,
    name: t.name,
    captainId: t.captainId,
    playerIds: t.playerIds,
    playerNames: Object.fromEntries(
      t.playerIds.map((u) => {
        const known = own(names, u);
        return [u, typeof known === "string" ? known : (Object.hasOwn(t.playerNames, u) ? t.playerNames[u]! : "Player")];
      }),
    ),
  }));
  const participantIds = teams.flatMap((t) => t.playerIds);
  // participantIds.toSet().difference(team().memberIds.toSet()).size() == 0
  const outsider = participantIds.find((u) => !members.has(u));
  if (outsider) throw new ApiError("failed_precondition", "Everyone on a team has to be in the group.");
  const captains = Object.fromEntries(teams.flatMap((t) => (t.captainId ? [[t.id, t.captainId]] : [])));
  const s = d.settings;
  return {
    name: d.name,
    eventId: d.eventId,
    settings: {
      format: s.format,
      playersOnField: s.playersOnField,
      poolCount: s.poolCount,
      gameMinutes: s.gameMinutes,
      breakMinutes: s.breakMinutes,
      scoreCap: s.scoreCap,
      timeoutsPerHalf: s.timeoutsPerHalf,
      fields: s.fields,
      startsAt: new Date(s.startsAt),
      idealEndsAt: s.idealEndsAt ? new Date(s.idealEndsAt) : null,
      laterDays: s.laterDays.map((x) => new Date(x)),
      scoring: s.scoring,
    },
    status,
    teams,
    participantIds,
    captains,
  };
}

/** TournamentListing.of(group, tournament).toMap (validTournamentListing). */
function listingFields(groupId: string, id: string, d: Draft, status: GroupTournamentStatus): Data {
  const last = d.settings.laterDays.at(-1);
  return {
    groupId,
    tournamentId: id,
    name: d.name,
    startsAt: new Date(d.settings.startsAt),
    endsOn: last ? new Date(last) : null,
    status,
    format: d.settings.format,
  };
}

/** GroupGame.toMap, checked like validGame. */
function gameFields(g: GroupGame): Data {
  const done = g.status === "done";
  const score = (n: number | null) => n !== null && Number.isInteger(n) && n >= 0 && n <= 99;
  if (
    !groupGameStages.includes(g.stage) ||
    g.label.length > 60 ||
    (g.place != null && !(Number.isInteger(g.place) && g.place >= 1 && g.place <= 64)) ||
    (done && !(score(g.scoreA) && score(g.scoreB) && g.scoreA !== g.scoreB))
  ) {
    throw new ApiError("internal", "That game isn't valid.");
  }
  return {
    order: g.order,
    stage: g.stage,
    round: g.round,
    label: g.label,
    pool: g.pool,
    field: g.field,
    startsAt: g.startsAt ? new Date(g.startsAt) : null,
    teamA: g.teamA,
    teamB: g.teamB,
    sourceA: g.sourceA,
    sourceB: g.sourceB,
    status: g.status,
    scoreA: g.scoreA,
    scoreB: g.scoreB,
    report: g.report,
    ifNeeded: g.ifNeeded,
    ...(g.place != null && { place: g.place }),
  };
}

const teamIdsOf = (raw: unknown) =>
  (Array.isArray(raw) ? raw : []).map((t) => String(mapOf(t).id ?? "")).sort().join("\n");

export class GroupTournamentService {
  constructor(
    private readonly store: DocStore,
    private readonly teams: Pick<TeamRepository, "deleteTree">,
    private readonly queries: DocQueries,
  ) {}

  /** The tournament's games, with only the fields the engine reads. */
  private async games(teamId: string, id: string): Promise<GroupGame[]> {
    const list = await this.queries.fields(p.games(teamId, id), gameKeys, maxGames);
    return list.map((g) => readGroupGame(g.id, g.data)).sort((a, b) => a.order - b.order);
  }

  /**
   * Writes the fills [compute] makes, read again inside [tx]: the games
   * they fill and the games those wait on are fetched fresh, the fills
   * worked out again, and (unless [overwrite]) only empty slots are filled.
   * Every read happens before [then] writes anything.
   */
  private async fill(
    tx: Tx,
    teamId: string,
    id: string,
    listed: GroupGame[],
    compute: (games: GroupGame[]) => GroupSlotFill[],
    overwrite: boolean,
  ): Promise<() => void> {
    const first = compute(listed);
    const byId = new Map(listed.map((g) => [g.id, g]));
    const ids = new Set<string>();
    for (const f of first) {
      ids.add(f.gameId);
      const g = byId.get(f.gameId);
      for (const s of [g?.sourceA, g?.sourceB]) if (s && s.type !== "pool") ids.add(s.game);
    }
    const fresh = await Promise.all([...ids].map(async (gid) => [gid, await tx.get(p.game(teamId, id, docIdParam(gid)))] as const));
    for (const [gid, data] of fresh) {
      if (data) byId.set(gid, readGroupGame(gid, data));
      else byId.delete(gid);
    }
    const fills = compute([...byId.values()].sort((a, b) => a.order - b.order)).filter((f) => ids.has(f.gameId) && byId.has(f.gameId));
    return () => {
      for (const f of fills) {
        const g = byId.get(f.gameId)!;
        if (g.status === "done") continue;
        const update: Data = {};
        if (f.teamA !== null && (overwrite || g.teamA === null)) update.teamA = f.teamA;
        if (f.teamB !== null && (overwrite || g.teamB === null)) update.teamB = f.teamB;
        if (Object.keys(update).length) tx.update(p.game(teamId, id, f.gameId), update);
      }
    };
  }

  /**
   * confirm()'s checks on [g]: a report to confirm, by the other team's
   * captain, for the score they saw, and advance()'s uid() in
   * participantIds for the games it fills. Answers the report.
   */
  private confirmable(t: Data, g: GroupGame, uid: string, s: { scoreA: number; scoreB: number }) {
    const r = g.report;
    if (g.status !== "reported" || !r) throw new ApiError("failed_precondition", "There's no score to confirm.");
    const other = r.byTeam === g.teamA ? g.teamB : g.teamA;
    if (other === null || own(mapOf(t.captains), other) !== uid) {
      throw new ApiError("permission_denied", "Only the other team's captain confirms a score.");
    }
    if (r.scoreA !== s.scoreA || r.scoreB !== s.scoreB) throw new ApiError("failed_precondition", "The reported score changed. Check it again.");
    if (!strings(t.participantIds).includes(uid)) throw notPlaying();
    return r;
  }

  async create(caller: Caller, rawTeam: unknown, body: unknown): Promise<{ id: string }> {
    const teamId = docIdParam(rawTeam);
    const d = parseBody(saveGroupTournamentRequestSchema, body);
    requireOrganizer(await this.store.get(p.team(teamId)), caller.uid, true);
    const id = this.store.newId(p.tournaments(teamId));
    await this.store.transact(async (tx) => {
      const [t, listing] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.listing(teamId, id))]);
      const team = requireOrganizer(t, caller.uid, true);
      requireOwnListing(listing, teamId, id);
      tx.create(p.tournament(teamId, id), { ...tournamentFields(team, d, "setup"), createdBy: caller.uid, createdAt: serverTime });
      tx.set(p.listing(teamId, id), listingFields(teamId, id, d, "setup"));
    });
    return { id };
  }

  /** Name, settings and teams. After publishing, the teams can't be added or removed without publishing again. */
  async save(caller: Caller, rawTeam: unknown, rawId: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    const d = parseBody(saveGroupTournamentRequestSchema, body);
    await this.store.transact(async (tx) => {
      const [t, existing, listing] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.tournament(teamId, id)), tx.get(p.listing(teamId, id))]);
      const team = requireOrganizer(t, caller.uid, true);
      if (!existing) throw noTournament();
      requireOwnListing(listing, teamId, id);
      const published = existing.status !== "setup";
      if (published && teamIdsOf(existing.teams) !== d.teams.map((x) => x.id).sort().join("\n")) {
        throw new ApiError("failed_precondition", "The number of teams changed: publish the schedule again.");
      }
      // A published one keeps its status: saving a finished one doesn't reopen it.
      const status = !published ? "setup" : existing.status === "done" ? "done" : "scheduled";
      tx.update(p.tournament(teamId, id), tournamentFields(team, d, status));
      tx.set(p.listing(teamId, id), listingFields(teamId, id, d, status));
    });
  }

  /** Saves [body], then replaces every game with a new schedule and marks it scheduled. */
  async publish(caller: Caller, rawTeam: unknown, rawId: unknown, body: unknown): Promise<{ games: number }> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    const d = parseBody(saveGroupTournamentRequestSchema, body);
    // Checked before the schedule is worked out or any game is replaced
    // (the biggest schedules take several transactions).
    const [team, tour, listing] = await Promise.all([this.store.get(p.team(teamId)), this.store.get(p.tournament(teamId, id)), this.store.get(p.listing(teamId, id))]);
    tournamentFields(requireOrganizer(team, caller.uid, true), d, "scheduled");
    if (!tour) throw noTournament();
    requireOwnListing(listing, teamId, id);
    let plan;
    try {
      plan = groupEngine.scheduleFor(
        d.teams.map((t) => t.id),
        readGroupSettings(d.settings),
      );
    } catch (e) {
      if (e instanceof GroupScheduleError) throw new ApiError("failed_precondition", e.message);
      throw e;
    }
    const fresh = new Set(plan.games.map((g) => g.id));
    const old = (await this.queries.ids(p.games(teamId, id), maxGames)).filter((g) => !fresh.has(g));
    const writes: Array<(tx: Tx) => void> = [
      ...old.map((g) => (tx: Tx) => tx.delete(p.game(teamId, id, docIdParam(g)))),
      ...plan.games.map((g) => {
        const fields = gameFields(g);
        return (tx: Tx) => tx.set(p.game(teamId, id, g.id), fields);
      }),
    ];
    // One transaction for any usual schedule; the biggest go in chunks
    // like the app's batches, the tournament update riding in the last.
    for (let i = 0; i < writes.length || i === 0; i += chunk) {
      const last = i + chunk >= writes.length;
      await this.store.transact(async (tx) => {
        const [t, existing, listing] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.tournament(teamId, id)), tx.get(p.listing(teamId, id))]);
        const team = requireOrganizer(t, caller.uid, true);
        if (!existing) throw noTournament();
        requireOwnListing(listing, teamId, id);
        const fields = last ? tournamentFields(team, d, "scheduled") : null;
        for (const w of writes.slice(i, i + chunk)) w(tx);
        if (fields) {
          tx.update(p.tournament(teamId, id), fields);
          tx.set(p.listing(teamId, id), listingFields(teamId, id, d, "scheduled"));
        }
      });
    }
    return { games: plan.games.length };
  }

  /** The tournament, its games and its listing. */
  async remove(caller: Caller, rawTeam: unknown, rawId: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    const exists = await this.store.transact(async (tx) => {
      const [t, existing, listing] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.tournament(teamId, id)), tx.get(p.listing(teamId, id))]);
      const team = requireOrganizer(t, caller.uid, false);
      // The listing's delete rule: organizes(resource.data.groupId), which
      // needs a group. Only this tournament's own listing goes with it.
      if (existing && listing && isGroup(team) && listing.groupId === teamId && listing.tournamentId === id) tx.delete(p.listing(teamId, id));
      return existing !== null;
    });
    if (exists) await this.teams.deleteTree(p.tournament(teamId, id));
  }

  /** A captain of either team files a score (report()). Re-filing replaces the other captain's report. */
  async report(caller: Caller, rawTeam: unknown, rawId: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    const gameId = docIdParam(rawGame);
    const s = parseBody(groupGameScoreRequestSchema, body);
    await this.store.transact(async (tx) => {
      const [t, gd] = await Promise.all([tx.get(p.tournament(teamId, id)), tx.get(p.game(teamId, id, gameId))]);
      if (!t) throw noTournament();
      if (!gd) throw noGame();
      const g = readGroupGame(gameId, gd);
      if (g.teamA === null || g.teamB === null) throw new ApiError("failed_precondition", "Teams are decided by earlier games.");
      if (g.status === "done") throw new ApiError("failed_precondition", "That game is already final.");
      const captains = mapOf(t.captains);
      const captainOf = (team: string) => own(captains, team) === caller.uid;
      const byTeam = captainOf(g.teamA) ? g.teamA : captainOf(g.teamB) ? g.teamB : null;
      if (byTeam === null) throw new ApiError("permission_denied", "Only team captains report scores.");
      tx.update(p.game(teamId, id, gameId), { report: { scoreA: s.scoreA, scoreB: s.scoreB, byTeam }, status: "reported" });
    });
  }

  /**
   * The other captain accepts the report (confirm()): the game is final,
   * and the teams move on in the same write. [body] is the score being
   * confirmed, so a report changed meanwhile isn't confirmed by mistake.
   */
  async confirm(caller: Caller, rawTeam: unknown, rawId: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    const gameId = docIdParam(rawGame);
    const s = parseBody(groupGameScoreRequestSchema, body);
    // Only the other captain gets as far as listing the games.
    const [tour, game] = await Promise.all([this.store.get(p.tournament(teamId, id)), this.store.get(p.game(teamId, id, gameId))]);
    if (!tour) throw noTournament();
    if (!game) throw noGame();
    this.confirmable(tour, readGroupGame(gameId, game), caller.uid, s);
    const listed = await this.games(teamId, id);
    await this.store.transact(async (tx) => {
      const [t, gd] = await Promise.all([tx.get(p.tournament(teamId, id)), tx.get(p.game(teamId, id, gameId))]);
      if (!t) throw noTournament();
      if (!gd) throw noGame();
      const g = readGroupGame(gameId, gd);
      const r = this.confirmable(t, g, caller.uid, s);
      const done: GroupGame = { ...g, status: "done", scoreA: r.scoreA, scoreB: r.scoreB, report: null };
      const list = listed.map((x) => (x.id === gameId ? done : x));
      // advance(): the confirming captain plays in it (captains are participants).
      const write = await this.fill(tx, teamId, id, list, (games) => groupEngine.fillsAfter(done, games), false);
      tx.update(p.game(teamId, id, gameId), { status: "done", scoreA: r.scoreA, scoreB: r.scoreB, report: null });
      write();
    });
  }

  /** An organizer sets (or corrects) the final score, unless later games already depend on it. */
  async setScore(caller: Caller, rawTeam: unknown, rawId: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    const gameId = docIdParam(rawGame);
    const s = parseBody(groupGameScoreRequestSchema, body);
    requireOrganizer(await this.store.get(p.team(teamId)), caller.uid, false);
    if (!(await this.store.get(p.tournament(teamId, id)))) throw noTournament();
    const listed = await this.games(teamId, id);
    await this.store.transact(async (tx) => {
      const [t, tour, gd] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.tournament(teamId, id)), tx.get(p.game(teamId, id, gameId))]);
      requireOrganizer(t, caller.uid, false);
      if (!tour) throw noTournament();
      if (!gd) throw noGame();
      const g = readGroupGame(gameId, gd);
      if (g.teamA === null || g.teamB === null) throw new ApiError("failed_precondition", "Teams are decided by earlier games.");
      const list = listed.map((x) => (x.id === gameId ? g : x));
      if (groupEngine.laterGamesPlayed(g, list)) throw new ApiError("failed_precondition", "Later games already depend on this result.");
      const done: GroupGame = { ...g, status: "done", scoreA: s.scoreA, scoreB: s.scoreB, report: null };
      const write = await this.fill(
        tx,
        teamId,
        id,
        list.map((x) => (x.id === gameId ? done : x)),
        (games) => groupEngine.fillsAfter(done, games, true),
        true,
      );
      tx.update(p.game(teamId, id, gameId), gameFields(done));
      write();
    });
  }

  /** Organizers seed the bracket from pool standings once every pool game is final. */
  async seedBracket(caller: Caller, rawTeam: unknown, rawId: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    requireOrganizer(await this.store.get(p.team(teamId)), caller.uid, false);
    if (!(await this.store.get(p.tournament(teamId, id)))) throw noTournament();
    const listed = await this.games(teamId, id);
    if (groupEngine.bracketSeeds(listed).length === 0) throw new ApiError("failed_precondition", "The pools aren't done yet.");
    await this.store.transact(async (tx) => {
      const [t, tour] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.tournament(teamId, id))]);
      requireOrganizer(t, caller.uid, false);
      if (!tour) throw noTournament();
      // The seeds depend on every pool game: read them all again.
      const pools = listed.filter((g) => g.stage === "pool");
      const fresh = await Promise.all(pools.map((g) => tx.get(p.game(teamId, id, docIdParam(g.id)))));
      const list = listed.map((g) => {
        const i = pools.findIndex((x) => x.id === g.id);
        return i < 0 ? g : fresh[i] ? readGroupGame(g.id, fresh[i]!) : g;
      });
      const write = await this.fill(tx, teamId, id, list, groupEngine.bracketSeeds, false);
      write();
    });
  }

  /**
   * Moves teams on where a finished game's bracket update didn't land
   * (advance()): anyone playing, or an organizer. Returns how many games
   * got a team.
   */
  async advance(caller: Caller, rawTeam: unknown, rawId: unknown): Promise<{ filled: number }> {
    const teamId = docIdParam(rawTeam);
    const id = docIdParam(rawId);
    const allowed = async (get: (path: string) => Promise<Data | null>) => {
      const [t, tour] = await Promise.all([get(p.team(teamId)), get(p.tournament(teamId, id))]);
      if (!tour) throw noTournament();
      const organizer = !!t && can(t, caller.uid, "manageEvents");
      if (!organizer && !strings(tour.participantIds).includes(caller.uid)) throw notPlaying();
    };
    // Someone not playing is refused before the games are listed.
    await allowed((path) => this.store.get(path));
    const listed = await this.games(teamId, id);
    if (groupEngine.pendingFills(listed).length === 0) return { filled: 0 };
    let filled = 0;
    await this.store.transact(async (tx) => {
      await allowed((path) => tx.get(path));
      const write = await this.fill(
        tx,
        teamId,
        id,
        listed,
        (games) => {
          const f = groupEngine.pendingFills(games);
          filled = f.length;
          return f;
        },
        false,
      );
      write();
    });
    return { filled };
  }
}

/** Big enough for 64 teams and 1,000 players (the app's limits). */
const draftBodyLimit = 512 * 1024;

export function groupTournamentRoutes(app: FastifyInstance, svc: GroupTournamentService, limiter: MemoryRateLimiter) {
  const caller = (req: FastifyRequest): Caller => {
    const c = requireCaller(req);
    if (!limiter.admit(`write:${c.uid}`, hubLimits.write)) {
      throw new ApiError("resource_exhausted", "You're doing that too fast. Wait a minute and try again.");
    }
    return c;
  };
  const base = "/v1/teams/:teamId/group-tournaments";
  type T = { Params: { teamId: string } };
  type I = { Params: { teamId: string; tournamentId: string } };
  type G = { Params: { teamId: string; tournamentId: string; gameId: string } };
  const big = { bodyLimit: draftBodyLimit };
  app.post<T>(base, big, async (req, reply) => reply.code(201).send(await svc.create(caller(req), req.params.teamId, req.body)));
  app.put<I>(`${base}/:tournamentId`, big, async (req, reply) => {
    await svc.save(caller(req), req.params.teamId, req.params.tournamentId, req.body);
    return reply.code(204).send();
  });
  app.post<I>(`${base}/:tournamentId/schedule`, big, async (req) => svc.publish(caller(req), req.params.teamId, req.params.tournamentId, req.body));
  app.delete<I>(`${base}/:tournamentId`, async (req, reply) => {
    await svc.remove(caller(req), req.params.teamId, req.params.tournamentId);
    return reply.code(204).send();
  });
  app.post<I>(`${base}/:tournamentId/seed-bracket`, async (req, reply) => {
    await svc.seedBracket(caller(req), req.params.teamId, req.params.tournamentId);
    return reply.code(204).send();
  });
  app.post<I>(`${base}/:tournamentId/advance`, async (req) => svc.advance(caller(req), req.params.teamId, req.params.tournamentId));
  app.post<G>(`${base}/:tournamentId/games/:gameId/report`, async (req, reply) => {
    await svc.report(caller(req), req.params.teamId, req.params.tournamentId, req.params.gameId, req.body);
    return reply.code(204).send();
  });
  app.post<G>(`${base}/:tournamentId/games/:gameId/confirm`, async (req, reply) => {
    await svc.confirm(caller(req), req.params.teamId, req.params.tournamentId, req.params.gameId, req.body);
    return reply.code(204).send();
  });
  app.put<G>(`${base}/:tournamentId/games/:gameId/score`, async (req, reply) => {
    await svc.setScore(caller(req), req.params.teamId, req.params.tournamentId, req.params.gameId, req.body);
    return reply.code(204).send();
  });
}
