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
  inLiveWindow,
  liveScoreOf,
  liveScoreRequestSchema,
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
import type { Caller } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam, storedId } from "../ids.js";
import type { DocQueries } from "../queries.js";
import { type Data, type DocStore, deleteField, serverTime, type Tx } from "../store.js";
import { can, kindOf, mapOf, strings } from "../teams/access.js";


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
const feeDoc = (f: { amountCents: number; currency: string; instructions: string; dueAt: Date | null; payerCoversFees: boolean } | null) =>
  f ? { amountCents: f.amountCents, currency: f.currency, instructions: f.instructions, dueAt: f.dueAt, payerCoversFees: f.payerCoversFees } : null;

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
  constructor(
    private readonly store: DocStore,
    private readonly queries: DocQueries,
    private readonly now: () => number = Date.now,
  ) {}

  // ---- Who's who -----------------------------------------------------------

  /** manages(t): the host's members with Manage events. */
  private async manages(tx: Pick<Tx, "get">, t: Data, uid: string): Promise<boolean> {
    const host = storedId(t.hostId);
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

  /**
   * Runs [writes] in transactions of up to [chunk] writes each, in order,
   * each after [check] (the caller still manages the event) in the same
   * transaction.
   */
  private async inChunks(writes: Array<(tx: Tx) => void>, check: (tx: Tx) => Promise<unknown>) {
    for (let i = 0; i < writes.length; i += chunk) {
      const part = writes.slice(i, i + chunk);
      await this.store.transact(async (tx) => {
        await check(tx);
        for (const w of part) w(tx);
      });
    }
  }

  /**
   * Deletes every document of [collection], a page of ids at a time until
   * none are left, each page after [check]. [children] deletes a
   * document's own subcollections first.
   */
  private async drain(collection: string, check: (tx: Tx) => Promise<unknown>, children?: (docId: string) => Promise<void>) {
    for (;;) {
      const ids = await this.queries.ids(collection, chunk);
      if (ids.length === 0) return;
      if (children) for (const docId of ids) await children(docId);
      await this.inChunks(
        ids.map((docId) => (tx: Tx) => tx.delete(`${collection}/${docId}`)),
        check,
      );
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
    const r: CreateTournamentInput = parseBody(createTournamentRequestSchema, body);
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
    const r = parseBody(saveTournamentRequestSchema, body);
    // Managers only get as far as the lists (checked again below).
    const first = await this.managed(this.store, id, caller.uid);
    const taking = ["status", "divisionId"];
    const [divRows, entries, signups] = await Promise.all([
      this.queries.fields(p.divisions(id), ["division"], 100),
      this.queries.fields(p.entries(id), taking, listMax),
      this.queries.fields(`tournaments/${id}/signups`, taking, listMax),
    ]);
    const taken = new Set<string>([
      ...entries.filter((e) => !["withdrawn", "declined"].includes(e.data.status as string)).map((e) => String(e.data.divisionId)),
      ...signups.filter((s) => !["withdrawn", "declined"].includes(s.data.status as string)).map((s) => String(s.data.divisionId)),
    ]);
    // Closing an empty division also clears any games it had: drained a
    // page at a time first (a transaction holds 500 writes), once the
    // request is known to be valid, each page re-checking that the caller
    // still manages it and the division is still empty.
    const closing = divRows.filter((d) => !r.divisions.includes(d.data.division as Division)).map((d) => d.id);
    if (closing.length) {
      this.checkHosted(first.kind === "league" ? "league" : "tournament", first.entryType === "players" ? "players" : "teams", r);
      for (const divId of closing) {
        const d = await this.store.get(p.division(id, divId));
        if (!d || divisionLocked(d, taken.has(divId))) continue;
        await this.drain(p.games(id, divId), async (tx) => {
          await this.managed(tx, id, caller.uid);
          const now = await tx.get(p.division(id, divId));
          if (now && divisionLocked(now, false)) throw new ApiError("failed_precondition", "A division you're closing just took teams. Try again.");
        });
      }
    }
    // Any game added since (a few at most) goes with the division.
    const gamesOf = new Map<string, string[]>();
    for (const divId of closing) gamesOf.set(divId, await this.queries.ids(p.games(id, divId), 100));
    await this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const hostId = storedId(t.hostId) as string;
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
        ...(Array.isArray(t.divisions) ? t.divisions.map((x) => storedId(mapOf(x).id)).filter((x): x is string => !!x) : []),
        ...[...stored.keys()],
      ].filter((x, i, l) => l.indexOf(x) === i && stored.has(x));
      const writes: Array<() => void> = [];
      const open = new Set<Division>();
      for (const divId of order) {
        const d = stored.get(divId) as Data;
        const locked = divisionLocked(d, taken.has(divId));
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
    const { status } = parseBody(tournamentStatusRequestSchema, body);
    await this.store.transact(async (tx) => {
      await this.managed(tx, id, caller.uid);
      tx.update(p.tournament(id), { status });
    });
  }

  /**
   * Deletes it with its divisions, games, entries, signups, drafts and
   * payments: each subcollection a page at a time until it's empty, every
   * page re-checked, and the tournament last, so a failure part way can be
   * tried again.
   */
  async remove(caller: Caller, rawId: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const check = (tx: Tx) => this.managed(tx, id, caller.uid);
    await this.store.transact(async (tx) => void (await check(tx)));
    await this.drain(p.divisions(id), check, (d) => this.drain(p.games(id, d), check));
    for (const sub of ["entries", "payments", "signups"]) await this.drain(`tournaments/${id}/${sub}`, check);
    await this.drain(`tournaments/${id}/drafts`, check, (d) => this.drain(`tournaments/${id}/drafts/${d}/details`, check));
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
    const check = (tx: Tx) => this.managed(tx, id, caller.uid);
    await this.store.transact(async (tx) => {
      await check(tx);
      if (!(await tx.get(p.division(id, divId)))) throw noDivision();
    });
    if ((await this.queries.ids(p.entries(id), 1, { divisionId: divId, status: "accepted" })).length > 0) {
      throw new ApiError("failed_precondition", "Move or remove its accepted teams first.");
    }
    await this.drain(p.games(id, divId), check);
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
    const { seeds } = parseBody(seedsRequestSchema, body);
    if ((await this.queries.ids(p.games(id, divId), 1)).length > 0) {
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
    const r = parseBody(entryRequestSchema, body);
    const divId = docIdParam(r.divisionId);
    // The team's admins only get as far as counting its roster (checked again below).
    await this.visible(this.store, id, caller.uid);
    const admin = await this.store.get(p.team(teamId));
    if (!admin) throw new ApiError("not_found", "That team doesn't exist.");
    if (!can(admin, caller.uid, "manageTeam")) throw new ApiError("permission_denied", "Only the team's admins can enter it.");
    const roster = (await this.queries.ids(`teams/${teamId}/roster`, 500)).length;
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
    const divId = docIdParam(parseBody(inviteRequestSchema, body).divisionId);
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
    const { status } = parseBody(entryStatusRequestSchema, body);
    await this.store.transact(async (tx) => {
      const { manager } = await this.visible(tx, id, caller.uid);
      const entry = await tx.get(p.entry(id, teamId));
      if (!entry) throw new ApiError("not_found", "That team hasn't entered.");
      const team = await tx.get(p.team(teamId));
      if (!team) throw new ApiError("not_found", "That team doesn't exist.");
      const divId = storedId(entry.divisionId);
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
    const { games } = parseBody(publishScheduleRequestSchema, body);
    const check = (tx: Tx) => this.managed(tx, id, caller.uid);
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
    const old = await this.queries.ids(p.games(id, divId), listMax);
    const fresh = new Set(games.map((g) => g.id));
    const writes: Array<(tx: Tx) => void> = [
      ...old.filter((g) => !fresh.has(g)).map((g) => (tx: Tx) => tx.delete(p.game(id, divId, g))),
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
    await this.inChunks(head, check);
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
    return this.queries.ids(p.games(id, divId), listMax);
  }

  /**
   * confirm()'s checks: a report on [g], the caller captains the other
   * team, and [s] is the reported score (the rule's `d.scoreA ==
   * g.report.scoreA`): a report filed again meanwhile isn't confirmed unseen.
   */
  private confirmable(d: Data, g: EngineGame, uid: string, s: { scoreA: number; scoreB: number }) {
    const r = g.report;
    if (g.status !== "reported" || !r) throw new ApiError("failed_precondition", "There's no score to confirm.");
    const other = r.byTeam === g.teamA ? g.teamB : g.teamA;
    if (!this.captainOf(d, other, uid)) throw new ApiError("permission_denied", "The other team's captain confirms the score.");
    if (r.scoreA !== s.scoreA || r.scoreB !== s.scoreB) throw new ApiError("failed_precondition", "The reported score changed. Check it again.");
    return r;
  }

  /** report(): a captain of one of the game's teams reports the score; the other confirms. */
  async report(caller: Caller, rawId: unknown, rawDiv: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const gameId = docIdParam(rawGame);
    const s = parseBody(scoreRequestSchema, body);
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

  /**
   * confirm(): the other team's captain confirms a report; the teams move
   * on (advance()). [body] is the score being confirmed ({scoreA, scoreB}).
   */
  async confirm(caller: Caller, rawId: unknown, rawDiv: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const gameId = docIdParam(rawGame);
    const s = parseBody(scoreRequestSchema, body);
    // Only the other captain gets as far as listing the games (checked again below).
    await this.visible(this.store, id, caller.uid);
    const [division, game] = await Promise.all([this.store.get(p.division(id, divId)), this.store.get(p.game(id, divId, gameId))]);
    if (!division || !game) throw new ApiError("not_found", "That game doesn't exist.");
    this.confirmable(division, engineGame(gameId, game), caller.uid, s);
    const ids = await this.gameIds(id, divId);
    await this.store.transact(async (tx) => {
      await this.visible(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      const games = await this.gamesIn(tx, id, divId, ids);
      const g = games.find((x) => x.id === gameId);
      if (!d || !g) throw new ApiError("not_found", "That game doesn't exist.");
      const r = this.confirmable(d, g, caller.uid, s);
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
    const s = parseBody(scoreRequestSchema, body);
    await this.managed(this.store, id, caller.uid);
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

  /**
   * The checks for a running score on [g] (setLive, clearLive): the event
   * is under way (not a draft or finished), the game has both teams and is
   * still scheduled (no score reported or final), and the caller is one of
   * its teams' captains (who report its score) or one of the host's event
   * managers. Returns the captain's team, or null for a manager.
   */
  private liveCheck(t: Data, manager: boolean, d: Data | null, g: Data | null, uid: string): string | null {
    if (!d || !g) throw new ApiError("not_found", "That game doesn't exist.");
    const status = statusOf(t);
    if (status === "draft" || status === "finished") throw new ApiError("failed_precondition", "This event isn't being played.");
    if (g.teamA == null || g.teamB == null) throw new ApiError("failed_precondition", "Teams are decided by earlier games.");
    if (g.status === "done") throw new ApiError("failed_precondition", "That game is final.");
    if (g.status === "reported") throw new ApiError("failed_precondition", "A final score is already reported for this game.");
    const byTeam = this.captainOf(d, g.teamA as string, uid)
      ? (g.teamA as string)
      : this.captainOf(d, g.teamB as string, uid)
        ? (g.teamB as string)
        : null;
    if (!byTeam && !manager) throw new ApiError("permission_denied", "Only the teams' captains and the host keep the live score.");
    return byTeam;
  }

  /**
   * setLive(): the running score while the game is played ([body]
   * {scoreA, scoreB}, 0–0 to start it). Not the final: the game stays
   * scheduled and the final is still reported and confirmed. Only from
   * liveLimits.earlyMs before the game's start to liveLimits.lateMs after.
   * The first live game makes a scheduled event live.
   */
  async setLive(caller: Caller, rawId: unknown, rawDiv: unknown, rawGame: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const gameId = docIdParam(rawGame);
    const s = parseBody(liveScoreRequestSchema, body);
    await this.store.transact(async (tx) => {
      const { t, manager } = await this.visible(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      const g = await tx.get(p.game(id, divId, gameId));
      this.liveCheck(t, manager, d, g, caller.uid);
      const startsAt = engineGame(gameId, g).startsAt;
      if (!inLiveWindow(startsAt, this.now())) {
        throw new ApiError("failed_precondition", "Live scores are kept on the day the game is played.");
      }
      const was = liveScoreOf(g!.live);
      tx.update(p.game(id, divId, gameId), {
        live: { scoreA: s.scoreA, scoreB: s.scoreB, startedAt: was?.startedAt ?? serverTime, updatedAt: serverTime, by: caller.uid },
      });
      if (statusOf(t) === "scheduled") tx.update(p.tournament(id), { status: "live" });
    });
  }

  /** clearLive(): takes the running score off (a game started by mistake); the same people as setLive. */
  async clearLive(caller: Caller, rawId: unknown, rawDiv: unknown, rawGame: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    const gameId = docIdParam(rawGame);
    await this.store.transact(async (tx) => {
      const { t, manager } = await this.visible(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      const g = await tx.get(p.game(id, divId, gameId));
      this.liveCheck(t, manager, d, g, caller.uid);
      if (g!.live !== undefined) tx.update(p.game(id, divId, gameId), { live: deleteField });
    });
  }

  /** Pools are done: the host seeds the bracket from the standings. */
  async seedBracket(caller: Caller, rawId: unknown, rawDiv: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const divId = docIdParam(rawDiv);
    await this.managed(this.store, id, caller.uid);
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
    // Managers only get as far as the lists (checked again below).
    const tour = await this.managed(this.store, id, caller.uid);
    const division = await this.store.get(p.division(id, divId));
    if (!division) throw noDivision();
    // A first look from small queries: the division's own entries and the
    // games' engine fields. Most looks change nothing, and need no
    // transaction; one that does reads again only what it may change.
    const [gameRows, entryRows] = await Promise.all([
      this.queries.fields(p.games(id, divId), engineGameFields, listMax),
      this.queries.fields(p.entries(id), ["status", "divisionId", "captainIds"], listMax, { divisionId: divId }),
    ]);
    // A seed's entry may name another division now (moved, then withdrawn).
    const entries = new Map(entryRows.map((e) => [e.id, e.data]));
    const elsewhere = strings(division.seeds)
      .map(storedId)
      .filter((s): s is string => s !== null && !entries.has(s));
    const moved = await this.store.getAll(elsewhere.map((s) => p.entry(id, s)));
    elsewhere.forEach((s, i) => {
      const e = moved[i];
      if (e) entries.set(s, e);
    });
    const seen = reconcilePlan({
      t: tour,
      d: division,
      divId,
      games: gameRows.map((g) => engineGame(g.id, g.data)).sort((a, b) => a.order - b.order),
      allGames: true,
      entries,
      others: null,
    });
    if (seen.changed.length === 0) return { changed: [] };
    const placing = seen.changed.includes("placements");
    // With no games (unpublished seeds), "every game" is none.
    const full = placing || gameRows.length === 0;
    // The games it may fill and the games they're filled from, a finished
    // one if it goes live, or every game when recording places.
    const fillIds = new Set(seen.fills.map((f) => f.gameId));
    const reread = full
      ? gameRows.map((g) => g.id)
      : [
          ...new Set([
            ...seen.games.filter((g) => fillIds.has(g.id)).flatMap((g) => [g.id, sourceGame(g.sourceA), sourceGame(g.sourceB)]),
            ...(seen.changed.includes("live") ? [seen.games.find(isDone)?.id] : []),
          ]),
        ].filter((x): x is string => !!x);
    const divIds = placing ? await this.queries.ids(p.divisions(id), 100) : [];
    return this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      if (!d) throw noDivision();
      let others: Data[] | null = null;
      if (placing) {
        others = [];
        for (const other of divIds) {
          if (other === divId) continue;
          const o = await tx.get(p.division(id, other));
          if (o) others.push(o);
        }
      }
      // The division's entries and every seed's (a seed's entry may have moved).
      const entries = new Map<string, Data>();
      for (const teamId of new Set([...entryRows.map((e) => e.id), ...strings(d.seeds).map(storedId).filter((s): s is string => s !== null)])) {
        const e = await tx.get(p.entry(id, teamId));
        if (e) entries.set(teamId, e);
      }
      const games = await this.gamesIn(tx, id, divId, reread);
      const plan = reconcilePlan({ t, d, divId, games, allGames: full, entries, others });
      for (const f of plan.fills) tx.update(p.game(id, divId, f.gameId), fillUpdate(f));
      if (Object.keys(plan.change).length) {
        checkDivision(divisionDoc(d, plan.change));
        tx.update(p.division(id, divId), plan.change);
      }
      if (plan.status !== statusOf(t)) tx.update(p.tournament(id), { status: plan.status });
      return { changed: plan.changed };
    });
  }
}

/** A division that stays open: it has seeds or teams, or [taken] (people or teams signed up). */
const divisionLocked = (d: Data, taken: boolean) => strings(d.seeds).length > 0 || (Array.isArray(d.teams) && d.teams.length > 0) || taken;

/** The game fields engineGame reads (reconcile's first look). */
const engineGameFields = [
  "order", "stage", "round", "label", "pool", "field", "startsAt", "teamA", "teamB",
  "sourceA", "sourceB", "status", "scoreA", "scoreB", "report", "ifNeeded", "place",
] as const;

/** The game a winner/loser slot is filled from. */
const sourceGame = (s: EngineGame["sourceA"]) => (s && (s.type === "winner" || s.type === "loser") ? s.game : null);

/**
 * What reconcile changes, from what it read: [games] are every game of
 * the division if [allGames], else only those it may fill (and their
 * sources), so places aren't worked out; [others] are the other
 * divisions, read only when recording places (null otherwise).
 */
function reconcilePlan(r: {
  t: Data;
  d: Data;
  divId: string;
  games: EngineGame[];
  allGames: boolean;
  entries: Map<string, Data>;
  others: Data[] | null;
}): { fills: ReturnType<typeof pendingFills>; status: HostedStatus; change: Data; changed: string[]; games: EngineGame[] } {
  const { t, d, divId, games, entries } = r;
  const changed: string[] = [];
  const fills = pendingFills(games);
  if (fills.length) changed.push("fills");

  let status = statusOf(t);
  if (status === "scheduled" && games.some(isDone)) {
    status = "live";
    changed.push("live");
  }

  const change: Data = {};
  const seeds = strings(d.seeds);
  if (r.allGames && games.length === 0) {
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

  if (r.allGames && strings(d.placements).length === 0 && fills.length === 0) {
    const fmt = formatOf({ kind: t.kind as "league", season: (t.season as never) ?? null }, { settings: { format: mapOf(d.settings).format as TournamentFormat } });
    const places = placementsOf(fmt, seeds, games);
    if (places.length > 0 && gamesToPlay(games).length === 0) {
      change.placements = places;
      changed.push("placements");
      // The first look doesn't read the other divisions: finishing is decided in the transaction.
      if (r.others?.every((o) => strings(o.placements).length > 0)) {
        status = "finished";
        changed.push("finished");
      }
    }
  }
  return { fills, status, change, changed, games };
}
