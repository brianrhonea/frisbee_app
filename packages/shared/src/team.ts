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
