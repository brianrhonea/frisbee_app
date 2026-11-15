// Players signing up as individuals and the teams made from them: ports of
// the signups and payments rules (rules.ts), the division write the app
// makes when it saves drafted teams, the captains' draft callables
// (firebase/functions/src/tournaments/draft.ts: startDraft, draftPick,
// draftControl, finishDraft) and createLeagueTeams (callables.ts), with
// the same checks in the same order and the same writes. The app keeps
// using the callables and its direct writes until it switches.
import {
  autoPick,
  available,
  type DraftedTeam,
  draftedTeams,
  draftedTeamsProblem,
  draftPickRequestSchema,
  draftControlRequestSchema,
  type DraftPick,
  leagueDirectoryDoc,
  leagueEntry,
  leagueProblem,
  leagueTeamChat,
  leagueTeamDoc,
  leagueTeamId,
  madeTeams,
  normalizedTeam,
  onTheClock,
  pickProblem,
  type PoolPlayer,
  saveDraftedTeamsRequestSchema,
  saveSignupRequestSchema,
  signupPaymentRequestSchema,
  signupStatusRequestSchema,
  startDraftRequestSchema,
  startProblem,
  teamsCreated,
  teamsFromDraft,
  withDrafted,
} from "@stall10/shared";
import type { z } from "zod";
import type { Caller } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import { type Data, type DocStore, serverTime, type Tx } from "../store.js";
import { can, mapOf, own, strings } from "../teams/access.js";
import type { DraftQueries } from "./repository.js";
import { paymentProblem, signupCreateProblem, signupUpdateProblem, validDivision } from "./rules.js";

function parse<S extends z.ZodType>(schema: S, body: unknown): z.output<S> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) throw fromZod(r.error);
  return r.data;
}

/** The callables' id check (idPattern in draft.ts and callables.ts). */
const idPattern = /^[A-Za-z0-9_-]{1,60}$/;
const clipName = (s: unknown): string => (typeof s === "string" ? s.trim().slice(0, 100) : "");

const p = {
  tournament: (t: string) => `tournaments/${t}`,
  division: (t: string, d: string) => `tournaments/${t}/divisions/${d}`,
  signup: (t: string, u: string) => `tournaments/${t}/signups/${u}`,
  payment: (t: string, u: string) => `tournaments/${t}/payments/${u}`,
  draft: (t: string, d: string) => `tournaments/${t}/drafts/${d}`,
  pool: (t: string, d: string) => `tournaments/${t}/drafts/${d}/details/pool`,
  entry: (t: string, team: string) => `tournaments/${t}/entries/${team}`,
  team: (id: string) => `teams/${id}`,
  user: (uid: string) => `users/${uid}`,
};

const fail = (m: string) => new ApiError("failed_precondition", m);
const organizersOnly = () => new ApiError("permission_denied", "Only the event's organizers can do that.");
const noEvent = () => new ApiError("not_found", "That event doesn't exist.");

/** A stored id fit for a document path, or null (a host id the callables would read as a missing team). */
function storedId(v: unknown): string | null {
  try {
    return docIdParam(v);
  } catch {
    return null;
  }
}

/** Fisher-Yates: every order equally likely. */
function shuffled<T>(list: readonly T[], random: () => number): T[] {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

interface Ctx {
  uid: string;
  tournamentId: string;
  divisionId: string;
  tournament: Data;
  division: Data;
  manager: boolean;
}

interface Loaded {
  draft: Data;
  captainIds: string[];
  picks: DraftPick[];
  pool: PoolPlayer[];
  everyone: Map<string, PoolPlayer>;
}

export class DraftService {
  constructor(
    private readonly store: DocStore,
    private readonly queries: DraftQueries,
    private readonly random: () => number = Math.random,
  ) {}

  /** manages(t): the caller can manage events on the tournament's host. */
  private async manages(read: (path: string) => Promise<Data | null>, tournament: Data, uid: string): Promise<{ manages: boolean; host: Data | null }> {
    const hostId = storedId(tournament.hostId);
    const host = hostId ? await read(p.team(hostId)) : null;
    return { manages: !!host && can(host, uid, "manageEvents"), host };
  }

  // ---- Signups -------------------------------------------------------------------

  /**
   * The caller signs up, edits their answers, or signs back up after
   * withdrawing (saveSignup in the app). Their name comes from their
   * account, never their email; their place is kept unless they withdrew.
   */
  async saveMySignup(caller: Caller, rawTournament: unknown, body: unknown): Promise<{ status: string }> {
    const tournamentId = docIdParam(rawTournament);
    const input = parse(saveSignupRequestSchema, body);
    const divisionId = docIdParam(input.divisionId);
    const profile = await this.store.get(p.user(caller.uid));
    const username = typeof profile?.username === "string" ? profile.username.trim() : "";
    const name = (caller.name?.trim() || username || "Player").slice(0, 100);
    return this.store.transact(async (tx) => {
      const tournament = await tx.get(p.tournament(tournamentId));
      if (!tournament) throw noEvent();
      const { manages } = await this.manages((x) => tx.get(x), tournament, caller.uid);
      const before = await tx.get(p.signup(tournamentId, caller.uid));
      const division = await tx.get(p.division(tournamentId, divisionId));
      const ctx = { uid: caller.uid, userId: caller.uid, tournament, manages };
      const fields = { name, divisionId, skill: input.skill, gender: input.gender };
      if (before) {
        const status = before.status !== "withdrawn" ? before.status : "applied";
        const next = { ...before, ...fields, status, updatedAt: serverTime };
        const problem = signupUpdateProblem(ctx, before, next);
        if (problem) throw problem;
        tx.update(p.signup(tournamentId, caller.uid), { ...fields, status, updatedAt: serverTime });
        return { status: String(status) };
      }
      const next = { ...fields, status: "applied", createdAt: serverTime, updatedAt: serverTime };
      const problem = signupCreateProblem(ctx, next, !!division);
      if (problem) throw problem;
      tx.create(p.signup(tournamentId, caller.uid), next);
      return { status: "applied" };
    });
  }

  /** The host accepts, waitlists or declines a signup, or the player withdraws (setSignupStatus). */
  async setSignupStatus(caller: Caller, rawTournament: unknown, rawUid: unknown, body: unknown): Promise<void> {
    const tournamentId = docIdParam(rawTournament);
    const userId = docIdParam(rawUid);
    const { status } = parse(signupStatusRequestSchema, body);
    await this.store.transact(async (tx) => {
      const tournament = await tx.get(p.tournament(tournamentId));
      if (!tournament) throw noEvent();
      const { manages } = await this.manages((x) => tx.get(x), tournament, caller.uid);
      const before = await tx.get(p.signup(tournamentId, userId));
      if (!before) throw new ApiError("not_found", "That signup doesn't exist.");
      const problem = signupUpdateProblem({ uid: caller.uid, userId, tournament, manages }, before, { ...before, status, updatedAt: serverTime });
      if (problem) throw problem;
      tx.update(p.signup(tournamentId, userId), { status, updatedAt: serverTime });
    });
  }

  /** The host marks a player's fee paid or unpaid, keeping their note (setPaid in the app). */
  async setSignupPayment(caller: Caller, rawTournament: unknown, rawUid: unknown, body: unknown): Promise<void> {
    const tournamentId = docIdParam(rawTournament);
    const userId = docIdParam(rawUid);
    const { paid } = parse(signupPaymentRequestSchema, body);
    await this.store.transact(async (tx) => {
      const tournament = await tx.get(p.tournament(tournamentId));
      if (!tournament) throw noEvent();
      const { manages } = await this.manages((x) => tx.get(x), tournament, caller.uid);
      const old = await tx.get(p.payment(tournamentId, userId));
      const doc = { paid, paidAt: paid ? serverTime : null, note: typeof old?.note === "string" ? old.note : "" };
      const problem = paymentProblem(manages, doc);
      if (problem) throw problem;
      tx.set(p.payment(tournamentId, userId), doc);
    });
  }

  // ---- Drafted teams (the balanced draft, and adjusting any draft) ---------------------

  /**
   * Saves the division's drafted teams, their seeds and captains in one
   * write (saveDraftTeams in the app): the division rule, plus the checks
   * the app makes before saving.
   */
  async saveDraftedTeams(caller: Caller, rawTournament: unknown, rawDivision: unknown, body: unknown): Promise<void> {
    const tournamentId = docIdParam(rawTournament);
    const divisionId = docIdParam(rawDivision);
    const input = parse(saveDraftedTeamsRequestSchema, body);
    const locked = await this.queries.hasGames(tournamentId, divisionId);
    await this.store.transact(async (tx) => {
      const tournament = await tx.get(p.tournament(tournamentId));
      if (!tournament) throw noEvent();
      const division = await tx.get(p.division(tournamentId, divisionId));
      if (!division) throw new ApiError("not_found", "That division doesn't exist.");
      const { manages } = await this.manages((x) => tx.get(x), tournament, caller.uid);
      if (!manages) throw organizersOnly();
      const problem = draftedTeamsProblem({ division, teams: input.teams, locked });
      if (problem) throw fail(problem);
      const teams = input.teams.map(normalizedTeam);
      const before = draftedTeams(division.teams).map((t) => t.id);
      const merged = withDrafted(division, before, teams);
      const invalid = validDivision({ ...division, teams, ...merged });
      if (invalid) throw invalid;
      tx.update(p.division(tournamentId, divisionId), { teams, seeds: merged.seeds, captains: merged.captains });
    });
  }

  // ---- The captains' draft -----------------------------------------------------------

  /** Signed in, and a real captains' draft in a real division (context in draft.ts). */
  private async context(caller: Caller, rawTournament: unknown, rawDivision: unknown): Promise<Ctx> {
    if (typeof rawTournament !== "string" || !idPattern.test(rawTournament)) throw new ApiError("invalid_argument", "Pick an event.");
    if (typeof rawDivision !== "string" || !idPattern.test(rawDivision)) throw new ApiError("invalid_argument", "Pick a division.");
    const tournamentId = docIdParam(rawTournament);
    const divisionId = docIdParam(rawDivision);
    const [tournament, division] = await Promise.all([this.store.get(p.tournament(tournamentId)), this.store.get(p.division(tournamentId, divisionId))]);
    if (!tournament || !division) throw new ApiError("not_found", "That event or division doesn't exist.");
    if (tournament.entryType !== "players" || tournament.draftMode !== "captains") throw fail("This event doesn't use a captains' draft.");
    const { manages } = await this.manages((x) => this.store.get(x), tournament, caller.uid);
    return { uid: caller.uid, tournamentId, divisionId, tournament, division, manager: manages };
  }

  private requireManager(c: Ctx) {
    if (!c.manager) throw organizersOnly();
  }

  /** Teams can't be redrafted once the schedule or the real teams exist. */
  private async requireOpen(c: Ctx) {
    if (await this.queries.hasGames(c.tournamentId, c.divisionId)) throw fail("The schedule is published.");
    if (teamsCreated(draftedTeams(c.division.teams))) throw fail("The teams have already been created.");
  }

  private async load(tx: Tx, c: Ctx): Promise<Loaded> {
    const draft = await tx.get(p.draft(c.tournamentId, c.divisionId));
    const poolDoc = await tx.get(p.pool(c.tournamentId, c.divisionId));
    if (!draft) throw fail("The draft hasn't started.");
    const names = mapOf(draft.pool);
    const details = mapOf(poolDoc?.players);
    const player = (uid: string, name: unknown): PoolPlayer => {
      const d = mapOf(own(details, uid));
      const gender = d.gender === "mmp" || d.gender === "wmp" ? d.gender : null;
      return { uid, name: String(name), skill: Number(d.skill ?? 3), gender };
    };
    const captains = (Array.isArray(draft.captains) ? draft.captains : []).map(mapOf).map((x) => ({ uid: String(x.uid), name: String(x.name) }));
    return {
      draft,
      captainIds: strings(draft.captainIds),
      picks: (Array.isArray(draft.picks) ? draft.picks : []).map(mapOf).map((x) => ({ uid: String(x.uid), captainId: String(x.captainId) })),
      pool: Object.entries(names).map(([uid, name]) => player(uid, name)),
      everyone: new Map([
        ...captains.map((x) => [x.uid, player(x.uid, x.name)] as const),
        ...Object.entries(names).map(([uid, name]) => [uid, player(uid, name)] as const),
      ]),
    };
  }

  /** Adds [uid] to the team on the clock and passes the turn. */
  private recordPick(tx: Tx, c: Ctx, l: Loaded, uid: string) {
    const picks = [...l.picks, { uid, captainId: onTheClock(l.captainIds, l.picks, l.pool.length) as string }];
    tx.update(p.draft(c.tournamentId, c.divisionId), {
      picks,
      status: picks.length >= l.pool.length ? "done" : "live",
      turnStartedAt: serverTime,
    });
  }

  /** The host starts a division's draft with the captains they chose, in a random order. */
  async startDraft(caller: Caller, rawTournament: unknown, rawDivision: unknown, body: unknown): Promise<{ captains: number; players: number }> {
    const c = await this.context(caller, rawTournament, rawDivision);
    this.requireManager(c);
    await this.requireOpen(c);
    const input = parse(startDraftRequestSchema, body);
    const signups = await this.queries.acceptedSignups(c.tournamentId, c.divisionId);
    const accepted = new Map(signups.map((s) => [s.id, s.data]));
    return this.store.transact(async (tx) => {
      if (await tx.get(p.draft(c.tournamentId, c.divisionId))) throw fail("This division already has a draft. Cancel it to start over.");
      const captainIds = input.captainIds;
      const problem = startProblem({ captainIds, accepted: new Set(accepted.keys()), poolSize: accepted.size - captainIds.length });
      if (problem) throw fail(problem);
      const order = shuffled(captainIds, this.random);
      const players = [...accepted.entries()].filter(([id]) => !captainIds.includes(id));
      tx.set(p.draft(c.tournamentId, c.divisionId), {
        status: "live",
        captains: order.map((id) => ({ uid: id, name: clipName(accepted.get(id)?.name) || "Captain" })),
        captainIds: order,
        pool: Object.fromEntries(players.map(([id, s]) => [id, clipName(s.name) || "Player"])),
        picks: [],
        pickSeconds: input.pickSeconds,
        mixed: c.division.division === "mixed",
        turnStartedAt: serverTime,
        startedBy: c.uid,
      });
      tx.set(p.pool(c.tournamentId, c.divisionId), {
        players: Object.fromEntries([...accepted.entries()].map(([id, s]) => [id, { skill: Number(s.skill ?? 3), gender: s.gender ?? null }])),
      });
      return { captains: order.length, players: players.length };
    });
  }

  /** The captain on the clock picks a player (the host can pick for them). */
  async pick(caller: Caller, rawTournament: unknown, rawDivision: unknown, body: unknown): Promise<void> {
    const c = await this.context(caller, rawTournament, rawDivision);
    const { uid } = parse(draftPickRequestSchema, body);
    await this.store.transact(async (tx) => {
      const l = await this.load(tx, c);
      const clock = onTheClock(l.captainIds, l.picks, l.pool.length);
      if (clock !== c.uid && !c.manager) throw new ApiError("permission_denied", "It's not your pick.");
      const problem = pickProblem({ status: String(l.draft.status), captainIds: l.captainIds, picks: l.picks, pool: l.pool, uid });
      if (problem) throw fail(problem);
      this.recordPick(tx, c, l, uid);
    });
  }

  /** The host pauses, resumes, undoes the last pick, auto-picks, or cancels the draft. */
  async control(caller: Caller, rawTournament: unknown, rawDivision: unknown, body: unknown): Promise<void> {
    const c = await this.context(caller, rawTournament, rawDivision);
    this.requireManager(c);
    const { action } = parse(draftControlRequestSchema, body);
    await this.store.transact(async (tx) => {
      const l = await this.load(tx, c);
      const draftPath = p.draft(c.tournamentId, c.divisionId);
      const status = String(l.draft.status);
      if (status === "finished") throw fail("The draft is finished.");
      switch (action) {
        case "cancel":
          tx.delete(p.pool(c.tournamentId, c.divisionId));
          tx.delete(draftPath);
          break;
        case "pause":
          if (status !== "live") throw fail("The draft isn't running.");
          tx.update(draftPath, { status: "paused" });
          break;
        case "resume":
          if (status !== "paused") throw fail("The draft isn't paused.");
          tx.update(draftPath, { status: "live", turnStartedAt: serverTime });
          break;
        case "undo":
          if (l.picks.length === 0) throw fail("Nothing to undo.");
          tx.update(draftPath, { picks: l.picks.slice(0, -1), status: status === "paused" ? "paused" : "live", turnStartedAt: serverTime });
          break;
        default: {
          const clock = onTheClock(l.captainIds, l.picks, l.pool.length);
          if (status !== "live" || clock === null) throw fail("Nobody is on the clock.");
          const team = [clock, ...l.picks.filter((x) => x.captainId === clock).map((x) => x.uid)]
            .map((id) => l.everyone.get(id))
            .filter((x): x is PoolPlayer => x !== undefined);
          const choice = autoPick(available(l.pool, l.picks), team, l.draft.mixed === true);
          if (!choice) throw fail("Nobody is left to pick.");
          this.recordPick(tx, c, l, choice.uid);
        }
      }
    });
  }

  /** The host turns the picks into the division's teams; unpicked players stay unassigned. */
  async finishDraft(caller: Caller, rawTournament: unknown, rawDivision: unknown): Promise<{ teams: number }> {
    const c = await this.context(caller, rawTournament, rawDivision);
    this.requireManager(c);
    await this.requireOpen(c);
    return this.store.transact(async (tx) => {
      const l = await this.load(tx, c);
      if (l.draft.status === "finished") throw fail("The draft is already finished.");
      const teams = teamsFromDraft({
        captains: (Array.isArray(l.draft.captains) ? l.draft.captains : []).map(mapOf).map((x) => ({ uid: String(x.uid), name: String(x.name) })),
        picks: l.picks,
        names: Object.fromEntries(Object.entries(mapOf(l.draft.pool)).map(([k, v]) => [k, String(v)])),
      });
      const divisionPath = p.division(c.tournamentId, c.divisionId);
      const division = (await tx.get(divisionPath)) ?? {};
      const before = Array.isArray(division.teams) ? division.teams.map((t) => String(mapOf(t).id ?? "")) : [];
      // Registered teams keep their seeds; only the drafted ones change.
      tx.update(divisionPath, { teams, ...withDrafted(division, before, teams) });
      tx.update(p.draft(c.tournamentId, c.divisionId), { status: "finished" });
      return { teams: teams.length };
    });
  }

  // ---- A league's real teams -----------------------------------------------------------

  /**
   * Turns a league's drafted teams into real teams (createLeagueTeams): the
   * captain owns each, the other players are its members, and it gets the
   * General and voice rooms, a directory listing and an accepted entry.
   * The division switches to the real ids in the same write; asking again
   * changes nothing.
   */
  async createLeagueTeams(caller: Caller, rawTournament: unknown, rawDivision: unknown): Promise<{ created: number; teams: { teamId: string; name: string }[] }> {
    if (typeof rawTournament !== "string" || !idPattern.test(rawTournament)) throw new ApiError("invalid_argument", "Pick a league.");
    if (typeof rawDivision !== "string" || !idPattern.test(rawDivision)) throw new ApiError("invalid_argument", "Pick a division.");
    const tournamentId = docIdParam(rawTournament);
    const divisionId = docIdParam(rawDivision);
    const divisionPath = p.division(tournamentId, divisionId);
    const [tournament, division] = await Promise.all([this.store.get(p.tournament(tournamentId)), this.store.get(divisionPath)]);
    if (!tournament || !division) throw new ApiError("not_found", "That league or division doesn't exist.");
    const { manages, host } = await this.manages((x) => this.store.get(x), tournament, caller.uid);
    if (!manages || !host) throw new ApiError("permission_denied", "Only the league's organizers can create its teams.");

    const drafted = draftedTeams(division.teams);
    if (teamsCreated(drafted)) return { created: 0, teams: drafted.map((t) => ({ teamId: t.id, name: t.name })) };

    const [signups, hasGames] = await Promise.all([this.queries.acceptedSignups(tournamentId, divisionId), this.queries.hasGames(tournamentId, divisionId)]);
    const problem = leagueProblem({ tournament, division, teams: drafted, accepted: new Set(signups.map((s) => s.id)), hasGames });
    if (problem) throw fail(problem);

    const city = typeof host.city === "string" ? host.city : "";
    // Real team ids become document paths, so each has to be one.
    const ids = drafted.map((t) => docIdParam(leagueTeamId(tournamentId, t.id)));
    const created = await this.store.transact(async (tx) => {
      const fresh = await tx.get(divisionPath);
      if (!fresh || JSON.stringify(draftedTeams(fresh.teams)) !== JSON.stringify(drafted)) {
        throw fail("The teams changed while they were being created. Try again.");
      }
      // A team made by an earlier, interrupted attempt keeps its own doc;
      // anything else at that id (someone who guessed it first) stops us.
      const existing = new Set<string>();
      for (const [i, id] of ids.entries()) {
        const doc = await tx.get(p.team(id));
        if (!doc) continue;
        if (!madeForLeague(doc, tournamentId, tournament.hostId, drafted[i].captainId)) {
          throw fail(`A team already uses the id for ${drafted[i].name}, and it isn't this league's. Ask us to remove it, then try again.`);
        }
        existing.add(id);
      }
      drafted.forEach((team: DraftedTeam, i) => {
        const teamId = ids[i];
        if (!existing.has(teamId)) {
          const doc = leagueTeamDoc({ team, tournamentId, tournament, division: fresh, city, createdAt: serverTime });
          tx.set(p.team(teamId), doc);
          tx.set(`teamDirectory/${teamId}`, leagueDirectoryDoc(doc));
          const chat = leagueTeamChat(team.captainId as string, serverTime);
          for (const [id, room] of Object.entries(chat.rooms)) tx.set(`teams/${teamId}/chats/${id}`, room);
          for (const [id, folder] of Object.entries(chat.folders)) tx.set(`teams/${teamId}/chatFolders/${id}`, folder);
        }
        tx.set(p.entry(tournamentId, teamId), leagueEntry(team, divisionId, serverTime));
      });
      tx.update(divisionPath, madeTeams(drafted, tournamentId, fresh));
      return drafted.length - existing.size;
    });
    return { created, teams: ids.map((teamId, i) => ({ teamId, name: drafted[i].name })) };
  }
}

/**
 * Whether [team], already at a league team's id, is the one an earlier
 * attempt made: leagueHostId is the server's alone (the team create rule
 * doesn't allow it), and the captain owns it.
 */
function madeForLeague(team: Data, tournamentId: string, hostId: unknown, captainId: string | null): boolean {
  return team.leagueId === tournamentId && team.leagueHostId === (hostId ?? null) && team.ownerId === captainId;
}
