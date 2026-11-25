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
  registrationWindowDays,
  registrationWindowProblem,
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
  inviteExpired,
  inviteExpiredMessage,
  inviteReplyBy,
  isDone,
  laterGamesPlayed,
  hostDefaults,
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
  type TeamTournamentInvite,
  canMoveStatus,
  effectiveMinRoster,
  type EntryAnswer,
  entryDeadlineProblem,
  entryRosterRequestSchema,
  hostedStatusLabels,
  publishAllRequestSchema,
  effectiveDeadline,
  entryChecklist,
  teamFee,
  type TeamEntryToFinish,

  type PublishGameInput,
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

/** A stored time (a Date from Firestore, or an ISO string) as a Date, or null. */
const dateOf = (v: unknown): Date | null => {
  const d = v instanceof Date ? v : typeof v === "string" ? new Date(v) : null;
  return d && !Number.isNaN(d.getTime()) ? d : null;
};

const notFound = () => new ApiError("not_found", "That tournament doesn't exist.");
const noDivision = () => new ApiError("not_found", "That division doesn't exist.");
const hostOnly = (what = "Only the host's event managers can do that.") => new ApiError("permission_denied", what);

const statusOf = (t: Data): HostedStatus =>
  (hostedStatuses as readonly string[]).includes(t.status as string) ? (t.status as HostedStatus) : "draft";
const entryStatusOf = (e: Data | null): EntryStatus | null => (e ? ((e.status as EntryStatus) ?? "applied") : null);

/**
 * The fee as stored (BidFee.toMap). With an entry deadline set, the fee is
 * due then (rosters and fees share one deadline).
 */
const feeDoc = (
  f: { amountCents: number; currency: string; instructions: string; dueAt: Date | null; payerCoversFees: boolean } | null,
  deadline: Date | null = null,
) =>
  f
    ? { amountCents: f.amountCents, currency: f.currency, instructions: f.instructions, dueAt: deadline ?? f.dueAt, payerCoversFees: f.payerCoversFees }
    : null;

/** The director as stored, or null. */
const directorDoc = (d: SaveTournamentInput["director"]) => (d ? { uid: d.uid, name: d.name, email: d.email, phone: d.phone } : null);

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
    seedsConfirmedAt: d.seedsConfirmedAt ?? null,
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

/** What tournaments need from payments (PaymentService): fees Stall 10 holds for an event. */
export interface TournamentPayouts {
  /** Sends the host its share once the event is finished. Never throws. */
  releaseTournament(id: string): Promise<void>;
  /** How many fees paid online Stall 10 still holds for it. */
  heldFor(id: string): Promise<number>;
}

export class TournamentService {
  constructor(
    private readonly store: DocStore,
    private readonly queries: DocQueries,
    private readonly now: () => number = Date.now,
    private readonly payouts?: TournamentPayouts,
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
    const late = entryDeadlineProblem(r.entryDeadline, r.startsOn);
    if (late) throw new ApiError("invalid_argument", late);
  }

  /** A director who's a member must be a real account; their name is theirs. */
  private async checkDirector(tx: Pick<Tx, "get">, r: SaveTournamentInput) {
    const uid = r.director?.uid;
    if (!uid) return;
    if (!(await tx.get(`users/${docIdParam(uid)}`))) throw new ApiError("invalid_argument", "That director isn't on Stall 10. Enter their name and contact details instead.");
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
      bidFee: feeDoc(r.bidFee, r.entryDeadline),
      teamEntry,
      teamFee: teamEntry && r.bidFee ? feeDoc(r.teamFee, r.entryDeadline) : null,
      kind,
      season: kind === "league" && r.season ? { ...r.season } : null,
      draftMode: r.draftMode,
      inviteReplyDays: r.inviteReplyDays,
      entryDeadline: r.entryDeadline,
      director: directorDoc(r.director),
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
      await this.checkDirector(tx, r);
      const summaries = opened.map((d, i) => ({ id: ids[i], division: d, level: r.format.level }));
      tx.create(p.tournament(id), {
        ...this.hostedFields(host, hostId, r.kind, r.entryType, "draft", r, summaries),
        createdBy: caller.uid,
        createdAt: serverTime,
      });
      // The host team in its own event (enterHost): accepted and seeded in
      // the division matching its own (else the first), the creator its
      // captain. Teams-entry events only; no fee (teamFee).
      const own = r.enterHost === true && r.entryType === "teams" && (host.kind ?? "team") === "team"
          ? hostDefaults({ kind: String(host.kind ?? "team"), division: String(host.division ?? ""), level: String(host.level ?? "") }, r.kind)
          : null;
      const hostIn = own ? Math.max(0, opened.indexOf(own.division)) : -1;
      if (own && r.kind === "league") {
        const problem = leagueFitProblem(
          { name: String(host.name ?? "Team"), division: host.division as string, level: host.level as string },
          { division: opened[hostIn], level: r.format.level as "club" },
        );
        if (problem) throw new ApiError("failed_precondition", problem);
      }
      opened.forEach((d, i) => {
        const doc = newDivisionDoc(r.format, d);
        const withHost = i === hostIn ? { ...doc, seeds: [hostId], captains: { [hostId]: [caller.uid] } } : doc;
        checkDivision(withHost);
        tx.create(p.division(id, ids[i]), withHost);
      });
      if (hostIn >= 0) {
        tx.set(
          p.entry(id, hostId),
          this.entryDoc(host, {
            teamId: hostId,
            teamName: String(host.name ?? "").slice(0, tournamentLimits.teamName),
            divisionId: ids[hostIn],
            status: "accepted",
            captainIds: [caller.uid],
          }),
        );
      }
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
      await this.checkDirector(tx, r);
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
      // Moving an open event's date further out than the window isn't allowed.
      const newStart = dateOf(r.startsOn);
      const live = statusOf(t) !== "draft" && statusOf(t) !== "finished";
      if (live && newStart && newStart.getTime() !== dateOf(t.startsOn)?.getTime()) {
        const problem = registrationWindowProblem(newStart, this.now());
        if (problem) throw new ApiError("failed_precondition", `Registration is open, so the event can start at most ${registrationWindowDays} days from now. Move it back to a draft first.`);
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
      const t = await this.managed(tx, id, caller.uid);
      const from = statusOf(t);
      if (!canMoveStatus(from, status)) {
        throw new ApiError(
          "failed_precondition",
          status === "scheduled"
            ? "Publish the schedule to make it scheduled."
            : `It can't go from ${hostedStatusLabels[from]} to ${hostedStatusLabels[status]}.`,
        );
      }
      // Registration (entries, signups, fees) opens only within
      // registrationWindowDays of the start: fees aren't held for long.
      if (status === "registration") {
        const problem = registrationWindowProblem(dateOf(t.startsOn), this.now());
        if (problem) throw new ApiError("failed_precondition", problem);
      }
      // finishedAt starts the payout hold (payments/service.ts releasable).
      // Reopened: a later finish starts a new hold.
      tx.update(p.tournament(id), { status, finishedAt: status === "finished" ? serverTime : deleteField });
    });
    if (status === "finished") await this.payouts?.releaseTournament(id);
  }

  /**
   * Deletes it with its chats (and their conversations), divisions, games,
   * entries, signups, drafts and payments: each subcollection a page at a time until it's empty, every
   * page re-checked, and the tournament last, so a failure part way can be
   * tried again.
   */
  async remove(caller: Caller, rawId: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const check = (tx: Tx) => this.managed(tx, id, caller.uid);
    await this.store.transact(async (tx) => void (await check(tx)));
    // Fees Stall 10 holds for it go back to the payers first (the Teams tab's Refund).
    const held = (await this.payouts?.heldFor(id)) ?? 0;
    if (held > 0) {
      throw new ApiError(
        "failed_precondition",
        held === 1 ? "Refund the fee paid online first (Teams)." : `Refund the ${held} fees paid online first (Teams).`,
      );
    }
    // Its chats with the organizers first (the Captains' channel and each
    // team's thread), so they leave everyone's inbox and nothing that
    // follows (the entries going) updates them. The pointers stay for the
    // tournamentDeleted function, which deletes them with the chats'
    // attachments once the tournament is gone.
    for (const chat of await this.queries.ids(`tournaments/${id}/chats`, 1000)) {
      const pointer = await this.store.get(`tournaments/${id}/chats/${chat}`);
      const conv = typeof pointer?.conversationId === "string" && /^g-[A-Za-z0-9]+$/.test(pointer.conversationId) ? pointer.conversationId : null;
      if (!conv) continue;
      const c = await this.store.get(`conversations/${conv}`);
      if (!c || c.kind !== "tournament" || c.tournamentId !== id) continue;
      for (const sub of ["messages", "typing"]) await this.drain(`conversations/${conv}/${sub}`, check);
      await this.store.transact(async (tx) => {
        await check(tx);
        if (await tx.get(`conversations/${conv}`)) tx.delete(`conversations/${conv}`);
      });
    }
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
    const { seeds, confirm } = parseBody(seedsRequestSchema, body);
    // Only managers get as far as the games (checked again below).
    await this.managed(this.store, id, caller.uid);
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
      if (confirm && seeds.length < 2) throw new ApiError("failed_precondition", "Accept at least two teams first.");
      const same = seeds.every((s, i) => current[i] === s);
      // Confirming sets the time; a change without it unconfirms them.
      const confirmedAt = confirm ? serverTime : same ? (d.seedsConfirmedAt ?? null) : null;
      const change = { seeds, seedsConfirmedAt: confirmedAt };
      checkDivision(divisionDoc(d, change));
      tx.update(p.division(id, divId), change);
    });
  }

  // ---- Entries -------------------------------------------------------------

  /** validEntry(e): shape, and captains from the team's members. */
  private entryDoc(
    team: Data,
    e: {
      teamId: string;
      teamName: string;
      divisionId: string;
      status: EntryStatus;
      captainIds: string[];
      replyBy?: Date | null;
      /** The entry as it was: its roster stays; its reason only while still withdrawn. */
      was?: Data | null;
      reason?: string | null;
    },
  ): Data {
    if (e.teamName.length < 1 || e.teamName.length > tournamentLimits.teamName) throw new ApiError("invalid_argument", "The team needs a name.");
    if (e.divisionId.length > tournamentLimits.divisionId) throw new ApiError("invalid_argument", "Invalid division.");
    if (e.captainIds.length > tournamentLimits.maxCaptains) {
      throw new ApiError("invalid_argument", `Pick up to ${tournamentLimits.maxCaptains} captains.`);
    }
    const members = new Set(strings(team.memberIds));
    if (!e.captainIds.every((c) => members.has(c))) throw new ApiError("invalid_argument", "Captains have to be on the team.");
    return {
      teamName: e.teamName,
      divisionId: e.divisionId,
      status: e.status,
      captainIds: e.captainIds,
      teamId: e.teamId,
      // An invite's answer-by time; gone once it's answered.
      replyBy: e.status === "invited" ? (e.replyBy ?? null) : null,
      // The players named for this event stay through status changes.
      roster: strings(e.was?.roster),
      rosterSetAt: e.was?.rosterSetAt ?? null,
      reason: e.status === "withdrawn" ? (e.reason ?? null) : null,
      updatedAt: serverTime,
    };
  }

  /**
   * Puts an entry in its division (the host accepting, or a team taking up
   * an invite): seeded last, its captains the ones who report scores, and
   * the seeds no longer confirmed. False when the division is full.
   */
  private seedIn(tx: Tx, id: string, divId: string, division: Data, teamId: string, captainIds: string[]): boolean {
    const seeds = strings(division.seeds);
    if (seeds.length >= Number(division.maxTeams) && !seeds.includes(teamId)) return false;
    const change = {
      seeds: seeds.includes(teamId) ? seeds : [...seeds, teamId],
      captains: { ...mapOf(division.captains), [teamId]: captainIds },
      ...(!seeds.includes(teamId) && { seedsConfirmedAt: null }),
    };
    checkDivision(divisionDoc(division, change));
    tx.update(p.division(id, divId), change);
    return true;
  }

  /**
   * A team's admins apply, take up an invite, or change their captains
   * (teamApplies, teamEdits), with the app's checks: a team (not a group)
   * and fit for a league's division. Taking up an invite puts the team in
   * straight away (accepted, or waitlisted when the division is full); an
   * application waits for the host. The roster is named separately
   * (putRoster), by the entry deadline.
   */
  async putEntry(caller: Caller, rawId: unknown, rawTeam: unknown, body: unknown): Promise<EntryAnswer> {
    const id = docIdParam(rawId);
    const teamId = docIdParam(rawTeam);
    const r = parseBody(entryRequestSchema, body);
    const divId = docIdParam(r.divisionId);
    return this.store.transact(async (tx): Promise<EntryAnswer> => {
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
        tx.set(
          p.entry(id, teamId),
          this.entryDoc(team, { teamId, teamName: String(existing.teamName ?? ""), divisionId: divId, status: was, captainIds: r.captainIds, was: existing }),
        );
        // An accepted team's captains are the ones who report its scores.
        if (was === "accepted" && strings(division.seeds).includes(teamId)) {
          tx.update(p.division(id, divId), { captains: { ...mapOf(division.captains), [teamId]: r.captainIds } });
        }
        return { status: was };
      }
      if (was === "declined") throw new ApiError("failed_precondition", "The host declined this team. They can invite it again.");
      // Past its reply-by time (inviteReplyDays) an invite can't be taken up.
      if (was === "invited" && inviteExpired({ status: was, replyBy: dateOf(existing?.replyBy) }, new Date(this.now()))) {
        throw new ApiError("failed_precondition", inviteExpiredMessage);
      }
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
      const fields = { teamId, teamName: String(team.name ?? "").slice(0, tournamentLimits.teamName), divisionId: divId, captainIds: r.captainIds, was: existing };
      if (was === "invited") {
        // Invited: in straight away, or on the waitlist when it's full.
        const status: EntryStatus = this.seedIn(tx, id, divId, division, teamId, r.captainIds) ? "accepted" : "waitlisted";
        tx.set(p.entry(id, teamId), this.entryDoc(team, { ...fields, status }));
        return { status };
      }
      tx.set(p.entry(id, teamId), this.entryDoc(team, { ...fields, status: "applied" }));
      return { status: "applied" };
    });
  }

  /**
   * A team's admins or its captains for this event name the players it
   * brings (ids from teams/{id}/roster): at least the division's roster
   * minimum (effectiveMinRoster; any number where teams reserve spots),
   * while the entry is in or waiting, until play starts.
   */
  async putRoster(caller: Caller, rawId: unknown, rawTeam: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const teamId = docIdParam(rawTeam);
    const { playerIds } = parseBody(entryRosterRequestSchema, body);
    const allowed = (team: Data | null, entry: Data | null) =>
      !!team && !!entry && (can(team, caller.uid, "manageTeam") || strings(entry.captainIds).includes(caller.uid));
    // Only the team's admins and captains get as far as listing its roster (checked again below).
    await this.visible(this.store, id, caller.uid);
    const [team0, entry0] = await Promise.all([this.store.get(p.team(teamId)), this.store.get(p.entry(id, teamId))]);
    if (!entry0) throw new ApiError("not_found", "That team hasn't entered.");
    if (!allowed(team0, entry0)) throw new ApiError("permission_denied", "Only the team's admins and captains set its roster.");
    const onTeam = new Set(await this.queries.ids(`teams/${teamId}/roster`, 500));
    await this.store.transact(async (tx) => {
      const { t } = await this.visible(tx, id, caller.uid);
      const team = await tx.get(p.team(teamId));
      const entry = await tx.get(p.entry(id, teamId));
      if (!entry) throw new ApiError("not_found", "That team hasn't entered.");
      if (!allowed(team, entry)) throw new ApiError("permission_denied", "Only the team's admins and captains set its roster.");
      const status = entryStatusOf(entry);
      if (status !== "applied" && status !== "accepted" && status !== "waitlisted") {
        throw new ApiError("failed_precondition", "Only a team that's entered sets a roster.");
      }
      if (statusIndex(statusOf(t)) >= statusIndex("live")) throw new ApiError("failed_precondition", "Rosters are locked once play starts.");
      if (!playerIds.every((x) => onTeam.has(x))) throw new ApiError("invalid_argument", "Pick players from the team's roster.");
      const divId = storedId(entry.divisionId);
      const division = divId ? await tx.get(p.division(id, divId)) : null;
      const mixed = t.entryType === "players" && t.teamEntry === true;
      const minimum = division ? effectiveMinRoster({ minRoster: division.minRoster as number | null }) : tournamentLimits.defaultMinRoster;
      if (!mixed && playerIds.length < minimum) {
        throw new ApiError("invalid_argument", `Pick at least ${minimum} players (you picked ${playerIds.length}).`);
      }
      tx.update(p.entry(id, teamId), { roster: playerIds, rosterSetAt: serverTime, updatedAt: serverTime });
    });
  }

  /**
   * The host invites a team (not one already entered; again once it
   * withdrew, or its invite expired), to answer by the event's reply-by
   * time (inviteReplyBy).
   */
  async invite(caller: Caller, rawId: unknown, rawTeam: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const teamId = docIdParam(rawTeam);
    const divId = docIdParam(parseBody(inviteRequestSchema, body).divisionId);
    await this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const team = await tx.get(p.team(teamId));
      if (!team || kindOf(team) !== "team") throw new ApiError("not_found", "That team doesn't exist.");
      const existing = await tx.get(p.entry(id, teamId));
      if (!(await tx.get(p.division(id, divId)))) throw noDivision();
      const was = entryStatusOf(existing);
      const now = new Date(this.now());
      const expired = was === "invited" && inviteExpired({ status: was, replyBy: dateOf(existing?.replyBy) }, now);
      if (was && was !== "withdrawn" && !expired) {
        throw new ApiError("already_exists", `${String(team.name ?? "That team")} is already ${String(was === "waitlisted" ? "on the waitlist" : was)}.`);
      }
      const startsOn = dateOf(t.startsOn);
      const replyBy = startsOn ? inviteReplyBy(startsOn, typeof t.inviteReplyDays === "number" ? t.inviteReplyDays : null, now) : null;
      tx.set(
        p.entry(id, teamId),
        this.entryDoc(team, { teamId, teamName: String(team.name ?? "Team").slice(0, 100), divisionId: divId, status: "invited", captainIds: [], replyBy }),
      );
    });
  }

  /**
   * A team's open tournament invites, for its admins (manageTeam): the
   * team page's Accept / Decline. Expired ones are listed as expired until
   * the event starts; answered ones and events that have started aren't.
   * Found through the team's records of its entries
   * (teams/{id}/tournamentEntries, kept by the entrySchedule trigger), then
   * read from the entries themselves, which have the last word.
   */
  async teamInvites(caller: Caller, rawTeam: unknown): Promise<TeamTournamentInvite[]> {
    const teamId = docIdParam(rawTeam);
    const team = await this.store.get(p.team(teamId));
    if (!team) throw new ApiError("not_found", "That team doesn't exist.");
    if (!can(team, caller.uid, "manageTeam")) throw new ApiError("permission_denied", "Only the team's admins see its tournament invites.");
    const ids = await this.queries.ids(`teams/${teamId}/tournamentEntries`, 50, { status: "invited" });
    const [events, entries] = await Promise.all([this.store.getAll(ids.map((t) => p.tournament(t))), this.store.getAll(ids.map((t) => p.entry(t, teamId)))]);
    const now = new Date(this.now());
    const out: TeamTournamentInvite[] = [];
    for (const [i, tid] of ids.entries()) {
      const t = events[i];
      const entry = entries[i];
      if (!t || !entry || entryStatusOf(entry) !== "invited" || statusOf(t) === "draft") continue;
      const startsOn = dateOf(t.startsOn);
      if (!startsOn || startsOn.getTime() + 24 * 60 * 60 * 1000 < now.getTime()) continue;
      const divisionId = String(entry.divisionId ?? "");
      const summary = (Array.isArray(t.divisions) ? t.divisions : []).find((d) => mapOf(d).id === divisionId);
      const replyBy = dateOf(entry.replyBy);
      out.push({
        tournamentId: tid,
        name: String(t.name ?? "Tournament"),
        hostName: String(t.hostName ?? ""),
        kind: t.kind === "league" ? "league" : "tournament",
        startsOn: startsOn.toISOString(),
        endsOn: dateOf(t.endsOn)?.toISOString() ?? null,
        location: String(t.location ?? ""),
        divisionId,
        divisionLabel: summary ? divisionLabel(mapOf(summary) as { division: Division; level: "club" }) : "",
        replyBy: replyBy?.toISOString() ?? null,
        expired: inviteExpired({ status: "invited", replyBy }, now),
      });
    }
    return out.sort((a, b) => a.startsOn.localeCompare(b.startsOn));
  }

  /**
   * A team's entries still missing their roster or fee, for its admins
   * (manageTeam): the team page's "Finish entry". Events that have started
   * aren't listed; neither are complete entries.
   */
  async teamEntriesToFinish(caller: Caller, rawTeam: unknown): Promise<TeamEntryToFinish[]> {
    const teamId = docIdParam(rawTeam);
    const team = await this.store.get(p.team(teamId));
    if (!team) throw new ApiError("not_found", "That team doesn't exist.");
    if (!can(team, caller.uid, "manageTeam")) throw new ApiError("permission_denied", "Only the team's admins see its entries.");
    const ids = (
      await Promise.all((["applied", "accepted", "waitlisted"] as const).map((status) => this.queries.ids(`teams/${teamId}/tournamentEntries`, 50, { status })))
    ).flat();
    const [events, entries, payments] = await Promise.all([
      this.store.getAll(ids.map((t) => p.tournament(t))),
      this.store.getAll(ids.map((t) => p.entry(t, teamId))),
      this.store.getAll(ids.map((t) => `tournaments/${t}/payments/${teamId}`)),
    ]);
    const now = this.now();
    const out: TeamEntryToFinish[] = [];
    for (const [i, tid] of ids.entries()) {
      const t = events[i];
      const entry = entries[i];
      const status = entryStatusOf(entry);
      if (!t || !entry || !status || !["applied", "accepted", "waitlisted"].includes(status) || statusOf(t) === "draft") continue;
      const startsOn = dateOf(t.startsOn);
      if (!startsOn || startsOn.getTime() < now || statusIndex(statusOf(t)) >= statusIndex("live")) continue;
      const divisionId = String(entry.divisionId ?? "");
      const division = await this.store.get(p.division(tid, divisionId));
      const mixed = t.entryType === "players" && t.teamEntry === true;
      const fee = teamFee({ ...(t as never as Parameters<typeof teamFee>[0]), hostId: String(t.hostId ?? "") }, teamId);
      const deadline = effectiveDeadline(t as never);
      const list = entryChecklist({
        status,
        rosterSize: mixed ? null : strings(entry.roster).length,
        minRoster: effectiveMinRoster({ minRoster: (division?.minRoster as number | null) ?? null }),
        paid: payments[i]?.paid === true,
        owes: !!fee && fee.amountCents > 0,
        deadline,
        now,
      });
      if (list.complete) continue;
      const summary = (Array.isArray(t.divisions) ? t.divisions : []).find((d) => mapOf(d).id === divisionId);
      out.push({
        tournamentId: tid,
        name: String(t.name ?? "Tournament"),
        hostName: String(t.hostName ?? ""),
        startsOn: startsOn.toISOString(),
        divisionLabel: summary ? divisionLabel(mapOf(summary) as { division: Division; level: "club" }) : "",
        status,
        rosterSet: list.rosterSet,
        paid: list.paid,
        deadline: deadline?.toISOString() ?? null,
        overdue: list.overdue,
      });
    }
    return out.sort((a, b) => a.startsOn.localeCompare(b.startsOn));
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
    const { status, reason } = parseBody(entryStatusRequestSchema, body);
    await this.store.transact(async (tx) => {
      const { manager } = await this.visible(tx, id, caller.uid);
      const entry = await tx.get(p.entry(id, teamId));
      if (!entry) throw new ApiError("not_found", "That team hasn't entered.");
      const team = await tx.get(p.team(teamId));
      if (!team) throw new ApiError("not_found", "That team doesn't exist.");
      const divId = storedId(entry.divisionId);
      const division = divId ? await tx.get(p.division(id, divId)) : null;
      const fields = { teamId, teamName: String(entry.teamName ?? ""), divisionId: String(entry.divisionId ?? ""), captainIds: strings(entry.captainIds), was: entry };
      const teamAdmin = can(team, caller.uid, "manageTeam");
      // A team's admins withdraw (saying why, when they turn an invite
      // down). Its seed goes when the host next looks (reconcile), unless
      // the schedule is out.
      if (status === "withdrawn" && teamAdmin && !manager) {
        tx.set(p.entry(id, teamId), this.entryDoc(team, { ...fields, status, reason: reason ?? null }));
        return;
      }
      if (!manager) throw hostOnly("Only the host decides on entries.");
      if (status === "accepted") {
        if (!division || !divId) throw new ApiError("not_found", "That division no longer exists.");
        if (!this.seedIn(tx, id, divId, division, teamId, fields.captainIds)) {
          throw new ApiError(
            "failed_precondition",
            `${divisionLabel(division as { division: Division; level: "club" })} is full (${String(division.maxTeams)} teams). Waitlist the team or raise the cap.`,
          );
        }
        tx.set(p.entry(id, teamId), this.entryDoc(team, { ...fields, status }));
        return;
      }
      tx.set(p.entry(id, teamId), this.entryDoc(team, { ...fields, status, reason: reason ?? null }));
      this.unseed(tx, id, divId, division, teamId);
    });
  }

  /** Takes a team out of its division's seeds and captains (and unconfirms the seeds). */
  private unseed(tx: Tx, id: string, divId: string | null, division: Data | null, teamId: string) {
    if (!division || !divId || !strings(division.seeds).includes(teamId)) return;
    tx.update(p.division(id, divId), {
      seeds: strings(division.seeds).filter((s) => s !== teamId),
      captains: Object.fromEntries(Object.entries(mapOf(division.captains)).filter(([k]) => k !== teamId)),
      seedsConfirmedAt: null,
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
    const format = await this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const d = await tx.get(p.division(id, divId));
      if (!d) throw noDivision();
      return this.checkGames(t, d, games);
    });
    await this.writeGames(caller, id, divId, games, format);
  }

  /**
   * Publishes every listed division's games in one go (the run sheet's
   * "Publish schedule"): each division's seeds must be confirmed, and every
   * division's games are checked before any is written.
   */
  async publishAll(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const { divisions } = parseBody(publishAllRequestSchema, body);
    const divIds = divisions.map((d) => docIdParam(d.divisionId));
    if (new Set(divIds).size !== divIds.length) throw new ApiError("invalid_argument", "Each division once.");
    const formats = await this.store.transact(async (tx) => {
      const t = await this.managed(tx, id, caller.uid);
      const out: TournamentFormat[] = [];
      for (const [i, divId] of divIds.entries()) {
        const d = await tx.get(p.division(id, divId));
        if (!d) throw noDivision();
        if (!d.seedsConfirmedAt) {
          throw new ApiError("failed_precondition", `Confirm the seeds for ${divisionLabel(d as { division: Division; level: "club" })} first.`);
        }
        out.push(this.checkGames(t, d, divisions[i].games));
      }
      return out;
    });
    for (const [i, divId] of divIds.entries()) await this.writeGames(caller, id, divId, divisions[i].games, formats[i]);
  }

  /** A schedule's games checked against the division (validGame); answers the format it plays. */
  private checkGames(t: Data, d: Data, games: Array<{ id: string; order: number; teamA: string | null; teamB: string | null; sourceA: unknown; sourceB: unknown }>): TournamentFormat {
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
    type Source = { type: string; game?: string } | null;
    games.forEach((g, i) => {
      const teamOk = (x: string | null) => x == null || seeds.includes(x);
      const sourceOk = (raw: unknown) => {
        const s = raw as Source;
        return s == null || s.type === "pool" || (!!s.game && ids.has(s.game) && s.game !== g.id);
      };
      if (g.order !== i || !teamOk(g.teamA) || !teamOk(g.teamB) || !sourceOk(g.sourceA) || !sourceOk(g.sourceB)) {
        throw new ApiError("invalid_argument", "That schedule doesn't match the division's teams. Refresh and try again.");
      }
    });
    return formatOf({ kind: t.kind as "league", season: (t.season as never) ?? null }, { settings: { format: mapOf(d.settings).format as TournamentFormat } });
  }

  /** Replaces a division's games with [games] (checked already), resets its results and schedules the event. */
  private async writeGames(
    caller: Caller,
    id: string,
    divId: string,
    games: PublishGameInput[],
    format: TournamentFormat,
  ): Promise<void> {
    const check = (tx: Tx) => this.managed(tx, id, caller.uid);
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
    await this.settle(id, divId);
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
    await this.settle(id, divId);
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
   * {scoreA, scoreB}, 0-0 to start it). Not the final: the game stays
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
    return this.keepInStep(id, divId, (tx) => this.managed(tx, id, caller.uid));
  }

  /**
   * After a final score (confirm, setScore): the same keeping in step as a
   * host looking (reconcile), done by the server, so a finished division
   * records its places and the event goes final without anyone on the page.
   * Never fails the score that was just saved.
   */
  private async settle(id: string, divId: string): Promise<void> {
    try {
      await this.keepInStep(id, divId, async (tx) => {
        const t = await tx.get(p.tournament(id));
        if (!t) throw notFound();
        return t;
      });
    } catch {
      // A host looking (reconcile) catches up anything missed.
    }
  }

  /** reconcile's work, each read of the tournament through [check] (who may do it). */
  private async keepInStep(id: string, divId: string, check: (tx: Pick<Tx, "get">) => Promise<Data>): Promise<{ changed: string[] }> {
    // Only those [check] lets through get as far as the lists (checked again below).
    const tour = await check(this.store);
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
      const t = await check(tx);
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
      if (plan.status !== statusOf(t)) tx.update(p.tournament(id), { status: plan.status, finishedAt: plan.status === "finished" ? serverTime : deleteField });
      return { changed: plan.changed };
    }).then(async (r) => {
      // The event is over: its hosts' fees go out.
      if (r.changed.includes("finished")) await this.payouts?.releaseTournament(id);
      return r;
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
