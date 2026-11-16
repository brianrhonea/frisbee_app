// Hosted tournaments and leagues for signed-out visitors (the website's
// /tournaments pages): what `match /tournaments/{tournamentId}` in
// firebase/firestore.rules lets anyone signed in read, minus anything about
// people. The Admin SDK skips the rules, so the check is here:
//
//   visible(t) = t.status != 'draft' || manages(t)
//
// Visitors manage nothing, so a draft is hidden (also from a manager with a
// token: answers are cached publicly and never depend on who asks). On top
// of the rule, as on every visitor page (BrowseService.team, events), an
// event hosted by a private group (isPrivateGroup) is hidden too.
//
// Every answer is built field by field: no signups, drafts, payments,
// captains (uids), entry contact fields, createdBy, fee instructions or
// player names. Standings are worked out on the website from the games
// with the shared engine, as the members' page does.
import {
  competitionLevels,
  type CompetitionLevel,
  type Division,
  type DivisionSummaryDoc,
  divisions as allDivisions,
  draftedTeams,
  draftModes,
  type DraftMode,
  engineGame,
  engineSeason,
  engineSettings,
  entryTypes,
  groupTournamentFormats,
  groupTournamentStatuses,
  hostedKinds,
  hostedStatuses,
  type HostedStatus,
  type PublicFee,
  type PublicGroupTournament,
  type PublicHostedCard,
  type PublicHostedDivision,
  type PublicHostedEntry,
  type PublicHostedGame,
  type PublicHostedList,
  type PublicHostedPage,
  type PublicHostedTournament,
  publicDraftedName,
  publicHostedQuerySchema,
  type SeasonDoc,
  type SettingsDoc,
  tournamentVisibilities,
} from "@stall10/shared";
import { isPrivateGroup, validId } from "../browse/model.js";
import { ApiError } from "../errors.js";
import type { Data, Doc, PublicTournamentRepository } from "./public_repository.js";

/** What Find tournaments lists: published and not finished (openStatuses on the website). */
export const listedStatuses: readonly HostedStatus[] = ["registration", "seeding", "scheduled", "live"];
/** Most events in the list, as the website's useUpcomingTournaments. */
export const listMax = 50;

const day = 24 * 60 * 60 * 1000;
const hiddenTournament = () => new ApiError("not_found", "This event isn't here: it may have been removed, or it hasn't been published yet.");
const hiddenGroupTournament = () => new ApiError("not_found", "No such tournament.");

const str = (v: unknown, fallback = ""): string => (typeof v === "string" ? v : fallback);
const iso = (v: unknown): string | null => (typeof v === "string" && !Number.isNaN(Date.parse(v)) ? v : null);
const num = (v: unknown, fallback: number): number => (typeof v === "number" && Number.isFinite(v) ? v : fallback);
const oneOf = <T extends string>(list: readonly T[], v: unknown, fallback: T): T => (list.includes(v as T) ? (v as T) : fallback);
const ids = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
const isRecord = (v: unknown): v is Data => typeof v === "object" && v !== null && !Array.isArray(v);

/** The rule's visible() for someone who manages nothing: any status but draft (an unknown one reads as draft). */
export function publishedStatus(t: Data): HostedStatus | null {
  const s = t.status;
  return (hostedStatuses as readonly unknown[]).includes(s) && s !== "draft" ? (s as HostedStatus) : null;
}

/** The fee's amount, currency and due date; never its instructions. */
function fee(raw: unknown): PublicFee | null {
  if (!isRecord(raw) || typeof raw.amountCents !== "number") return null;
  return { amountCents: raw.amountCents, currency: str(raw.currency, "USD"), dueAt: iso(raw.dueAt) };
}

function divisionSummaries(raw: unknown): DivisionSummaryDoc[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(isRecord).flatMap((d) =>
    validId(d.id)
      ? [{ id: d.id, division: oneOf(allDivisions, d.division, "mixed") as Division, level: oneOf(competitionLevels, d.level, "club") as CompetitionLevel }]
      : [],
  );
}

function card(id: string, t: Data, status: HostedStatus): PublicHostedCard {
  return {
    id,
    hostId: str(t.hostId),
    hostName: str(t.hostName),
    hostKind: oneOf(["team", "community", "organization"] as const, t.hostKind, "team"),
    hostOfficial: t.hostOfficial === true,
    name: str(t.name),
    startsOn: iso(t.startsOn) ?? "",
    endsOn: iso(t.endsOn),
    location: str(t.location),
    visibility: oneOf(tournamentVisibilities, t.visibility, "public"),
    entryType: oneOf(entryTypes, t.entryType, "teams"),
    teamEntry: t.teamEntry === true,
    kind: oneOf(hostedKinds, t.kind, "tournament"),
    status,
    bidFee: fee(t.bidFee),
    divisions: divisionSummaries(t.divisions),
  };
}

/** Settings as stored, with the app's defaults, dates as ISO strings. */
function settings(raw: unknown): SettingsDoc {
  const s = engineSettings(raw);
  return {
    ...s,
    startsAt: s.startsAt.toISOString(),
    idealEndsAt: s.idealEndsAt?.toISOString() ?? null,
    laterDays: s.laterDays.map((d) => d.toISOString()),
  };
}

function season(raw: unknown): SeasonDoc | null {
  const s = engineSeason(raw);
  return s ? { ...s, skipDates: s.skipDates.map((d) => d.toISOString()) } : null;
}

function game(d: Doc): PublicHostedGame {
  const g = engineGame(d.id, d.data);
  return {
    id: g.id,
    order: g.order,
    stage: g.stage,
    round: g.round,
    label: g.label,
    pool: g.pool,
    field: g.field,
    startsAt: g.startsAt?.toISOString() ?? null,
    teamA: g.teamA,
    teamB: g.teamB,
    sourceA: g.sourceA,
    sourceB: g.sourceB,
    status: g.status,
    scoreA: g.scoreA,
    scoreB: g.scoreB,
    report: g.report ? { scoreA: g.report.scoreA, scoreB: g.report.scoreB, byTeam: g.report.byTeam } : null,
    ifNeeded: g.ifNeeded,
    place: g.place ?? null,
  };
}

export class PublicTournamentService {
  constructor(
    private readonly repo: PublicTournamentRepository,
    private readonly now: () => number = Date.now,
  ) {}

  /** Hosts that are private groups (or have no listing), among [hostIds]. */
  private async privateHosts(hostIds: string[]): Promise<Set<string>> {
    const valid = [...new Set(hostIds.filter((id) => validId(id)))];
    const listings = await this.repo.listings(valid);
    return new Set(hostIds.filter((id) => !validId(id) || isPrivateGroup(listings.get(id))));
  }

  /**
   * Upcoming published tournaments and leagues, soonest first (the
   * website's useUpcomingTournaments): ones starting from about a week ago,
   * plus leagues still running.
   */
  async list(): Promise<PublicHostedList> {
    const now = this.now();
    const [starting, running] = await Promise.all([
      this.repo.startingFrom(listedStatuses, new Date(now - 8 * day), listMax),
      // As on the website: without its index yet, this query fails and the first still lists the rest.
      this.repo.endingFrom(listedStatuses, new Date(now - day), listMax).catch(() => [] as Doc[]),
    ]);
    const byId = new Map<string, Doc>();
    for (const d of [...starting, ...running]) byId.set(d.id, d);
    const shown = [...byId.values()].filter((d) => listedStatuses.includes(publishedStatus(d.data) as HostedStatus));
    const hidden = await this.privateHosts(shown.map((d) => str(d.data.hostId)));
    return {
      tournaments: shown
        .filter((d) => !hidden.has(str(d.data.hostId)))
        .map((d) => card(d.id, d.data, publishedStatus(d.data)!))
        .sort((a, b) => a.startsOn.localeCompare(b.startsOn))
        .slice(0, listMax),
    };
  }

  /** One event's page, with [query].division's games (else the first division's). */
  async page(id: unknown, query: unknown): Promise<PublicHostedPage> {
    if (!validId(id)) throw hiddenTournament();
    const t = await this.repo.tournament(id);
    const status = t ? publishedStatus(t) : null;
    if (!t || !status) throw hiddenTournament();
    if ((await this.privateHosts([str(t.hostId)])).size > 0) throw hiddenTournament();

    const [divDocs, entryDocs] = await Promise.all([this.repo.divisions(id), this.repo.entries(id)]);
    const summaries = divisionSummaries(t.divisions);
    const byId = new Map(divDocs.map((d) => [d.id, d.data]));
    const drafted = new Map<string, string>();
    const divisions: PublicHostedDivision[] = summaries.flatMap((s) => {
      const d = byId.get(s.id);
      if (!d) return [];
      const teams = draftedTeams(d.teams).map((x, i) => ({ id: x.id, name: publicDraftedName(x.name, Object.values(x.playerNames), i) }));
      for (const x of teams) if (x.id) drafted.set(x.id, x.name);
      return [
        {
          id: s.id,
          division: oneOf(allDivisions, d.division, s.division) as Division,
          level: oneOf(competitionLevels, d.level, s.level) as CompetitionLevel,
          settings: settings(d.settings),
          maxTeams: num(d.maxTeams, 8),
          minRoster: typeof d.minRoster === "number" ? d.minRoster : null,
          seeds: ids(d.seeds),
          placements: ids(d.placements),
          teams: teams.filter((x) => x.id),
        },
      ];
    });

    const { division } = publicHostedQuerySchema.parse(isRecord(query) ? query : {});
    const divisionId = (division && divisions.some((d) => d.id === division) ? division : divisions[0]?.id) ?? null;
    const games = divisionId ? (await this.repo.games(id, divisionId)).map(game) : [];

    const entryNames = new Map<string, string>();
    const entries: PublicHostedEntry[] = [];
    for (const e of entryDocs) {
      const teamName = str(e.data.teamName);
      if (teamName) entryNames.set(e.id, teamName);
      if (e.data.status === "accepted" && teamName) entries.push({ id: e.id, teamName, divisionId: str(e.data.divisionId), status: "accepted" });
    }
    // Only the teams the page shows: seeds, places and games.
    const names: Record<string, string> = {};
    const named = (teamId: string | null | undefined) => {
      if (!teamId || teamId in names) return;
      const name = drafted.get(teamId) ?? entryNames.get(teamId);
      if (name) names[teamId] = name;
    };
    for (const d of divisions) for (const x of [...d.seeds, ...d.placements]) named(x);
    for (const g of games) [g.teamA, g.teamB, g.report?.byTeam].forEach(named);

    return {
      tournament: {
        ...card(id, t, status),
        description: str(t.description),
        teamFee: fee(t.teamFee),
        season: t.kind === "league" ? season(t.season) : null,
        draftMode: oneOf(draftModes, t.draftMode, "balanced") as DraftMode,
      } satisfies PublicHostedTournament,
      divisions,
      entries: entries
        .filter((e) => divisions.some((d) => d.id === e.divisionId))
        .map((e) => ({ ...e, teamName: drafted.get(e.id) ?? e.teamName }))
        .sort((a, b) => a.teamName.localeCompare(b.teamName)),
      names,
      divisionId,
      games,
    };
  }

  /** A community group's tournament as outsiders see it (its tournamentDirectory listing), unless the group is private. */
  async groupTournament(groupId: unknown, tournamentId: unknown): Promise<PublicGroupTournament> {
    if (!validId(groupId) || !validId(tournamentId)) throw hiddenGroupTournament();
    const d = await this.repo.groupListing(`${groupId}_${tournamentId}`);
    if (!d || d.groupId !== groupId || d.tournamentId !== tournamentId) throw hiddenGroupTournament();
    if ((await this.privateHosts([groupId])).size > 0) throw hiddenGroupTournament();
    return {
      groupId,
      tournamentId,
      name: str(d.name),
      startsAt: iso(d.startsAt) ?? "",
      endsOn: iso(d.endsOn),
      status: oneOf(groupTournamentStatuses, d.status, "setup"),
      format: oneOf(groupTournamentFormats, d.format, "poolsSingleElim"),
    };
  }
}
