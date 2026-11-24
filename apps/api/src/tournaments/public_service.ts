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
  effectiveDeadline,
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
  isLiveGame,
  liveLimits,
  liveScoreOf,
  type LiveScoreDoc,
  type PublicFee,
  type PublicGroupTournament,
  type PublicHostedCard,
  type PublicHostedDivision,
  type PublicHostedEntry,
  type PublicHostedGame,
  type PublicHostedList,
  type PublicHostedPage,
  type PublicHostedTournament,
  type PublicLiveGame,
  publicDraftedName,
  publicHostedQuerySchema,
  type SeasonDoc,
  type SettingsDoc,
  tournamentSpots,
  tournamentVisibilities,
} from "@stall10/shared";
import { validId } from "../browse/model.js";
import { draftedLeagueTeamName, isDraftedLeagueTeam, isPrivateHost } from "../browse/visibility.js";
import { ApiError } from "../errors.js";
import { TtlCache } from "../ttl_cache.js";
import type { Data, Doc, PublicTournamentRepository } from "./public_repository.js";

/** What Find tournaments lists: published and not finished (openStatuses on the website). */
export const listedStatuses: readonly HostedStatus[] = ["registration", "seeding", "scheduled", "live"];
/** Most events in the list, as the website's useUpcomingTournaments. */
export const listMax = 50;
/**
 * Answers are kept this long in each instance, so a burst of visitors (or
 * one scraping) costs one set of reads: an event page reads up to
 * ~3,200 documents. The HTTP answers are cached for 30s anyway.
 */
export const publicCacheMs = 30_000;
/** Most events (and, separately, divisions' games) kept per instance. */
export const publicCacheMax = 200;

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

/** The running score without who kept it. */
function live(raw: unknown): LiveScoreDoc | null {
  const l = liveScoreOf(raw);
  return l
    ? { scoreA: l.scoreA, scoreB: l.scoreB, startedAt: l.startedAt?.toISOString() ?? null, updatedAt: l.updatedAt?.toISOString() ?? null }
    : null;
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
    live: live(d.data.live),
  };
}

/** An event's page without its games, as cached. */
interface EventBase {
  tournament: PublicHostedTournament;
  divisions: PublicHostedDivision[];
  entries: PublicHostedEntry[];
  /** Drafted teams' public names ("Team N"), by team id. */
  drafted: Map<string, string>;
  /** Entrants' names as visitors see them, by team id. */
  entryNames: Map<string, string>;
}

export class PublicTournamentService {
  private readonly lists: TtlCache<PublicHostedList>;
  private readonly bases: TtlCache<EventBase | null>;
  private readonly gameCache: TtlCache<PublicHostedGame[]>;

  constructor(
    private readonly repo: PublicTournamentRepository,
    private readonly now: () => number = Date.now,
  ) {
    this.lists = new TtlCache(publicCacheMs, 1, now);
    this.bases = new TtlCache(publicCacheMs, publicCacheMax, now);
    this.gameCache = new TtlCache(publicCacheMs, publicCacheMax, now);
  }

  /**
   * Hosts that are private groups, among [hostIds]: by their listing or
   * their team doc, or with either missing (isPrivateHost).
   */
  private async privateHosts(hostIds: string[]): Promise<Set<string>> {
    const valid = [...new Set(hostIds.filter((id) => validId(id)))];
    const [listings, teams] = await Promise.all([this.repo.listings(valid), this.repo.teams(valid)]);
    return new Set(hostIds.filter((id) => !validId(id) || isPrivateHost(listings.get(id), teams.get(id))));
  }

  /**
   * Upcoming published tournaments and leagues, soonest first (the
   * website's useUpcomingTournaments): ones starting from about a week ago,
   * plus leagues still running.
   */
  list(): Promise<PublicHostedList> {
    return this.lists.get("list", () => this.loadList());
  }

  private async loadList(): Promise<PublicHostedList> {
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
    const cards = shown
      .filter((d) => !hidden.has(str(d.data.hostId)))
      .map((d) => card(d.id, d.data, publishedStatus(d.data)!))
      .sort((a, b) => a.startsOn.localeCompare(b.startsOn))
      .slice(0, listMax);
    await Promise.all([
      ...cards.filter((c) => c.status === "live").map(async (c) => {
        const games = await this.liveGames(c.id, now);
        if (games.length > 0) c.liveGames = games;
      }),
      // Spots left (F10): only events open for team registration read their divisions.
      ...cards.filter((c) => c.status === "registration" && c.entryType === "teams").map(async (c) => {
        const spots = tournamentSpots(c, (await this.repo.divisions(c.id)).map((d) => d.data));
        if (spots) c.spots = spots;
      }),
    ]);
    return { tournaments: cards };
  }

  /**
   * A live event's games being played now (isLiveGame), for Discover:
   * only games updated in the last liveLimits.staleAfterMs are read, with
   * the teams' names as the event's page shows them.
   */
  private async liveGames(id: string, now: number): Promise<PublicLiveGame[]> {
    const base = await this.bases.get(id, () => this.loadBase(id));
    if (!base) return [];
    const since = new Date(now - liveLimits.staleAfterMs);
    const out: PublicLiveGame[] = [];
    for (const d of base.divisions) {
      for (const doc of await this.repo.liveGames(id, d.id, since)) {
        const g = engineGame(doc.id, doc.data);
        const l = liveScoreOf(doc.data.live);
        if (!l?.updatedAt || !g.teamA || !g.teamB || !isLiveGame({ status: g.status, live: doc.data.live }, now)) continue;
        const name = (t: string) => base.drafted.get(t) ?? base.entryNames.get(t) ?? "Team";
        out.push({
          divisionId: d.id,
          gameId: g.id,
          label: g.label,
          field: g.field,
          teamA: g.teamA,
          teamB: g.teamB,
          nameA: name(g.teamA),
          nameB: name(g.teamB),
          scoreA: l.scoreA,
          scoreB: l.scoreB,
          updatedAt: l.updatedAt.toISOString(),
        });
      }
    }
    return out.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }

  /**
   * One event's page, with [query].division's games (else the first
   * division's). The event and its games are cached separately
   * (publicCacheMs), the games by the division they resolve to, so an
   * unknown `?division=` costs no more reads than none.
   */
  async page(id: unknown, query: unknown): Promise<PublicHostedPage> {
    if (!validId(id)) throw hiddenTournament();
    const base = await this.bases.get(id, () => this.loadBase(id));
    if (!base) throw hiddenTournament();
    const { divisions, drafted, entryNames } = base;

    const { division } = publicHostedQuerySchema.parse(isRecord(query) ? query : {});
    const divisionId = (division && divisions.some((d) => d.id === division) ? division : divisions[0]?.id) ?? null;
    const games = divisionId
      ? await this.gameCache.get(`${id}/${divisionId}`, async () => (await this.repo.games(id, divisionId)).map(game))
      : [];

    // Only the teams the page shows: seeds, places and games.
    const names: Record<string, string> = {};
    const named = (teamId: string | null | undefined) => {
      if (!teamId || teamId in names) return;
      const name = drafted.get(teamId) ?? entryNames.get(teamId);
      if (name) names[teamId] = name;
    };
    for (const d of divisions) for (const x of [...d.seeds, ...d.placements]) named(x);
    for (const g of games) [g.teamA, g.teamB, g.report?.byTeam].forEach(named);

    return { tournament: base.tournament, divisions, entries: base.entries, names, divisionId, games };
  }

  /** The event's page without its games, or null when visitors can't see it. */
  private async loadBase(id: string): Promise<EventBase | null> {
    const t = await this.repo.tournament(id);
    const status = t ? publishedStatus(t) : null;
    if (!t || !status) return null;
    if ((await this.privateHosts([str(t.hostId)])).size > 0) return null;

    const [divDocs, entryDocs] = await Promise.all([this.repo.divisions(id), this.repo.entries(id)]);
    const summaries = divisionSummaries(t.divisions);
    const byId = new Map(divDocs.map((d) => [d.id, d.data]));

    // Entrants' names. A drafted league team's (`league_...`) is its
    // players', as "Team Alex - Thursday Night": never shown.
    const entryNames = new Map<string, string>();
    for (const e of entryDocs) {
      const teamName = str(e.data.teamName);
      if (teamName) entryNames.set(e.id, isDraftedLeagueTeam(e.id) ? draftedLeagueTeamName : teamName);
    }
    const taken = new Set([...entryNames].filter(([teamId]) => !isDraftedLeagueTeam(teamId)).map(([, n]) => n));

    // Drafted teams are always "Team N" for visitors, whatever they're called.
    const drafted = new Map<string, string>();
    const divisions: PublicHostedDivision[] = summaries.flatMap((s) => {
      const d = byId.get(s.id);
      if (!d) return [];
      const teams = draftedTeams(d.teams).map((x, i) => ({ id: x.id, name: publicDraftedName(i, taken) }));
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

    const entries: PublicHostedEntry[] = [];
    for (const e of entryDocs) {
      const teamName = entryNames.get(e.id);
      if (e.data.status === "accepted" && teamName) entries.push({ id: e.id, teamName, divisionId: str(e.data.divisionId), status: "accepted" });
    }

    return {
      tournament: {
        ...card(id, t, status),
        description: str(t.description),
        teamFee: fee(t.teamFee),
        season: t.kind === "league" ? season(t.season) : null,
        draftMode: oneOf(draftModes, t.draftMode, "balanced") as DraftMode,
        directorName: str((t.director as { name?: unknown } | null | undefined)?.name) || null,
        entryDeadline: effectiveDeadline(t as never)?.toISOString() ?? null,
      } satisfies PublicHostedTournament,
      divisions,
      entries: entries
        .filter((e) => divisions.some((d) => d.id === e.divisionId))
        .map((e) => ({ ...e, teamName: drafted.get(e.id) ?? e.teamName }))
        .sort((a, b) => a.teamName.localeCompare(b.teamName)),
      drafted,
      entryNames,
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
