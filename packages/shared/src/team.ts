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
export function rosterIsPublic(team: { kind?: unknown; level?: unknown } | null | undefined): boolean {
  if (!team) return false;
  if (team.kind !== undefined && team.kind !== "team") return false;
  return (publicRosterLevels as readonly unknown[]).includes(team.level);
}

/** Whether [team]'s roster is private because it's a youth team (for the website's wording). */
export const isYouthTeam = (team: { kind?: unknown; level?: unknown } | null | undefined): boolean =>
  !!team && (team.kind === undefined || team.kind === "team") && team.level === "youth";
