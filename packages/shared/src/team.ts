// Team types and request schemas, mirroring apps/mobile/lib/domain/models/
// team.dart and the limits in firebase/firestore.rules (validTeamFields,
// validGroupFields, validLocation, validLeagueRef).
import { z } from "zod";

export const divisions = ["mixed", "open", "women", "masters"] as const;
export type Division = (typeof divisions)[number];

export const competitionLevels = ["club", "college", "youth", "league", "pickup"] as const;
export type CompetitionLevel = (typeof competitionLevels)[number];

/** `team` has no `kind` field in Firestore; groups store theirs. */
export const teamKinds = ["team", "community", "organization"] as const;
export type TeamKind = (typeof teamKinds)[number];

export const isGroupLike = (kind: TeamKind) => kind !== "team";

/**
 * A club team: a team (no `kind`, or "team") at the club level (a stored
 * team with no level reads as club, as the app and listings read it).
 * Joining one needs [clubMinimumAge] (personal.ts); groups and other
 * levels are open to everyone.
 */
export const isClubTeam = (t: { kind?: unknown; level?: unknown }) =>
  (t.kind == null || t.kind === "team") && (t.level == null || t.level === "club");

export const groupLocationSchema = z.strictObject({
  address: z.string().max(200),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});
export type GroupLocation = z.infer<typeof groupLocationSchema>;

/** Limits shared with firestore.rules. */
export const teamLimits = {
  name: 80,
  city: 80,
  description: 1000,
  leagueId: 60,
} as const;

/**
 * Body of `POST /v1/teams` (NewTeam in the app). The owner is whoever's ID
 * token signs the request; it is never taken from the body.
 */
export const createTeamRequestSchema = z
  .strictObject({
    name: z.string().trim().min(1, "Name your team.").max(teamLimits.name),
    division: z.enum(divisions),
    level: z.enum(competitionLevels),
    city: z.string().trim().max(teamLimits.city).default(""),
    kind: z.enum(teamKinds).default("team"),
    description: z.string().trim().max(teamLimits.description).default(""),
    requiresApproval: z.boolean().default(false),
    location: groupLocationSchema.nullable().default(null),
    /** The league a team is started for, to reserve a spot (teams only). */
    leagueId: z.string().min(1).max(teamLimits.leagueId).nullable().default(null),
  })
  .superRefine((t, ctx) => {
    if (isGroupLike(t.kind) && t.leagueId != null) {
      ctx.addIssue({ code: "custom", path: ["leagueId"], message: "Only a team can reserve a league spot." });
    }
  });

/**
 * A team's sections its owner switches on or off (`sections` on the team
 * doc; Team.sections in the app). Feed, Schedule, Chat and Roster are
 * always there. A missing map or key reads as on, so teams made before
 * the switches keep everything; new teams start with these off
 * ([newTeamSections]). Communities and organizations store none.
 */
export const optionalTeamSections = ["playbook", "videos", "stats", "meetings"] as const;
export type OptionalTeamSection = (typeof optionalTeamSections)[number];

/** What a new team (not a community) stores: every optional section off. */
export const newTeamSections = (): Record<OptionalTeamSection, boolean> => ({
  playbook: false,
  videos: false,
  stats: false,
  meetings: false,
});

/** Whether [team] shows [section]: on unless stored as false. */
export function sectionOn(team: { sections?: unknown } | Record<string, unknown>, section: OptionalTeamSection): boolean {
  const s = (team as { sections?: unknown }).sections;
  return !(s && typeof s === "object" && (s as Record<string, unknown>)[section] === false);
}

/**
 * Body of `PUT /v1/teams/:id/sections`: the sections to switch, each on
 * (true) or off (false). Sections left out keep what they have.
 */
export const setTeamSectionsRequestSchema = z
  .strictObject({
    playbook: z.boolean().optional(),
    videos: z.boolean().optional(),
    stats: z.boolean().optional(),
    meetings: z.boolean().optional(),
  })
  .refine((s) => Object.values(s).some((v) => v !== undefined), { message: "Pick a section to switch." });
export type SetTeamSectionsRequest = z.input<typeof setTeamSectionsRequestSchema>;

/**
 * A team's "Public team page" switch (`publicPage` on the team doc and its
 * directory listing; Team.publicPage in the app). Missing or true: anyone
 * may see its public posts, upcoming public events and, for an adult team,
 * its roster. false: people outside the team see only its card (name,
 * division, level and city in search), as a private group's. It only ever
 * hides more: youth rosters stay private either way. Teams only; groups
 * use requiresApproval.
 */
export function publicPageOn(team: { publicPage?: unknown } | Record<string, unknown> | null | undefined): boolean {
  return (team as { publicPage?: unknown } | null | undefined)?.publicPage !== false;
}

/** What the switch does, as both apps say it (publicPageDescription in team_settings_screen.dart). */
export const publicPageDescription =
  "Anyone can see the team's public posts, upcoming public events and, for an adult team, its roster. Turned off, people outside the team see only its name and city. Chat always stays private.";

/** Body of `PUT /v1/teams/:id/public-page` (manageTeam admins). */
export const setPublicPageRequestSchema = z.strictObject({ public: z.boolean() });
export type SetPublicPageRequest = z.input<typeof setPublicPageRequestSchema>;

export type CreateTeamRequest = z.input<typeof createTeamRequestSchema>;
export type CreateTeamInput = z.output<typeof createTeamRequestSchema>;

export interface CreateTeamResponse {
  id: string;
}

/**
 * Levels whose team rosters anyone may see, signed in or not: adult play
 * (open/men's, women's, mixed and masters divisions alike). Youth teams,
 * and teams with no level stored, keep their rosters to members. Listed
 * on purpose rather than "every level but youth", so a level added later
 * stays private until it's added here.
 */
export const publicRosterLevels = ["club", "college", "league", "pickup"] as const satisfies readonly CompetitionLevel[];

/**
 * Whether visitors (signed out, on the website) may see [team]'s roster
 * (`GET /v1/public/teams/:id/roster`): a team, never a community or
 * organization (they keep no roster, and a private group keeps its members
 * to itself), at an adult level. Fails closed: an unknown kind, a missing
 * or unknown level, or no team at all is private. The API checks both the
 * team doc and its directory listing; the website, which has only the
 * listing, uses it to choose what to show.
 */
export function rosterIsPublic(team: { kind?: unknown; level?: unknown; publicPage?: unknown } | null | undefined): boolean {
  if (!team) return false;
  if (team.kind !== undefined && team.kind !== "team") return false;
  if (!publicPageOn(team)) return false;
  return (publicRosterLevels as readonly unknown[]).includes(team.level);
}

/** Whether [team]'s roster is private because it's a youth team (for the website's wording). */
export const isYouthTeam = (team: { kind?: unknown; level?: unknown } | null | undefined): boolean =>
  !!team && (team.kind === undefined || team.kind === "team") && team.level === "youth";
