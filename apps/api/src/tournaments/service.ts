// Hosted tournaments and leagues (tournaments/{id} and its divisions,
// games and entries): the rules of `match /tournaments/{tournamentId}` in
// firebase/firestore.rules ported, with the app's own checks
// (HostedTournamentViewModel, HostedTournamentFormViewModel). The Admin SDK
// skips the rules, so these are what guard the website's writes. The
// documents written are the app's (HostedTournament.toMap and friends), so
// the entrySchedule, tournamentSchedule and leagueGameEvents triggers keep
// working as they do for the app.
//
// The website generates a schedule in the browser (the engine's calendar
// maths is in local time, as on the phone) and the API checks each game.
// Results that move teams on are worked out here from the stored games.
import {
  type CreateTournamentInput,
  createTournamentRequestSchema,
  type Division,
  divisionLabel,
  divisions as allDivisions,
  type EngineGame,
  engineGame,
  type EntryStatus,
  entryRequestSchema,
  entryStatusRequestSchema,
  fillsAfter,
  formatOf,
  gamesToPlay,
  hostedStatuses,
  type HostedStatus,
  inviteRequestSchema,
  isDone,
  laterGamesPlayed,
  leagueFitProblem,
  leagueTeamPrefix,
  pendingFills,
  placementsOf,
  publishScheduleRequestSchema,
  type SaveTournamentInput,
  saveTournamentRequestSchema,
  scoreRequestSchema,
  seedsRequestSchema,
  type SlotFill,
  statusIndex,
  tournamentLimits,
  tournamentStatusRequestSchema,
  bracketSeeds,
  type TournamentFormat,
} from "@stall10/shared";
import type { z } from "zod";
import type { Caller } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import { type Data, type DocStore, serverTime, type Tx } from "../store.js";
import { can, kindOf, mapOf, strings } from "../teams/access.js";

function parse<S extends z.ZodType>(schema: S, body: unknown): z.output<S> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) throw fromZod(r.error);
  return r.data;
}

/** A stored id that is safe to put in a path, or null. */
function safeId(v: unknown): string | null {
  if (typeof v !== "string" || !v) return null;
  try {
    return docIdParam(v);
  } catch {
    return null;
  }
}

const p = {
  tournament: (id: string) => `tournaments/${id}`,
  divisions: (id: string) => `tournaments/${id}/divisions`,
  division: (id: string, d: string) => `tournaments/${id}/divisions/${d}`,
  games: (id: string, d: string) => `tournaments/${id}/divisions/${d}/games`,
  game: (id: string, d: string, g: string) => `tournaments/${id}/divisions/${d}/games/${g}`,
  entries: (id: string) => `tournaments/${id}/entries`,
  entry: (id: string, team: string) => `tournaments/${id}/entries/${team}`,
  team: (id: string) => `teams/${id}`,
};

/** Writes per transaction when a change is too big for one (Firestore takes 500). */
const chunk = 450;
const listMax = 2200;

const notFound = () => new ApiError("not_found", "That tournament doesn't exist.");
const noDivision = () => new ApiError("not_found", "That division doesn't exist.");
const hostOnly = (what = "Only the host's event managers can do that.") => new ApiError("permission_denied", what);

const statusOf = (t: Data): HostedStatus =>
  (hostedStatuses as readonly string[]).includes(t.status as string) ? (t.status as HostedStatus) : "draft";
const entryStatusOf = (e: Data | null): EntryStatus | null => (e ? ((e.status as EntryStatus) ?? "applied") : null);

/** The fee as stored (BidFee.toMap). */
const feeDoc = (f: { amountCents: number; currency: string; instructions: string; dueAt: Date | null } | null) =>
  f ? { amountCents: f.amountCents, currency: f.currency, instructions: f.instructions, dueAt: f.dueAt } : null;

type FormatInput = SaveTournamentInput["format"];

/** TournamentSettings.toMap. */
const settingsDoc = (s: FormatInput["settings"], format?: TournamentFormat) => ({
  format: format ?? s.format,
  playersOnField: s.playersOnField,
  poolCount: s.poolCount,
  gameMinutes: s.gameMinutes,
  breakMinutes: s.breakMinutes,
  scoreCap: s.scoreCap,
  timeoutsPerHalf: s.timeoutsPerHalf,
  fields: s.fields,
  startsAt: s.startsAt,
  idealEndsAt: s.idealEndsAt,
  laterDays: s.laterDays,
  scoring: s.scoring,
});

/** EventFormat.toMap. */
const formatDoc = (f: FormatInput) => ({ settings: settingsDoc(f.settings), level: f.level, maxTeams: f.maxTeams, minRoster: f.minRoster });

/** The division a format makes (EventFormat.divisionFor). */
const newDivisionDoc = (f: FormatInput, division: Division) => ({
  division,
  level: f.level,
  settings: settingsDoc(f.settings),
  maxTeams: f.maxTeams,
  seeds: [],
  captains: {},
  placements: [],
  minRoster: f.minRoster,
  teams: [],
});

/** A division as stored, every key the app writes (TournamentDivision.toMap). */
function divisionDoc(d: Data, change: Data = {}): Data {
  return {
    division: d.division,
    level: d.level,
    settings: d.settings ?? {},
    maxTeams: d.maxTeams,
    seeds: strings(d.seeds),
    captains: mapOf(d.captains),
    placements: strings(d.placements),
    minRoster: d.minRoster ?? null,
    teams: Array.isArray(d.teams) ? d.teams : [],
    ...change,
  };
}

/** validDivision(d), as the rule checks it. */
function checkDivision(d: Data) {
  const minRoster = d.minRoster;
  const teams = Array.isArray(d.teams) ? d.teams : [];
  const maxTeams = d.maxTeams;
  const ok =
    (minRoster == null || (Number.isInteger(minRoster) && (minRoster as number) >= 2 && (minRoster as number) <= 30)) &&
    teams.length <= tournamentLimits.maxDraftedTeams &&
    (allDivisions as readonly string[]).includes(d.division as string) &&
    ["club", "college", "youth", "league", "pickup"].includes(d.level as string) &&
    !!d.settings &&
    typeof d.settings === "object" &&
    Number.isInteger(maxTeams) &&
    (maxTeams as number) >= 2 &&
    (maxTeams as number) <= 64 &&
    Array.isArray(d.seeds) &&
    d.seeds.length <= (maxTeams as number) &&
    Object.keys(mapOf(d.captains)).length <= tournamentLimits.maxCaptainsMap &&
    Array.isArray(d.placements) &&
    d.placements.length <= tournamentLimits.maxPlacements;
  if (!ok) throw new ApiError("invalid_argument", "That division isn't valid.");
}

/** A fill as a game update: only the slots it fills. */
const fillUpdate = (f: SlotFill): Data => ({ ...(f.teamA != null && { teamA: f.teamA }), ...(f.teamB != null && { teamB: f.teamB }) });

export class TournamentService {
  constructor(private readonly store: DocStore) {}

  // ---- Who's who -----------------------------------------------------------

  /** manages(t): the host's members with Manage events. */
  private async manages(tx: Pick<Tx, "get">, t: Data, uid: string): Promise<boolean> {
    const host = safeId(t.hostId);
    if (!host) return false;
    const team = await tx.get(p.team(host));
    return !!team && can(team, uid, "manageEvents");
  }

  /** The tournament if the caller may see it (visible(t)): published, or theirs to manage. */
  private async visible(tx: Pick<Tx, "get">, id: string, uid: string): Promise<{ t: Data; manager: boolean }> {
    const t = await tx.get(p.tournament(id));
    if (!t) throw notFound();
    const manager = await this.manages(tx, t, uid);
    if (statusOf(t) === "draft" && !manager) throw notFound();
    return { t, manager };
  }

  private async managed(tx: Pick<Tx, "get">, id: string, uid: string): Promise<Data> {
    const { t, manager } = await this.visible(tx, id, uid);
    if (!manager) throw hostOnly();
    return t;
  }

  /** Runs [writes] in transactions of up to [chunk] writes each, in order. */
  private async inChunks(writes: Array<(tx: Tx) => void>) {
    for (let i = 0; i < writes.length; i += chunk) {
      const part = writes.slice(i, i + chunk);
      await this.store.transact(async (tx) => {
        for (const w of part) w(tx);
      });
    }
  }

  // ---- Hosting and editing -------------------------------------------------

  /** validHosted(t) beyond the request's shape, plus the form's own checks (HostedTournamentFormViewModel.problem). */
  private checkHosted(kind: string, entryType: string, r: SaveTournamentInput) {
    if (r.teamEntry && entryType !== "players") {
      throw new ApiError("invalid_argument", "Only events that players sign up for take team spots too.");
    }
    if (kind !== "league" && r.season != null) throw new ApiError("invalid_argument", "Only a league has a season.");
    if (r.season && r.season.playoffTeams > 0) {
      if (r.season.playoffWeeks < 1) throw new ApiError("invalid_argument", "Give the playoffs at least one week.");
      if (r.season.playoffWeeks >= r.season.weeks) throw new ApiError("invalid_argument", "Leave at least one week for the regular season.");
    }
    if (r.endsOn && r.endsOn.getTime() < r.startsOn.getTime()) throw new ApiError("invalid_argument", "It can't end before it starts.");
    if (r.bidFee && r.teamEntry && !r.teamFee) throw new ApiError("invalid_argument", "Enter the team spot fee, e.g. 300.");
  }

  /** The tournament's fields (HostedTournament.toMap), its host's details from the host team. */
  private hostedFields(host: Data, hostId: string, kind: string, entryType: string, status: HostedStatus, r: SaveTournamentInput, divisions: Data[]): Data {
    const teamEntry = entryType === "players" && r.teamEntry;
    return {
      hostId,
      hostName: String(host.name ?? "").slice(0, tournamentLimits.hostName),
      hostKind: kindOf(host),
      hostOfficial: host.official === true,
      name: r.name,
      startsOn: r.startsOn,
      endsOn: r.endsOn,
      description: r.description,
      location: r.location,
      visibility: r.visibility,
      entryType,
      status,
      bidFee: feeDoc(r.bidFee),
      teamEntry,
      teamFee: teamEntry && r.bidFee ? feeDoc(r.teamFee) : null,
      kind,
      season: kind === "league" && r.season ? { ...r.season } : null,
      draftMode: r.draftMode,
      divisions,
      format: formatDoc(r.format),
    };
  }

  async create(caller: Caller, body: unknown): Promise<{ id: string }> {
    const r: CreateTournamentInput = parse(createTournamentRequestSchema, body);
    const hostId = docIdParam(r.hostId);
    this.checkHosted(r.kind, r.entryType, r);
    const id = this.store.newId("tournaments");
    const opened = allDivisions.filter((d) => r.divisions.includes(d));
    const ids = opened.map(() => this.store.newId(p.divisions(id)));
    await this.store.transact(async (tx) => {
      const host = await tx.get(p.team(hostId));
      if (!host) throw new ApiError("not_found", "That team doesn't exist.");
      if (!can(host, caller.uid, "manageEvents")) throw hostOnly("Only members who manage events can host tournaments.");
      const summaries = opened.map((d, i) => ({ id: ids[i], division: d, level: r.format.level }));
      tx.create(p.tournament(id), {
        ...this.hostedFields(host, hostId, r.kind, r.entryType, "draft", r, summaries),
        createdBy: caller.uid,
        createdAt: serverTime,
      });
      opened.forEach((d, i) => {
        const doc = newDivisionDoc(r.format, d);
        checkDivision(doc);
        tx.create(p.division(id, ids[i]), doc);
      });
    });
    return { id };
  }

  /**
   * Saves the details and format, and opens and closes divisions
   * (HostedTournamentFormViewModel._save): a division with teams or people
   * signed up stays open; the others take the format while schedules
   * aren't out yet.
   */
  async save(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const r = parse(saveTournamentRequestSchema, body);
    const [divRows, entries, signups] = await Promise.all([
      this.store.list(p.divisions(id), 100),
      this.store.list(p.entries(id), listMax),
      this.store.list(`tournaments/${id}/signups`, listMax),
    ]);
    const taken = new Set<string>([
      ...entries.filter((e) => !["withdrawn", "declined"].includes(e.data.status as string)).map((e) => String(e.data.divisionId)),
      ...signups.filter((s) => !["withdrawn", "declined"].includes(s.data.status as string)).map((s) => String(s.data.divisionId)),
    ]);
    // Closing an empty division also clears any games it had.
    const gamesOf = new Map<string, string[]>();
    for (const d of divRows) {
      if (!r.divisions.includes(d.data.division as Division)) {
        gamesOf.set(d.id, (await this.store.list(p.games(id, d.id), 400)).map((g) => g.id));
      }
    }
    await this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const hostId = safeId(t.hostId) as string;
      const host = (await tx.get(p.team(hostId))) as Data;
      const kind = t.kind === "league" ? "league" : "tournament";
      const entryType = t.entryType === "players" ? "players" : "teams";
      this.checkHosted(kind, entryType, r);
      const stored = new Map<string, Data>();
      for (const row of divRows) {
        const d = await tx.get(p.division(id, row.id));
        if (d) stored.set(row.id, d);
      }
      const editable = statusIndex(statusOf(t)) < statusIndex("scheduled");
      const summaries: Array<{ id: string; division: unknown; level: unknown }> = [];
      const order = [
        ...(Array.isArray(t.divisions) ? t.divisions.map((x) => safeId(mapOf(x).id)).filter((x): x is string => !!x) : []),
        ...[...stored.keys()],
      ].filter((x, i, l) => l.indexOf(x) === i && stored.has(x));
      const writes: Array<() => void> = [];
      const open = new Set<Division>();
      for (const divId of order) {
        const d = stored.get(divId) as Data;
        const locked = strings(d.seeds).length > 0 || (Array.isArray(d.teams) && d.teams.length > 0) || taken.has(divId);
        const wanted = r.divisions.includes(d.division as Division);
        if (!wanted && !locked) {
          const draft = `tournaments/${id}/drafts/${divId}`;
          writes.push(() => {
            for (const g of gamesOf.get(divId) ?? []) tx.delete(p.game(id, divId, g));
            tx.delete(`${draft}/details/pool`);
            tx.delete(draft);
            tx.delete(p.division(id, divId));
          });
          continue;
        }
        open.add(d.division as Division);
        if (wanted && editable) {
          // EventFormat.restamp: teams, seeds and results stay.
          const seeds = strings(d.seeds).length;
          const change = {
            level: r.format.level,
            maxTeams: Math.max(r.format.maxTeams, seeds),
            minRoster: r.format.minRoster,
            settings: settingsDoc(r.format.settings),
          };
          checkDivision(divisionDoc(d, change));
          writes.push(() => tx.update(p.division(id, divId), change));
          summaries.push({ id: divId, division: d.division, level: r.format.level });
        } else {
          summaries.push({ id: divId, division: d.division, level: d.level });
        }
      }
      for (const g of allDivisions) {
        if (!r.divisions.includes(g) || open.has(g)) continue;
        const divId = this.store.newId(p.divisions(id));
        const doc = newDivisionDoc(r.format, g);
        checkDivision(doc);
        writes.push(() => tx.create(p.division(id, divId), doc));
        summaries.push({ id: divId, division: g, level: r.format.level });
      }
      if (summaries.length > tournamentLimits.maxDivisions) {
        throw new ApiError("invalid_argument", `Up to ${tournamentLimits.maxDivisions} divisions.`);
      }
      // hostId, createdBy and createdAt stay as they are.
      tx.update(p.tournament(id), this.hostedFields(host, hostId, kind, entryType, statusOf(t), r, summaries));
      for (const w of writes) w();
    });
  }

  async setStatus(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const { status } = parse(tournamentStatusRequestSchema, body);
    await this.store.transact(async (tx) => {
      await this.managed(tx, id, caller.uid);
      tx.update(p.tournament(id), { status });
    });
  }

  /** Deletes it with its divisions, games, entries, signups, drafts and payments. */
  async remove(caller: Caller, rawId: unknown): Promise<void> {
    const id = docIdParam(rawId);
    await this.store.transact(async (tx) => void (await this.managed(tx, id, caller.uid)));
    const paths: string[] = [];
    for (const d of await this.store.list(p.divisions(id), 100)) {
      for (const g of await this.store.list(p.games(id, d.id), listMax)) paths.push(p.game(id, d.id, g.id));
      paths.push(p.division(id, d.id));
    }
    for (const sub of ["entries", "payments", "signups"]) {
      for (const row of await this.store.list(`tournaments/${id}/${sub}`, listMax)) paths.push(`tournaments/${id}/${sub}/${row.id}`);
    }
    for (const d of await this.store.list(`tournaments/${id}/drafts`, 100)) {
      paths.push(`tournaments/${id}/drafts/${d.id}/details/pool`, `tournaments/${id}/drafts/${d.id}`);
    }
    await this.inChunks(paths.map((path) => (tx: Tx) => tx.delete(path)));
    await this.store.transact(async (tx) => {
      if (!(await tx.get(p.tournament(id)))) return;
      await this.managed(tx, id, caller.uid);
      tx.delete(p.tournament(id));
    });
  }

  // ---- Divisions -----------------------------------------------------------

  /** Removes a division with no accepted teams, its games and draft, and its place in the list. */
  async removeDivision(caller: Caller, rawId: unknown, rawDiv: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const entries = await this.store.list(p.entries(id), listMax);
    if (entries.some((e) => e.data.divisionId === divId && e.data.status === "accepted")) {
      throw new ApiError("failed_precondition", "Move or remove its accepted teams first.");
    }
    await this.store.transact(async (tx) => {
      await this.managed(tx, id, caller.uid);
      if (!(await tx.get(p.division(id, divId)))) throw noDivision();
    });
    const games = await this.store.list(p.games(id, divId), listMax);
    await this.inChunks(games.map((g) => (tx: Tx) => tx.delete(p.game(id, divId, g.id))));
    await this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const draft = `tournaments/${id}/drafts/${divId}`;
      tx.delete(`${draft}/details/pool`);
      tx.delete(draft);
      tx.delete(p.division(id, divId));
      tx.update(p.tournament(id), {
        divisions: (Array.isArray(t.divisions) ? t.divisions : []).filter((d) => mapOf(d).id !== divId),
      });
    });
  }

  /** The host reorders a division's accepted teams, until its schedule is out. */
  async saveSeeds(caller: Caller, rawId: unknown, rawDiv: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const { seeds } = parse(seedsRequestSchema, body);
    if ((await this.store.list(p.games(id, divId), 1)).length > 0) {
      throw new ApiError("failed_precondition", "Seeds are set: the schedule is published.");
    }
    await this.store.transact(async (tx) => {
      await this.managed(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      if (!d) throw noDivision();
      const current = strings(d.seeds);
      if (seeds.length !== current.length || new Set(seeds).size !== seeds.length || !seeds.every((s) => current.includes(s))) {
        throw new ApiError("failed_precondition", "The teams changed. Try again.");
      }
      checkDivision(divisionDoc(d, { seeds }));
      tx.update(p.division(id, divId), { seeds });
    });
  }

  // ---- Entries -------------------------------------------------------------

  /** validEntry(e): shape, and captains from the team's members. */
  private entryDoc(team: Data, e: { teamName: string; divisionId: string; status: EntryStatus; captainIds: string[] }): Data {
    if (e.teamName.length < 1 || e.teamName.length > tournamentLimits.teamName) throw new ApiError("invalid_argument", "The team needs a name.");
    if (e.divisionId.length > tournamentLimits.divisionId) throw new ApiError("invalid_argument", "Invalid division.");
    if (e.captainIds.length > tournamentLimits.maxCaptains) {
      throw new ApiError("invalid_argument", `Pick up to ${tournamentLimits.maxCaptains} captains.`);
    }
    const members = new Set(strings(team.memberIds));
    if (!e.captainIds.every((c) => members.has(c))) throw new ApiError("invalid_argument", "Captains have to be on the team.");
    return { teamName: e.teamName, divisionId: e.divisionId, status: e.status, captainIds: e.captainIds, updatedAt: serverTime };
  }

  /**
   * A team's admins apply, accept an invite, or change their captains
   * (teamApplies, teamEdits), with the app's checks: a team (not a group),
   * fit for a league's division, and the roster minimum.
   */
  async putEntry(caller: Caller, rawId: unknown, rawTeam: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const teamId = docIdParam(rawTeam);
    const r = parse(entryRequestSchema, body);
    const divId = docIdParam(r.divisionId);
    const roster = (await this.store.list(`teams/${teamId}/roster`, 500)).length;
    await this.store.transact(async (tx) => {
      const { t } = await this.visible(tx, id, caller.uid);
      const team = await tx.get(p.team(teamId));
      if (!team) throw new ApiError("not_found", "That team doesn't exist.");
      const existing = await tx.get(p.entry(id, teamId));
      const division = await tx.get(p.division(id, divId));
      if (!division) throw noDivision();
      if (!can(team, caller.uid, "manageTeam")) throw new ApiError("permission_denied", "Only the team's admins can enter it.");
      const was = entryStatusOf(existing);
      if (was === "applied" || was === "accepted" || was === "waitlisted") {
        // teamEdits(): captains only, status unchanged.
        if (existing?.divisionId !== divId) {
          throw new ApiError("failed_precondition", "To change division, withdraw and apply again.");
        }
        tx.set(p.entry(id, teamId), this.entryDoc(team, { teamName: String(existing.teamName ?? ""), divisionId: divId, status: was, captainIds: r.captainIds }));
        return;
      }
      if (was === "declined") throw new ApiError("failed_precondition", "The host declined this team. They can invite it again.");
      // teamApplies(t).
      if (kindOf(team) !== "team") throw new ApiError("invalid_argument", "Only teams enter tournaments.");
      if (t.status !== "registration") throw new ApiError("failed_precondition", "Registration isn't open.");
      if (t.entryType === "players" && t.teamEntry !== true) {
        throw new ApiError("failed_precondition", "Players sign up one by one here; teams are drawn from them.");
      }
      if (t.visibility !== "public" && was !== "invited") throw new ApiError("permission_denied", "Invite only: the host invites the teams.");
      if (t.kind === "league") {
        const problem = leagueFitProblem(
          { name: String(team.name ?? "Team"), division: team.division as string, level: team.level as string },
          { division: division.division as Division, level: division.level as "club" },
        );
        if (problem) throw new ApiError("failed_precondition", problem);
      }
      const minimum = typeof division.minRoster === "number" ? division.minRoster : tournamentLimits.defaultMinRoster;
      // Where teams reserve spots, they fill their roster afterwards.
      const mixed = t.entryType === "players" && t.teamEntry === true;
      if (roster < minimum && !mixed) {
        throw new ApiError(
          "failed_precondition",
          `${String(team.name ?? "The team")} needs at least ${minimum} players on its roster to register (it has ${roster}). Add players on the team's Roster tab, then try again.`,
        );
      }
      tx.set(
        p.entry(id, teamId),
        this.entryDoc(team, { teamName: String(team.name ?? "").slice(0, tournamentLimits.teamName), divisionId: divId, status: "applied", captainIds: r.captainIds }),
      );
    });
  }

  /** The host invites a team (not one already entered). */
  async invite(caller: Caller, rawId: unknown, rawTeam: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const teamId = docIdParam(rawTeam);
    const divId = docIdParam(parse(inviteRequestSchema, body).divisionId);
    await this.store.transact(async (tx) => {
      await this.managed(tx, id, caller.uid);
      const team = await tx.get(p.team(teamId));
      if (!team || kindOf(team) !== "team") throw new ApiError("not_found", "That team doesn't exist.");
      const existing = await tx.get(p.entry(id, teamId));
      if (!(await tx.get(p.division(id, divId)))) throw noDivision();
      const was = entryStatusOf(existing);
      if (was && was !== "withdrawn") {
        throw new ApiError("already_exists", `${String(team.name ?? "That team")} is already ${String(was === "waitlisted" ? "on the waitlist" : was)}.`);
      }
      tx.set(p.entry(id, teamId), this.entryDoc(team, { teamName: String(team.name ?? "Team").slice(0, 100), divisionId: divId, status: "invited", captainIds: [] }));
    });
  }

  /**
   * The host accepts, waitlists, declines or removes an entry; a team's
   * admins withdraw it (teamWithdraws). Accepting seeds it last in its
   * division and makes its captains the ones who report scores; anything
   * else takes it out of the seeds.
   */
  async setEntryStatus(caller: Caller, rawId: unknown, rawTeam: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const teamId = docIdParam(rawTeam);
    const { status } = parse(entryStatusRequestSchema, body);
    await this.store.transact(async (tx) => {
      const { manager } = await this.visible(tx, id, caller.uid);
      const entry = await tx.get(p.entry(id, teamId));
      if (!entry) throw new ApiError("not_found", "That team hasn't entered.");
      const team = await tx.get(p.team(teamId));
      if (!team) throw new ApiError("not_found", "That team doesn't exist.");
      const divId = safeId(entry.divisionId);
      const division = divId ? await tx.get(p.division(id, divId)) : null;
      const fields = { teamName: String(entry.teamName ?? ""), divisionId: String(entry.divisionId ?? ""), captainIds: strings(entry.captainIds) };
      if (!manager) {
        if (status !== "withdrawn" || !can(team, caller.uid, "manageTeam")) throw hostOnly("Only the host decides on entries.");
        tx.set(p.entry(id, teamId), this.entryDoc(team, { ...fields, status }));
        return;
      }
      if (status === "accepted") {
        if (!division || !divId) throw new ApiError("not_found", "That division no longer exists.");
        const seeds = strings(division.seeds);
        if (seeds.length >= Number(division.maxTeams) && !seeds.includes(teamId)) {
          throw new ApiError(
            "failed_precondition",
            `${divisionLabel(division as { division: Division; level: "club" })} is full (${String(division.maxTeams)} teams). Waitlist the team or raise the cap.`,
          );
        }
        const change = {
          seeds: seeds.includes(teamId) ? seeds : [...seeds, teamId],
          captains: { ...mapOf(division.captains), [teamId]: fields.captainIds },
        };
        tx.set(p.entry(id, teamId), this.entryDoc(team, { ...fields, status }));
        checkDivision(divisionDoc(division, change));
        tx.update(p.division(id, divId), change);
        return;
      }
      tx.set(p.entry(id, teamId), this.entryDoc(team, { ...fields, status }));
      if (division && divId && strings(division.seeds).includes(teamId)) {
        tx.update(p.division(id, divId), {
          seeds: strings(division.seeds).filter((s) => s !== teamId),
          captains: Object.fromEntries(Object.entries(mapOf(division.captains)).filter(([k]) => k !== teamId)),
        });
      }
    });
  }

  // ---- Schedule ------------------------------------------------------------

  /**
   * Publishes (or regenerates) a division's games, as generated in the
   * browser from its seeds, checking each against validGame; the
   * division's results reset and a tournament not yet scheduled becomes so.
   */
  async publish(caller: Caller, rawId: unknown, rawDiv: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const { games } = parse(publishScheduleRequestSchema, body);
    const old = await this.store.list(p.games(id, divId), listMax);
    let format: TournamentFormat = "roundRobin";
    await this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      if (!d) throw noDivision();
      const seeds = strings(d.seeds);
      const drafted = Array.isArray(d.teams) ? d.teams.map((x) => String(mapOf(x).id ?? "")) : [];
      // needsTeamsCreated: a league that takes players makes its real teams first.
      const teamsCreated = drafted.length > 0 && drafted.every((x) => x.startsWith(leagueTeamPrefix));
      const mixed = t.entryType === "players" && t.teamEntry === true;
      if (t.kind === "league" && t.entryType === "players" && !teamsCreated && (drafted.length > 0 || !mixed)) {
        throw new ApiError("failed_precondition", "Create the league's teams first: draft teams, then Create teams.");
      }
      if (seeds.length < 2) throw new ApiError("failed_precondition", "Accept at least two teams first.");
      const ids = new Set(games.map((g) => g.id));
      if (ids.size !== games.length) throw new ApiError("invalid_argument", "Each game once.");
      games.forEach((g, i) => {
        const teamOk = (x: string | null) => x == null || seeds.includes(x);
        const sourceOk = (s: (typeof g)["sourceA"]) => s == null || s.type === "pool" || (ids.has(s.game) && s.game !== g.id);
        if (g.order !== i || !teamOk(g.teamA) || !teamOk(g.teamB) || !sourceOk(g.sourceA) || !sourceOk(g.sourceB)) {
          throw new ApiError("invalid_argument", "That schedule doesn't match the division's teams. Refresh and try again.");
        }
      });
      format = formatOf({ kind: t.kind as "league", season: (t.season as never) ?? null }, { settings: { format: mapOf(d.settings).format as TournamentFormat } });
    });
    const writes: Array<(tx: Tx) => void> = [
      ...old.filter((g) => !games.some((n) => n.id === g.id)).map((g) => (tx: Tx) => tx.delete(p.game(id, divId, g.id))),
      ...games.map((g) => (tx: Tx) =>
        tx.set(p.game(id, divId, g.id), {
          order: g.order,
          stage: g.stage,
          round: g.round,
          label: g.label,
          pool: g.pool,
          field: g.field,
          startsAt: g.startsAt,
          teamA: g.teamA,
          teamB: g.teamB,
          sourceA: g.sourceA,
          sourceB: g.sourceB,
          status: "scheduled",
          scoreA: null,
          scoreB: null,
          report: null,
          ifNeeded: g.ifNeeded,
          ...(g.place != null && { place: g.place }),
        }),
      ),
    ];
    // The division and status ride in the last chunk, after every game.
    const head = writes.slice(0, Math.max(0, writes.length - (chunk - 2)));
    const tail = writes.slice(head.length);
    await this.inChunks(head);
    await this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      if (!d) throw noDivision();
      for (const w of tail) w(tx);
      tx.set(p.division(id, divId), divisionDoc(d, { placements: [], settings: { ...mapOf(d.settings), format } }));
      if (statusIndex(statusOf(t)) < statusIndex("scheduled")) tx.update(p.tournament(id), { status: "scheduled" });
    });
  }

  // ---- Games ---------------------------------------------------------------

  /** The division's captains map. */
  private captainOf(d: Data, teamRef: string | null, uid: string): boolean {
    return teamRef != null && strings(mapOf(d.captains)[teamRef]).includes(uid);
  }

  /** Every game of a division, read again in the transaction. */
  private async gamesIn(tx: Tx, id: string, divId: string, ids: string[]): Promise<EngineGame[]> {
    const out: EngineGame[] = [];
    for (const g of ids) {
      const data = await tx.get(p.game(id, divId, g));
      if (data) out.push(engineGame(g, data));
    }
    return out.sort((a, b) => a.order - b.order);
  }

  private async gameIds(id: string, divId: string) {
    return (await this.store.list(p.games(id, divId), listMax)).map((g) => g.id);
  }

  /** report(): a captain of one of the game's teams reports the score; the other confirms. */
  async report(caller: Caller, rawId: unknown, rawDiv: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const gameId = docIdParam(rawGame);
    const s = parse(scoreRequestSchema, body);
    await this.store.transact(async (tx) => {
      await this.visible(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      const g = await tx.get(p.game(id, divId, gameId));
      if (!d || !g) throw new ApiError("not_found", "That game doesn't exist.");
      if (g.teamA == null || g.teamB == null) throw new ApiError("failed_precondition", "Teams are decided by earlier games.");
      if (g.status === "done") throw new ApiError("failed_precondition", "That game is final.");
      const byTeam = this.captainOf(d, g.teamA as string, caller.uid)
        ? (g.teamA as string)
        : this.captainOf(d, g.teamB as string, caller.uid)
          ? (g.teamB as string)
          : null;
      if (!byTeam) throw new ApiError("permission_denied", "Only team captains report scores.");
      tx.update(p.game(id, divId, gameId), { report: { scoreA: s.scoreA, scoreB: s.scoreB, byTeam }, status: "reported" });
    });
  }

  /** confirm(): the other team's captain confirms a report; the teams move on (advance()). */
  async confirm(caller: Caller, rawId: unknown, rawDiv: unknown, rawGame: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const gameId = docIdParam(rawGame);
    const ids = await this.gameIds(id, divId);
    await this.store.transact(async (tx) => {
      await this.visible(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      const games = await this.gamesIn(tx, id, divId, ids);
      const g = games.find((x) => x.id === gameId);
      if (!d || !g) throw new ApiError("not_found", "That game doesn't exist.");
      const r = g.report;
      if (g.status !== "reported" || !r) throw new ApiError("failed_precondition", "There's no score to confirm.");
      const other = r.byTeam === g.teamA ? g.teamB : g.teamA;
      if (!this.captainOf(d, other, caller.uid)) throw new ApiError("permission_denied", "The other team's captain confirms the score.");
      const done: EngineGame = { ...g, status: "done", scoreA: r.scoreA, scoreB: r.scoreB, report: null };
      tx.update(p.game(id, divId, gameId), { status: "done", scoreA: r.scoreA, scoreB: r.scoreB, report: null });
      for (const f of fillsAfter(done, games)) tx.update(p.game(id, divId, f.gameId), fillUpdate(f));
    });
  }

  /** A host manager sets (or corrects) a final score, unless later games already depend on it. */
  async setScore(caller: Caller, rawId: unknown, rawDiv: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const gameId = docIdParam(rawGame);
    const s = parse(scoreRequestSchema, body);
    const ids = await this.gameIds(id, divId);
    await this.store.transact(async (tx) => {
      await this.managed(tx, id, caller.uid);
      const games = await this.gamesIn(tx, id, divId, ids);
      const g = games.find((x) => x.id === gameId);
      if (!g) throw new ApiError("not_found", "That game doesn't exist.");
      if (g.teamA == null || g.teamB == null) throw new ApiError("failed_precondition", "Teams are decided by earlier games.");
      if (laterGamesPlayed(g, games)) throw new ApiError("failed_precondition", "Later games already depend on this result.");
      const done: EngineGame = { ...g, status: "done", scoreA: s.scoreA, scoreB: s.scoreB, report: null };
      tx.update(p.game(id, divId, gameId), { status: "done", scoreA: s.scoreA, scoreB: s.scoreB, report: null });
      for (const f of fillsAfter(done, games, true)) tx.update(p.game(id, divId, f.gameId), fillUpdate(f));
    });
  }

  /** Pools are done: the host seeds the bracket from the standings. */
  async seedBracket(caller: Caller, rawId: unknown, rawDiv: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const ids = await this.gameIds(id, divId);
    await this.store.transact(async (tx) => {
      await this.managed(tx, id, caller.uid);
      const fills = bracketSeeds(await this.gamesIn(tx, id, divId, ids));
      if (fills.length === 0) throw new ApiError("failed_precondition", "The pools aren't done yet.");
      for (const f of fills) tx.update(p.game(id, divId, f.gameId), fillUpdate(f));
    });
  }

  /**
   * What the app's manager view keeps in step while a host is looking
   * (HostedTournamentViewModel: _catchUp, _goLive, _recordPlacements,
   * _dropWithdrawn, _syncCaptains), for one division: teams moved on after
   * a result whose update didn't land, the first result making it live, a
   * finished division's places (and the event final once every division
   * has them), withdrawn teams out of unpublished seeds, and captains
   * copied from the teams' entries. Answers what it changed.
   */
  async reconcile(caller: Caller, rawId: unknown, rawDiv: unknown): Promise<{ changed: string[] }> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const [ids, entryRows, divRows] = await Promise.all([this.gameIds(id, divId), this.store.list(p.entries(id), listMax), this.store.list(p.divisions(id), 100)]);
    return this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      if (!d) throw noDivision();
      const others: Data[] = [];
      for (const row of divRows) {
        if (row.id === divId) continue;
        const o = await tx.get(p.division(id, row.id));
        if (o) others.push(o);
      }
      const entries = new Map<string, Data>();
      for (const row of entryRows) {
        const e = await tx.get(p.entry(id, row.id));
        if (e) entries.set(row.id, e);
      }
      const games = await this.gamesIn(tx, id, divId, ids);
      const changed: string[] = [];

      const fills = pendingFills(games);
      for (const f of fills) tx.update(p.game(id, divId, f.gameId), fillUpdate(f));
      if (fills.length) changed.push("fills");

      let status = statusOf(t);
      if (status === "scheduled" && games.some(isDone)) {
        status = "live";
        changed.push("live");
      }

      const change: Data = {};
      const seeds = strings(d.seeds);
      if (games.length === 0) {
        const gone = seeds.filter((s) => entries.get(s)?.status === "withdrawn");
        if (gone.length) {
          change.seeds = seeds.filter((s) => !gone.includes(s));
          change.captains = Object.fromEntries(Object.entries(mapOf(d.captains)).filter(([k]) => !gone.includes(k)));
          changed.push("withdrawn");
        }
      }
      const captains = mapOf(change.captains ?? d.captains);
      let synced = false;
      for (const [teamId, e] of entries) {
        if (e.status !== "accepted" || e.divisionId !== divId || !strings(change.seeds ?? d.seeds).includes(teamId)) continue;
        const want = strings(e.captainIds);
        const have = strings(captains[teamId]);
        if (want.length !== have.length || want.some((u, i) => have[i] !== u)) {
          captains[teamId] = want;
          synced = true;
        }
      }
      if (synced) {
        change.captains = captains;
        changed.push("captains");
      }

      if (strings(d.placements).length === 0 && fills.length === 0) {
        const fmt = formatOf({ kind: t.kind as "league", season: (t.season as never) ?? null }, { settings: { format: mapOf(d.settings).format as TournamentFormat } });
        const places = placementsOf(fmt, seeds, games);
        if (places.length > 0 && gamesToPlay(games).length === 0) {
          change.placements = places;
          changed.push("placements");
          if (others.every((o) => strings(o.placements).length > 0)) {
            status = "finished";
            changed.push("finished");
          }
        }
      }
      if (Object.keys(change).length) {
        checkDivision(divisionDoc(d, change));
        tx.update(p.division(id, divId), change);
      }
      if (status !== statusOf(t)) tx.update(p.tournament(id), { status });
      return { changed };
    });
  }
}
