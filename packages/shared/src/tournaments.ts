// Hosted tournaments and leagues (tournaments/{id}, HostedTournament in
// apps/mobile/lib/domain/models/hosted_tournament.dart): limits from
// firestore.rules, the requests the website sends the API, the documents
// as the website reads them, and the app's pure helpers (formats, labels,
// division and entry logic).
import { z } from "zod";
import { clean } from "./word_filter.js";
import { type CompetitionLevel, competitionLevels, type Division, divisions } from "./team.js";
import {
  type EngineGame,
  type EngineSeason,
  type EngineSettings,
  type GameStage,
  gameStages,
  type GameStatus,
  gameStatuses,
  type ScoringMode,
  scoringModes,
  type SlotSource,
  type TournamentFormat,
  tournamentFormats,
} from "./tournament_engine.js";

export const hostedStatuses = ["draft", "registration", "seeding", "scheduled", "live", "finished"] as const;
export type HostedStatus = (typeof hostedStatuses)[number];
export const hostedStatusLabels: Record<HostedStatus, string> = {
  draft: "Draft",
  registration: "Registration open",
  seeding: "Seeding",
  scheduled: "Scheduled",
  live: "Live",
  finished: "Final",
};
export const statusIndex = (s: HostedStatus) => hostedStatuses.indexOf(s);

/**
 * Where an organizer can move an event's status by hand (PUT .../status):
 * open registration, close it for seeding or reopen it, back to a draft
 * while registration is open. Publishing a schedule, the first live score
 * and the last result move it on by themselves (scheduled, live,
 * finished); an organizer can also end an event being played, or reopen a
 * finished one to correct it.
 */
export const statusMoves: Record<HostedStatus, readonly HostedStatus[]> = {
  draft: ["registration"],
  registration: ["seeding", "draft"],
  seeding: ["registration"],
  scheduled: ["live"],
  live: ["finished"],
  finished: ["live"],
};
/** Whether an organizer may move an event from [from] to [to] by hand (staying put is fine). */
export const canMoveStatus = (from: HostedStatus, to: HostedStatus) => from === to || statusMoves[from].includes(to);
export const publishedStatuses = hostedStatuses.filter((s) => s !== "draft");

export const tournamentVisibilities = ["public", "inviteOnly"] as const;
export type TournamentVisibility = (typeof tournamentVisibilities)[number];
export const visibilityLabels: Record<TournamentVisibility, { label: string; summary: string }> = {
  public: { label: "Public", summary: "Any team can apply" },
  inviteOnly: { label: "Invite only", summary: "Only teams you invite can play" },
};

export const entryTypes = ["teams", "players"] as const;
export type TournamentEntryType = (typeof entryTypes)[number];
export const hostedKinds = ["tournament", "league"] as const;
export type HostedKind = (typeof hostedKinds)[number];
export const draftModes = ["balanced", "captains"] as const;
export type DraftMode = (typeof draftModes)[number];
export const draftModeLabels: Record<DraftMode, { label: string; summary: string }> = {
  balanced: { label: "Balanced teams", summary: "Teams are dealt automatically, evened by skill" },
  captains: { label: "Captains draft", summary: "Captains take turns picking players" },
};

export type HostedType = "tournament" | "hat" | "league";
export const hostedTypeLabels: Record<HostedType, string> = { tournament: "Tournament", hat: "Hat tournament", league: "League" };

export const entryStatuses = ["invited", "applied", "accepted", "waitlisted", "declined", "withdrawn"] as const;
export type EntryStatus = (typeof entryStatuses)[number];
export const entryStatusLabels: Record<EntryStatus, string> = {
  invited: "Invited",
  applied: "Applied",
  accepted: "Accepted",
  waitlisted: "Waitlist",
  declined: "Declined",
  withdrawn: "Withdrawn",
};

export const divisionLabels: Record<Division, string> = { mixed: "Mixed", open: "Open", women: "Women", masters: "Masters" };
export const levelLabels: Record<CompetitionLevel, string> = {
  club: "Club",
  college: "College",
  youth: "Youth",
  league: "League",
  pickup: "Pickup",
};

/** The rules' and the app's limits. */
/**
 * The organizer's reply-by choices for invites, in days before the event
 * starts (HostedTournament.inviteReplyChoices in the app): 2 weeks is the
 * usual. No deadline is null.
 */
export const inviteReplyChoices = [3, 7, 14, 21, 30] as const;
/** What a new event starts with. */
export const defaultInviteReplyDays = 14;
/** A reply-by choice as the form shows it, e.g. "2 weeks before it starts"; null: "No deadline". */
export function inviteReplyLabel(days: number | null): string {
  if (!days) return "No deadline";
  const span = days % 7 === 0 ? (days === 7 ? "1 week" : `${days / 7} weeks`) : `${days} days`;
  return `${span} before it starts`;
}
/** The least time a team gets to answer an invite, however late it's sent. */
export const inviteMinReplyMs = 2 * 24 * 60 * 60 * 1000;

/**
 * When a team invited at [now] must answer by: [days] before [startsOn],
 * but at least two days after the invite (inviteMinReplyMs), unless the
 * event starts sooner: then by its start. Null when the event has no deadline.
 * HostedTournament.inviteReplyBy in the app.
 */
export function inviteReplyBy(startsOn: Date, days: number | null | undefined, now: Date): Date | null {
  if (!days || days <= 0) return null;
  const due = startsOn.getTime() - days * 24 * 60 * 60 * 1000;
  const earliest = now.getTime() + inviteMinReplyMs;
  return new Date(Math.min(Math.max(due, earliest), startsOn.getTime()));
}

/** Whether an entry is an invite nobody answered by its reply-by time. */
export function inviteExpired(entry: { status: string; replyBy?: Date | string | null }, now: Date): boolean {
  if (entry.status !== "invited" || !entry.replyBy) return false;
  const by = entry.replyBy instanceof Date ? entry.replyBy.getTime() : Date.parse(entry.replyBy);
  return !Number.isNaN(by) && now.getTime() > by;
}

/** Shown when an invite's reply-by time has passed. */
export const inviteExpiredMessage = "This invite has expired. Ask the organizers to invite your team again.";

/** A team's open invite (GET /v1/teams/:teamId/tournament-invites), for its admins. */
export interface TeamTournamentInvite {
  tournamentId: string;
  name: string;
  hostName: string;
  kind: HostedKind;
  startsOn: string;
  endsOn: string | null;
  location: string;
  divisionId: string;
  divisionLabel: string;
  replyBy: string | null;
  expired: boolean;
}

/**
 * One of a team's entries still missing its roster or fee before the event
 * (GET /v1/teams/:teamId/tournament-invites, `toFinish`): the team page's
 * "Finish entry", for its admins.
 */
export interface TeamEntryToFinish {
  tournamentId: string;
  name: string;
  hostName: string;
  startsOn: string;
  divisionLabel: string;
  status: EntryStatus;
  rosterSet: boolean;
  /** Paid, or nothing to pay. */
  paid: boolean;
  /** When the roster and fee are due (effectiveDeadline). */
  deadline: string | null;
  overdue: boolean;
}

/** GET /v1/teams/:teamId/tournament-invites */
export interface TeamTournamentInvitesResult {
  invites: TeamTournamentInvite[];
  toFinish: TeamEntryToFinish[];
}

export const tournamentLimits = {
  name: 100,
  hostName: 100,
  description: 2000,
  location: 200,
  feeInstructions: 500,
  maxCents: 10_000_000,
  maxDivisions: 12,
  maxWeeks: 26,
  maxPlayoffWeeks: 3,
  playoffSizes: [0, 2, 4, 8] as const,
  maxGamesPerNight: 2,
  maxSkipDates: 10,
  minTeams: 2,
  maxTeams: 64,
  minRoster: 2,
  maxMinRoster: 30,
  defaultMinRoster: 7,
  maxDraftedTeams: 32,
  maxCaptainsMap: 64,
  maxPlacements: 64,
  maxCaptains: 4,
  teamName: 100,
  divisionId: 100,
  gameLabel: 60,
  maxScore: 99,
  maxPlace: 64,
  /** Games one schedule can have (a 64-team round robin is 2016). */
  maxGames: 2100,
  fieldSizes: [3, 4, 5, 6, 7] as const,
  teamCaps: [4, 6, 8, 10, 12, 16, 20, 24, 32] as const,
  maxLaterDays: 6,
  /** Players a team can name for one event (its tournament roster). */
  maxEventRoster: 60,
  directorName: 100,
  directorEmail: 200,
  directorPhone: 40,
} as const;

export const currencies = ["USD", "CAD", "EUR", "GBP", "AUD", "MXN"] as const;

// ---- Requests ----------------------------------------------------------------

const isoDate = z.iso.datetime({ offset: true }).transform((s) => new Date(s));

const feeSchema = z.strictObject({
  amountCents: z.number().int().min(0).max(tournamentLimits.maxCents),
  currency: z.string().regex(/^[A-Z]{3}$/, "Pick a currency."),
  instructions: z.string().trim().max(tournamentLimits.feeInstructions).default(""),
  dueAt: isoDate.nullable().default(null),
  /**
   * Unused: paid online, the payer always pays Stripe's and Stall 10's
   * fees on top (onlineCharge). Kept so older events' fees still parse.
   */
  payerCoversFees: z.boolean().default(false),
});

export const seasonSchema = z
  .strictObject({
    weeks: z.number().int().min(1).max(tournamentLimits.maxWeeks),
    playoffWeeks: z.number().int().min(0).max(tournamentLimits.maxPlayoffWeeks),
    playoffTeams: z.union(tournamentLimits.playoffSizes.map((n) => z.literal(n)) as [z.ZodLiteral<0>, z.ZodLiteral<2>, z.ZodLiteral<4>, z.ZodLiteral<8>]),
    gamesPerNight: z.number().int().min(1).max(tournamentLimits.maxGamesPerNight),
    skipDates: z.array(isoDate).max(tournamentLimits.maxSkipDates).default([]),
  })
  .refine((s) => s.playoffWeeks <= s.weeks, { message: "The playoffs can't be longer than the season.", path: ["playoffWeeks"] });

export const settingsSchema = z.strictObject({
  format: z.enum(tournamentFormats),
  playersOnField: z.number().int().min(3).max(7),
  poolCount: z.number().int().min(1).max(16),
  gameMinutes: z.number().int().min(5).max(240),
  breakMinutes: z.number().int().min(0).max(120),
  scoreCap: z.number().int().min(1).max(50),
  timeoutsPerHalf: z.number().int().min(0).max(10),
  fields: z.number().int().min(1).max(32),
  startsAt: isoDate,
  idealEndsAt: isoDate.nullable().default(null),
  laterDays: z.array(isoDate).max(tournamentLimits.maxLaterDays).default([]),
  scoring: z.enum(scoringModes).default("points"),
});

export const formatSchema = z.strictObject({
  settings: settingsSchema,
  level: z.enum(competitionLevels),
  maxTeams: z.number().int().min(tournamentLimits.minTeams).max(tournamentLimits.maxTeams),
  minRoster: z.number().int().min(tournamentLimits.minRoster).max(tournamentLimits.maxMinRoster).nullable().default(null),
});

/**
 * The tournament director: the main contact for questions and logistics.
 * A Stall 10 member (uid, with their name copied for display) or anyone,
 * by name with an optional email and phone. Not an organizer: they get no
 * rights over the event unless they also manage it.
 */
export const directorSchema = z.strictObject({
  uid: z.string().min(1).max(128).nullable().default(null),
  name: clean(z.string().trim().min(1, "Give the director's name.").max(tournamentLimits.directorName)),
  email: z.union([z.literal(""), z.email("Enter a valid email.").max(tournamentLimits.directorEmail)]).default(""),
  phone: z
    .string()
    .trim()
    .max(tournamentLimits.directorPhone)
    .regex(/^[+()\-.\s\d]*$/, "Enter a valid phone number.")
    .default(""),
});
export type DirectorInput = z.output<typeof directorSchema>;

const detailsShape = {
  name: clean(z.string().trim().min(1, "Give it a name.").max(tournamentLimits.name)),
  description: clean(z.string().trim().max(tournamentLimits.description).default("")),
  location: clean(z.string().trim().max(tournamentLimits.location).default("")),
  startsOn: isoDate,
  endsOn: isoDate.nullable().default(null),
  visibility: z.enum(tournamentVisibilities),
  bidFee: feeSchema.nullable().default(null),
  teamEntry: z.boolean().default(false),
  teamFee: feeSchema.nullable().default(null),
  season: seasonSchema.nullable().default(null),
  draftMode: z.enum(draftModes).default("balanced"),
  /**
   * How many days before it starts invited teams must answer by (inviteReplyBy);
   * null: no deadline. One of inviteReplyChoices.
   */
  inviteReplyDays: z
    .number()
    .int()
    .refine((n) => (inviteReplyChoices as readonly number[]).includes(n), "Pick a reply-by choice.")
    .nullable()
    .default(null),
  /**
   * When teams must have their roster set and fee paid, and players their
   * fee (effectiveDeadline); null: the fee's due date, else the day before
   * it starts. The fees' due dates follow it.
   */
  entryDeadline: isoDate.nullable().default(null),
  /** The tournament director (directorSchema), or none. */
  director: directorSchema.nullable().default(null),
  format: formatSchema,
  /** The divisions to have open (one per gender division). */
  divisions: z
    .array(z.enum(divisions))
    .min(1, "Open at least one division.")
    .max(tournamentLimits.maxDivisions)
    .refine((l) => new Set(l).size === l.length, "Each division once."),
};

/** POST /v1/tournaments: host a tournament or league as [hostId]. */
export const createTournamentRequestSchema = z.strictObject({
  hostId: z.string().min(1).max(128),
  kind: z.enum(hostedKinds),
  entryType: z.enum(entryTypes),
  /** Enter the host team in its own event (accepted, in the division matching its own; no fee). Teams-entry events only. */
  enterHost: z.boolean().optional(),
  ...detailsShape,
});
export type CreateTournamentInput = z.output<typeof createTournamentRequestSchema>;

/** PATCH /v1/tournaments/:id: everything but the host, kind and entry type, which are fixed. */
export const saveTournamentRequestSchema = z.strictObject(detailsShape);
export type SaveTournamentInput = z.output<typeof saveTournamentRequestSchema>;

/** PUT /v1/tournaments/:id/status */
export const tournamentStatusRequestSchema = z.strictObject({ status: z.enum(hostedStatuses) });

/** PUT /v1/tournaments/:id/divisions/:divisionId/seeds: the accepted teams, reordered. */
export const seedsRequestSchema = z.strictObject({
  seeds: z.array(z.string().min(1).max(128)).max(tournamentLimits.maxTeams),
  /** The host confirms these are the seeds (seedsConfirmedAt); without it, saving a change unconfirms them. */
  confirm: z.boolean().optional(),
});

/** PUT /v1/tournaments/:id/schedule: publish every listed division's games at once. */
export const publishAllRequestSchema = z.strictObject({
  divisions: z
    .array(z.strictObject({ divisionId: z.string().min(1).max(tournamentLimits.divisionId), games: z.array(z.lazy(() => publishGameSchema)).min(1).max(tournamentLimits.maxGames) }))
    .min(1)
    .max(tournamentLimits.maxDivisions),
});


/** PUT /v1/tournaments/:id/entries/:teamId: a team admin applies, accepts an invite or changes captains. */
export const entryRequestSchema = z.strictObject({
  divisionId: z.string().min(1).max(tournamentLimits.divisionId),
  captainIds: z
    .array(z.string().min(1).max(128))
    .min(1, "Pick at least one captain.")
    .max(tournamentLimits.maxCaptains, `Pick up to ${tournamentLimits.maxCaptains} captains.`),
});

/**
 * PUT /v1/tournaments/:id/entries/:teamId/roster: the players (ids of the
 * team's roster, teams/{id}/roster) a team brings to this event.
 */
export const entryRosterRequestSchema = z.strictObject({
  playerIds: z
    .array(z.string().min(1).max(128))
    .max(tournamentLimits.maxEventRoster, `Up to ${tournamentLimits.maxEventRoster} players.`)
    .refine((l) => new Set(l).size === l.length, "Each player once."),
});

/**
 * What PUT .../entries/:teamId answers: the entry's status after it. An
 * invite taken up is accepted (waitlisted when the division is full); an
 * application waits as applied.
 */
export interface EntryAnswer {
  status: EntryStatus;
}

/** POST /v1/tournaments/:id/entries/:teamId/invite: the host invites a team. */
export const inviteRequestSchema = z.strictObject({ divisionId: z.string().min(1).max(tournamentLimits.divisionId) });

/** PUT /v1/tournaments/:id/entries/:teamId/status: the host decides, or the team withdraws. */
export const entryStatusRequestSchema = z.strictObject({
  status: z.enum(["accepted", "waitlisted", "declined", "withdrawn"]),
  /** A team withdrawing because it turned the invite down, so organizers see why. */
  reason: z.enum(["declined"]).optional(),
});

/** Why a team withdrew, when it said (entries/{id}.reason). */
export const entryReasons = ["declined"] as const;
export type EntryReason = (typeof entryReasons)[number];

/** Scores a captain reports, the other captain confirms (the score they saw) or the host sets. */
export const scoreRequestSchema = z
  .strictObject({
    scoreA: z.number().int().min(0).max(tournamentLimits.maxScore),
    scoreB: z.number().int().min(0).max(tournamentLimits.maxScore),
  })
  .refine((s) => s.scoreA !== s.scoreB, { message: "Games can't end in a tie.", path: ["scoreB"] });

// ---- Live running scores -------------------------------------------------------
//
// While a game is played, either team's captain or the host's event managers
// keep its running score (`games/{id}.live`, written only by the API:
// POST /v1/tournaments/:id/divisions/:divisionId/games/:gameId/live). It's
// never the final: the game stays `scheduled` with no scoreA/scoreB, so the
// engine, standings and brackets ignore it, and the final still goes through
// report → confirm (or the host's set score). A game is live while it's
// scheduled and its running score was updated in the last
// liveLimits.staleAfterMs (the app and older clients can't clear it).

/** POST .../games/:gameId/live: the running score (0–0 starts the game; ties are fine). */
export const liveScoreRequestSchema = z.strictObject({
  scoreA: z.number().int().min(0).max(tournamentLimits.maxScore),
  scoreB: z.number().int().min(0).max(tournamentLimits.maxScore),
});
export type LiveScoreRequest = z.infer<typeof liveScoreRequestSchema>;

export const liveLimits = {
  /** A running score not updated for this long no longer shows as live. */
  staleAfterMs: 3 * 60 * 60 * 1000,
  /** How early before its start time a game can go live. */
  earlyMs: 2 * 60 * 60 * 1000,
  /** How long after its start time a game can still go live or be updated. */
  lateMs: 24 * 60 * 60 * 1000,
  /** Running-score updates per person per minute (their own bucket). */
  perMinute: 60,
} as const;

/** games/{id}.live as stored (dates as ISO strings for the website). `by` is the uid of whoever updated it last. */
export interface LiveScoreDoc {
  scoreA: number;
  scoreB: number;
  startedAt: string | null;
  updatedAt: string | null;
  /** Never in public answers. */
  by?: string;
}

/** A stored `live` map (Date or ISO dates) → its scores and times, or null. */
export function liveScoreOf(raw: unknown): { scoreA: number; scoreB: number; startedAt: Date | null; updatedAt: Date | null; by: string | null } | null {
  if (!raw || typeof raw !== "object") return null;
  const m = raw as Record<string, unknown>;
  if (typeof m.scoreA !== "number" || typeof m.scoreB !== "number") return null;
  return {
    scoreA: m.scoreA,
    scoreB: m.scoreB,
    startedAt: dateOf(m.startedAt),
    updatedAt: dateOf(m.updatedAt),
    by: typeof m.by === "string" ? m.by : null,
  };
}

/**
 * Whether a game is being played right now: still scheduled (no score
 * reported or final) with a running score updated within
 * liveLimits.staleAfterMs of [now]. Mirrored by GroupGame.liveAt in the app.
 */
export function isLiveGame(g: { status: string; live?: unknown }, now: Date | number): boolean {
  if (g.status !== "scheduled") return false;
  const live = liveScoreOf(g.live);
  if (!live?.updatedAt) return false;
  const t = typeof now === "number" ? now : now.getTime();
  return t - live.updatedAt.getTime() <= liveLimits.staleAfterMs;
}

/**
 * Whether a game starting at [startsAt] can take a running score at [now]:
 * from liveLimits.earlyMs before its start to liveLimits.lateMs after
 * (time zone free, so "today" wherever it's played). Games without a time can.
 */
export function inLiveWindow(startsAt: Date | null, now: Date | number): boolean {
  if (!startsAt) return true;
  const t = typeof now === "number" ? now : now.getTime();
  const at = startsAt.getTime();
  return t >= at - liveLimits.earlyMs && t <= at + liveLimits.lateMs;
}

const sourceSchema = z.union([
  z.strictObject({ type: z.literal("winner"), game: z.string().min(1).max(128) }),
  z.strictObject({ type: z.literal("loser"), game: z.string().min(1).max(128) }),
  z.strictObject({ type: z.literal("pool"), pool: z.string().min(1).max(4), rank: z.number().int().min(1).max(64) }),
]);

/** One generated game (GroupGame.toMap) as the website sends it to publish. */
export const publishGameSchema = z.strictObject({
  id: z.string().regex(/^g\d{3,4}$/),
  order: z.number().int().min(0).max(tournamentLimits.maxGames),
  stage: z.enum(gameStages),
  round: z.number().int().min(1).max(200),
  label: z.string().max(tournamentLimits.gameLabel),
  pool: z.string().min(1).max(4).nullable(),
  field: z.number().int().min(1).max(32),
  startsAt: isoDate.nullable(),
  teamA: z.string().min(1).max(128).nullable(),
  teamB: z.string().min(1).max(128).nullable(),
  sourceA: sourceSchema.nullable(),
  sourceB: sourceSchema.nullable(),
  ifNeeded: z.boolean(),
  place: z.number().int().min(1).max(tournamentLimits.maxPlace).nullable().optional(),
});

export type PublishGameInput = z.output<typeof publishGameSchema>;

/** PUT /v1/tournaments/:id/divisions/:divisionId/schedule: publish (or regenerate) the games. */
export const publishScheduleRequestSchema = z.strictObject({
  games: z.array(publishGameSchema).min(1).max(tournamentLimits.maxGames),
});

// ---- Documents as the website reads them (timestamps as ISO strings) ---------

export interface FeeDoc {
  amountCents: number;
  currency: string;
  instructions: string;
  dueAt: string | null;
  /** Paid online, the payer also pays the fees (missing on older events: false). */
  payerCoversFees?: boolean;
}
export interface SeasonDoc {
  weeks: number;
  playoffWeeks: number;
  playoffTeams: number;
  gamesPerNight: number;
  skipDates: string[];
}
export interface SettingsDoc {
  format: TournamentFormat;
  playersOnField: number;
  poolCount: number;
  gameMinutes: number;
  breakMinutes: number;
  scoreCap: number;
  timeoutsPerHalf: number;
  fields: number;
  startsAt: string;
  idealEndsAt: string | null;
  laterDays: string[];
  scoring: ScoringMode;
}
export interface FormatDoc {
  settings: SettingsDoc;
  level: CompetitionLevel;
  maxTeams: number;
  minRoster: number | null;
}
export interface DivisionSummaryDoc {
  id: string;
  division: Division;
  level: CompetitionLevel;
}
export interface TournamentDoc {
  hostId: string;
  hostName: string;
  hostKind: "team" | "community" | "organization";
  hostOfficial?: boolean;
  name: string;
  startsOn: string;
  endsOn: string | null;
  description: string;
  location: string;
  visibility: TournamentVisibility;
  entryType: TournamentEntryType;
  status: HostedStatus;
  bidFee: FeeDoc | null;
  teamEntry?: boolean;
  teamFee?: FeeDoc | null;
  kind?: HostedKind;
  season?: SeasonDoc | null;
  draftMode?: DraftMode;
  /** Days before the start invited teams answer by (inviteReplyBy), or none. */
  inviteReplyDays?: number | null;
  /** Rosters and fees due by (effectiveDeadline), or none set. */
  entryDeadline?: string | null;
  /** The tournament director. Email and phone are only sent to signed-in people. */
  director?: DirectorDoc | null;
  divisions: DivisionSummaryDoc[];
  format?: FormatDoc | null;
  createdBy?: string;
  createdAt?: string;
}
export interface DirectorDoc {
  uid: string | null;
  name: string;
  email: string;
  phone: string;
}
export interface DraftedTeamDoc {
  id: string;
  name: string;
  captainId: string | null;
  playerIds: string[];
  playerNames: Record<string, string>;
}
export interface DivisionDoc {
  division: Division;
  level: CompetitionLevel;
  settings: SettingsDoc;
  maxTeams: number;
  seeds: string[];
  captains: Record<string, string[]>;
  placements: string[];
  minRoster: number | null;
  teams?: DraftedTeamDoc[];
  /** When the host confirmed the seeds; any change to them clears it. */
  seedsConfirmedAt?: string | null;
}
export interface EntryDoc {
  teamName: string;
  divisionId: string;
  status: EntryStatus;
  captainIds: string[];
  /** The team's id (the doc's id too), so a team's invites can be found. */
  teamId?: string;
  /** An invite's answer-by time (inviteReplyBy); past it, it's expired (inviteExpired). */
  replyBy?: string | null;
  /** The players the team brings (ids of teams/{id}/roster), once set. */
  roster?: string[];
  rosterSetAt?: string | null;
  /** Why a team withdrew, if it said. */
  reason?: EntryReason | null;
  updatedAt?: string;
}
export interface GameDoc {
  order: number;
  stage: GameStage;
  round: number;
  label: string;
  pool: string | null;
  field: number;
  startsAt: string | null;
  teamA: string | null;
  teamB: string | null;
  sourceA: SlotSource | null;
  sourceB: SlotSource | null;
  status: GameStatus;
  scoreA: number | null;
  scoreB: number | null;
  report: { scoreA: number; scoreB: number; byTeam: string } | null;
  ifNeeded: boolean;
  place?: number | null;
  /** The running score while it's played (see isLiveGame); not the final. */
  live?: LiveScoreDoc | null;
}
/** teams/{teamId}/tournamentEntries/{tournamentId}, kept by the server. */
export interface EnteredTournamentDoc {
  name: string;
  hostId: string;
  hostName: string;
  startsOn: string | null;
  endsOn: string | null;
  location: string;
  status: EntryStatus;
}

// ---- Helpers (the app's model getters) ---------------------------------------

const dateOf = (v: unknown): Date | null => {
  if (v instanceof Date) return v;
  if (typeof v === "string" && !Number.isNaN(Date.parse(v))) return new Date(v);
  return null;
};
const num = (v: unknown, fallback: number) => (typeof v === "number" && Number.isFinite(v) ? v : fallback);
const strOrNull = (v: unknown) => (typeof v === "string" ? v : null);

/** Settings as stored (Date or ISO dates) → the engine's, with the app's defaults. */
export function engineSettings(raw: unknown): EngineSettings {
  const m = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  return {
    format: (tournamentFormats as readonly string[]).includes(m.format as string) ? (m.format as TournamentFormat) : "poolsSingleElim",
    playersOnField: num(m.playersOnField, 5),
    poolCount: num(m.poolCount, 2),
    gameMinutes: num(m.gameMinutes, 40),
    breakMinutes: num(m.breakMinutes, 10),
    scoreCap: num(m.scoreCap, 11),
    timeoutsPerHalf: num(m.timeoutsPerHalf, 1),
    fields: num(m.fields, 1),
    startsAt: dateOf(m.startsAt) ?? new Date(1970, 0, 1),
    idealEndsAt: dateOf(m.idealEndsAt),
    laterDays: Array.isArray(m.laterDays) ? m.laterDays.map(dateOf).filter((d): d is Date => d != null) : [],
    scoring: m.scoring === "time" ? "time" : "points",
  };
}

export function engineSeason(raw: unknown): EngineSeason | null {
  if (!raw || typeof raw !== "object") return null;
  const m = raw as Record<string, unknown>;
  const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);
  return {
    weeks: clamp(num(m.weeks, 8), 1, tournamentLimits.maxWeeks),
    playoffWeeks: clamp(num(m.playoffWeeks, 0), 0, tournamentLimits.maxPlayoffWeeks),
    playoffTeams: num(m.playoffTeams, 0),
    gamesPerNight: clamp(num(m.gamesPerNight, 1), 1, tournamentLimits.maxGamesPerNight),
    skipDates: Array.isArray(m.skipDates) ? m.skipDates.map(dateOf).filter((d): d is Date => d != null) : [],
  };
}

/** A stored game (Date or ISO dates) → the engine's. */
export function engineGame(id: string, raw: unknown): EngineGame {
  const m = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const src = (v: unknown): SlotSource | null => {
    if (!v || typeof v !== "object") return null;
    const s = v as Record<string, unknown>;
    if (s.type === "winner" || s.type === "loser") return { type: s.type, game: String(s.game ?? "") };
    if (s.type === "pool") return { type: "pool", pool: String(s.pool ?? ""), rank: num(s.rank, 1) };
    return null;
  };
  const r = m.report && typeof m.report === "object" ? (m.report as Record<string, unknown>) : null;
  return {
    id,
    order: num(m.order, 0),
    stage: (gameStages as readonly string[]).includes(m.stage as string) ? (m.stage as GameStage) : "pool",
    round: num(m.round, 1),
    label: typeof m.label === "string" ? m.label : "",
    pool: strOrNull(m.pool),
    field: num(m.field, 1),
    startsAt: dateOf(m.startsAt),
    teamA: strOrNull(m.teamA),
    teamB: strOrNull(m.teamB),
    sourceA: src(m.sourceA),
    sourceB: src(m.sourceB),
    status: (gameStatuses as readonly string[]).includes(m.status as string) ? (m.status as GameStatus) : "scheduled",
    scoreA: typeof m.scoreA === "number" ? m.scoreA : null,
    scoreB: typeof m.scoreB === "number" ? m.scoreB : null,
    report: r ? { scoreA: num(r.scoreA, 0), scoreB: num(r.scoreB, 0), byTeam: String(r.byTeam ?? "") } : null,
    ifNeeded: m.ifNeeded === true,
    place: typeof m.place === "number" ? m.place : null,
  };
}

/** What kind of event it is, for lists and badges. */
export function hostedType(t: Pick<TournamentDoc, "kind" | "entryType" | "teamEntry">): HostedType {
  if (t.kind === "league") return "league";
  return t.entryType === "players" && !t.teamEntry ? "hat" : "tournament";
}
export const takesPlayers = (t: Pick<TournamentDoc, "entryType">) => t.entryType === "players";
/** Teams can enter: team-entry events, and player events that let teams reserve spots. */
export const takesTeams = (t: Pick<TournamentDoc, "entryType" | "teamEntry">) => t.entryType !== "players" || t.teamEntry === true;
export const mixedEntry = (t: Pick<TournamentDoc, "entryType" | "teamEntry">) => t.entryType === "players" && t.teamEntry === true;
/**
 * Who can enter, as the host picks it (EntryChoice in hosted_tournament.dart):
 * teams apply; players sign up and are drafted; or, for a league, both:
 * a captain pays the team fee and brings their own players, and everyone
 * else signs up on their own and is drafted onto the remaining teams. A
 * tournament still offers that third way as a switch under "Players sign up".
 */
export const entryChoices = ["teams", "players", "both"] as const;
export type EntryChoice = (typeof entryChoices)[number];
export const entryChoiceLabels: Record<EntryChoice, string> = {
  teams: "Teams apply",
  players: "Players sign up",
  both: "Teams and players",
};
/** The choices a [kind] offers: all three for a league. */
export const entryChoicesFor = (kind: HostedKind): readonly EntryChoice[] =>
  kind === "league" ? entryChoices : ["teams", "players"];
/** The choice an event's fields make (a tournament's switch reads as "players"). */
export function entryChoiceOf(t: { kind?: HostedKind | string; entryType: TournamentEntryType; teamEntry?: boolean }): EntryChoice {
  if (t.entryType !== "players") return "teams";
  return t.kind === "league" && t.teamEntry === true ? "both" : "players";
}
/** The fields a choice stores. */
export const entryFields = (c: EntryChoice): { entryType: TournamentEntryType; teamEntry: boolean } =>
  c === "teams" ? { entryType: "teams", teamEntry: false } : { entryType: "players", teamEntry: c === "both" };

/** What a team pays to enter (bid fee or spot fee), if anything. */
export function spotFee(t: Pick<TournamentDoc, "entryType" | "teamEntry" | "bidFee" | "teamFee">): FeeDoc | null {
  return t.entryType === "players" ? (t.teamEntry ? (t.teamFee ?? null) : null) : t.bidFee;
}

/**
 * The fee [teamId] pays to enter: the spot fee, except for the host's own
 * team, which plays its own event for free (HostedTournament.feeFor in
 * the app).
 */
export function teamFee(
  t: Pick<TournamentDoc, "entryType" | "teamEntry" | "bidFee" | "teamFee"> & { hostId?: string | null },
  teamId: string,
): FeeDoc | null {
  return t.hostId && teamId === t.hostId ? null : spotFee(t);
}

/**
 * A new event's starting divisions and level from the team hosting it:
 * its own division, and its level (club, college, youth) unless the event
 * is a league, which keeps "league". Null for groups and organizations,
 * which have no division.
 */
export function hostDefaults(
  host: { kind?: string | null; division?: string | null; level?: string | null },
  kind: HostedKind,
): { division: Division; level: CompetitionLevel } | null {
  if ((host.kind ?? "team") !== "team") return null;
  const division = divisions.find((d) => d === host.division);
  const level = competitionLevels.find((l) => l === host.level);
  if (!division || !level) return null;
  return { division, level: kind === "league" ? "league" : level };
}

const dayMs = 24 * 60 * 60 * 1000;

/**
 * Registration (entries, signups and paying fees) opens at most this many
 * days before an event starts, so Stall 10 never holds fees for long. The
 * event can be a draft before then; its location can be added later.
 */
export const registrationWindowDays = 60;

/** The first day registration can open for an event starting [startsOn]. */
export function registrationOpensOn(startsOn: Date): Date {
  return new Date(startsOn.getTime() - registrationWindowDays * dayMs);
}

/** Why registration can't open now ([now], ms) for an event starting [startsOn], or null. */
export function registrationWindowProblem(startsOn: Date | null, now: number): string | null {
  if (!startsOn) return "Set the event's date first.";
  const opens = registrationOpensOn(startsOn);
  if (opens.getTime() <= now) return null;
  const day = opens.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });
  return `Registration opens ${registrationWindowDays} days before the event, on ${day}. Keep it as a draft until then.`;
}

/**
 * When rosters and fees are due: the event's entry deadline, else the
 * fee's due date, else the day before it starts. Null without a start.
 * HostedTournament.effectiveDeadline in the app.
 */
export function effectiveDeadline(t: {
  entryDeadline?: Date | string | null;
  startsOn?: Date | string | null;
  entryType?: TournamentEntryType | string;
  teamEntry?: boolean;
  bidFee?: { dueAt?: Date | string | null } | null;
  teamFee?: { dueAt?: Date | string | null } | null;
}): Date | null {
  const set = dateOf(t.entryDeadline ?? null);
  if (set) return set;
  const fee = t.entryType === "players" ? ((t.teamEntry ? t.teamFee : null) ?? t.bidFee) : t.bidFee;
  const due = dateOf(fee?.dueAt ?? null);
  if (due) return due;
  const starts = dateOf(t.startsOn ?? null);
  return starts ? new Date(starts.getTime() - dayMs) : null;
}

/** Why an entry deadline can't be used, or null: it has to be by the time the event starts. */
export function entryDeadlineProblem(deadline: Date | null, startsOn: Date): string | null {
  if (!deadline) return null;
  if (deadline.getTime() > startsOn.getTime()) return "The entry deadline has to be before the event starts.";
  return null;
}

/** A team's (or player's) progress through entering: what's left before the deadline. */
export interface EntryChecklist {
  /** In the event (accepted), not still waiting on the organizer. */
  accepted: boolean;
  /** The team named enough players (always true for a player signup). */
  rosterSet: boolean;
  /** Paid, or nothing to pay. */
  paid: boolean;
  /** There's a fee to pay at all. */
  owes: boolean;
  deadline: Date | null;
  /** Past the deadline with something left to do. */
  overdue: boolean;
  /** Roster and payment both done. */
  complete: boolean;
}

/**
 * Where an entry stands (entryChecklist in the app): [rosterSize] is how
 * many players the team named (null for a player signup), [minRoster] how
 * many the division needs, [paid] whether payments/{payer}.paid, [owes]
 * whether there's a fee to pay.
 */
export function entryChecklist(e: {
  status: string;
  rosterSize: number | null;
  minRoster: number;
  paid: boolean;
  owes: boolean;
  deadline: Date | null;
  now: Date | number;
}): EntryChecklist {
  const accepted = e.status === "accepted";
  const rosterSet = e.rosterSize == null || e.rosterSize >= e.minRoster;
  const paid = !e.owes || e.paid;
  const complete = rosterSet && paid;
  const t = typeof e.now === "number" ? e.now : e.now.getTime();
  const overdue = !complete && !!e.deadline && t > e.deadline.getTime();
  return { accepted, rosterSet, paid, owes: e.owes, deadline: e.deadline, overdue, complete };
}

/** "$250" or "$250.50". */
export function feeLabel(f: { amountCents: number; currency: string }): string {
  const whole = Math.floor(f.amountCents / 100);
  const cents = f.amountCents % 100;
  const symbol = f.currency === "USD" ? "$" : `${f.currency} `;
  return cents === 0 ? `${symbol}${whole}` : `${symbol}${whole}.${String(cents).padStart(2, "0")}`;
}

/** "Club Mixed". */
export const divisionLabel = (d: { division: Division; level: CompetitionLevel }) => `${levelLabels[d.level]} ${divisionLabels[d.division]}`;

export const effectiveMinRoster = (d: { minRoster?: number | null }) => d.minRoster ?? tournamentLimits.defaultMinRoster;

/** "to 11", or "25 min timed". */
export const scoreLabel = (s: { scoring?: string; gameMinutes: number; scoreCap: number }) =>
  s.scoring === "time" ? `${s.gameMinutes} min timed` : `to ${s.scoreCap}`;

/** The format a league's division plays follows its season; otherwise the division's own. */
export function formatOf(t: Pick<TournamentDoc, "kind" | "season">, d: { settings: { format: TournamentFormat } }): TournamentFormat {
  if (t.kind === "league" && t.season) {
    return t.season.playoffTeams > 0 && t.season.playoffWeeks > 0 ? "singleElim" : "roundRobin";
  }
  return d.settings.format;
}

/** Why a team can't play in a league's division, or null (leagueFitProblem). */
export function leagueFitProblem(
  team: { name: string; division?: string; level?: string },
  d: { division: Division; level: CompetitionLevel } | null,
): string | null {
  if (!d) return null;
  if (team.division !== d.division) {
    return `${divisionLabel(d)} is for ${divisionLabels[d.division]} teams; ${team.name} plays ${divisionLabels[(team.division as Division) ?? "mixed"] ?? team.division}.`;
  }
  if (d.level !== "league" && team.level !== d.level) {
    return `${divisionLabel(d)} is for ${levelLabels[d.level]} teams; ${team.name} is ${levelLabels[(team.level as CompetitionLevel) ?? "club"] ?? team.level}.`;
  }
  return null;
}

// ---- Formats (EventFormat), in local time: for the browser -------------------

/** The format as the form edits it: dates as Date. */
export interface FormFormat {
  settings: EngineSettings;
  level: CompetitionLevel;
  maxTeams: number;
  minRoster: number | null;
}

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/** Each day after [first] up to [last], at [first]'s time; at most six. */
export function daysAfter(first: Date, last: Date | null): Date[] {
  if (!last) return [];
  const end = startOfDay(last).getTime();
  const out: Date[] = [];
  for (
    let d = new Date(first.getFullYear(), first.getMonth(), first.getDate() + 1, first.getHours(), first.getMinutes());
    startOfDay(d).getTime() <= end && out.length < 6;
    d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, d.getHours(), d.getMinutes())
  ) {
    out.push(d);
  }
  return out;
}

/** A weekly 7v7 league night, or a two-day club tournament (EventFormat.usual). */
export function usualFormat(t: { kind: HostedKind; startsOn: Date; endsOn: Date | null }): FormFormat {
  const s = t.startsOn;
  if (t.kind === "league") {
    return {
      level: "league",
      maxTeams: 8,
      minRoster: null,
      settings: {
        startsAt: new Date(s.getFullYear(), s.getMonth(), s.getDate(), 18, 30),
        format: "roundRobin",
        playersOnField: 7,
        poolCount: 2,
        gameMinutes: 60,
        breakMinutes: 10,
        scoreCap: 15,
        timeoutsPerHalf: 2,
        fields: 2,
        idealEndsAt: null,
        laterDays: [],
        scoring: "points",
      },
    };
  }
  const first = new Date(s.getFullYear(), s.getMonth(), s.getDate(), 9);
  return {
    level: "club",
    maxTeams: 16,
    minRoster: null,
    settings: {
      playersOnField: 7,
      startsAt: first,
      format: "poolsPlacement",
      poolCount: 4,
      gameMinutes: 90,
      breakMinutes: 15,
      scoreCap: 15,
      timeoutsPerHalf: 2,
      fields: 4,
      idealEndsAt: null,
      laterDays: daysAfter(first, t.endsOn),
      scoring: "points",
    },
  };
}

/** [f] on the event's dates (EventFormat.on): first day at the same time, later days, a league's format from its season. */
export function formatOn(
  f: FormFormat,
  t: { kind: HostedKind; startsOn: Date; endsOn: Date | null; season: { playoffTeams: number; playoffWeeks: number } | null },
): FormFormat {
  const s = t.startsOn;
  const first = new Date(s.getFullYear(), s.getMonth(), s.getDate(), f.settings.startsAt.getHours(), f.settings.startsAt.getMinutes());
  const league = t.kind === "league";
  return {
    ...f,
    settings: {
      ...f.settings,
      startsAt: first,
      laterDays: league ? [] : daysAfter(first, t.endsOn),
      format: league
        ? t.season && t.season.playoffTeams > 0 && t.season.playoffWeeks > 0
          ? "singleElim"
          : "roundRobin"
        : f.settings.format,
    },
  };
}

/** The format as the API takes it (dates as ISO strings). */
export function formatRequest(f: FormFormat) {
  const s = f.settings;
  return {
    level: f.level,
    maxTeams: f.maxTeams,
    minRoster: f.minRoster,
    settings: {
      format: s.format,
      playersOnField: s.playersOnField,
      poolCount: s.poolCount,
      gameMinutes: s.gameMinutes,
      breakMinutes: s.breakMinutes,
      scoreCap: s.scoreCap,
      timeoutsPerHalf: s.timeoutsPerHalf,
      fields: s.fields,
      startsAt: s.startsAt.toISOString(),
      idealEndsAt: s.idealEndsAt ? s.idealEndsAt.toISOString() : null,
      laterDays: s.laterDays.map((d) => d.toISOString()),
      scoring: s.scoring,
    },
  };
}

/** A league's last night: the first plus a week for each week, skipped weeks included. */
export function seasonEnd(startsOn: Date, season: { weeks: number; skipDates: unknown[] }): Date | null {
  const nights = season.weeks + season.skipDates.length;
  const last = new Date(startsOn.getFullYear(), startsOn.getMonth(), startsOn.getDate() + 7 * (nights - 1));
  return last.getTime() === startOfDay(startsOn).getTime() ? null : last;
}
