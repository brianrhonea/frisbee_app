// Splitting a team fee (TeamShare in apps/mobile/lib/domain/models/
// team_share.dart): someone who paid for the whole team (a league's team
// fee, say) sets each member's share and how to pay them (Venmo, cash…),
// and marks who has paid. No money passes through Stall 10. Stored at
// teams/{id}/private/share, which only the API reads and writes.
import { z } from "zod";
import { clean } from "./word_filter.js";

export const teamShareLimits = {
  /** $100,000. */
  maxAmountCents: 10_000_000,
  note: 300,
} as const;

/** `PUT /v1/teams/:id/share` (admins with Manage team): start or change the split; they collect it. */
export const setTeamShareRequestSchema = z.strictObject({
  amountCents: z.number().int().min(1, "Enter each person's share, e.g. 40.").max(teamShareLimits.maxAmountCents),
  currency: z.enum(["usd"]).default("usd"),
  note: clean(z.string().trim().max(teamShareLimits.note).default("")),
});
export type SetTeamShareRequest = z.input<typeof setTeamShareRequestSchema>;

/** `PUT /v1/teams/:id/share/members/:uid` (the collector or Manage team): mark a member paid or not. */
export const markSharePaidRequestSchema = z.strictObject({ paid: z.boolean() });
export type MarkSharePaidRequest = z.input<typeof markSharePaidRequestSchema>;

export const teamSharePath = (teamId: string) => `/v1/teams/${encodeURIComponent(teamId)}/share`;
export const teamShareMemberPath = (teamId: string, uid: string) =>
  `${teamSharePath(teamId)}/members/${encodeURIComponent(uid)}`;

export interface TeamShareMember {
  uid: string;
  name: string;
  paid: boolean;
}

/** `GET /v1/teams/:id/share` (members): the split, or null when there's none. */
export interface TeamShareView {
  share: {
    amountCents: number;
    currency: string;
    note: string;
    /** Who collects (who set it up): everyone else owes a share. */
    collectorId: string;
    collectorName: string;
  } | null;
  /** Whether the caller can change it and mark people paid. */
  manages: boolean;
  /** The caller's own share: null when they collect it (or there's none). */
  mine: { paid: boolean } | null;
  /** Everyone who owes a share, for those who manage it; [] for everyone else. */
  members: TeamShareMember[];
}

/** Collected and still owed, for the manager's summary. */
export function shareTotals(amountCents: number, members: readonly { paid: boolean }[]): {
  paid: number;
  owed: number;
  collectedCents: number;
  outstandingCents: number;
} {
  const paid = members.filter((m) => m.paid).length;
  const owed = members.length - paid;
  return { paid, owed, collectedCents: paid * amountCents, outstandingCents: owed * amountCents };
}

/** An even share of [totalCents] among [people] (the team fee ÷ the roster), rounded up to the cent. */
export function evenShare(totalCents: number, people: number): number {
  if (people <= 0 || totalCents <= 0) return 0;
  return Math.ceil(totalCents / people);
}
