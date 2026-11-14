"use client";
import {
  type DraftDetailsDoc,
  type DraftedTeam,
  draftedTeams,
  draftPaths,
  type DraftControlAction,
  type LiveDraftDoc,
  type PlayerSignupDoc,
  type SaveSignupInput,
  type SignupStatus,
  type TeamPermission,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import { limit } from "firebase/firestore";
import { callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";

// What the signups and draft views read and write. Reads are Firestore
// listeners, as the app's (the rules decide who sees signups, drafts and
// their private details); writes go through the API (draftPaths).

/** The fields of tournaments/{id} these views use. */
export interface TournamentDoc {
  name?: string;
  hostId?: string;
  kind?: "tournament" | "league";
  entryType?: "teams" | "players";
  draftMode?: "balanced" | "captains";
  status?: "draft" | "registration" | "seeding" | "scheduled" | "live" | "finished";
  visibility?: "public" | "inviteOnly";
  bidFee?: { amountCents: number; currency: string; instructions?: string; dueAt?: string | null } | null;
}

/** The fields of tournaments/{id}/divisions/{id} these views use. */
export interface DivisionDoc {
  division?: string;
  level?: string;
  settings?: { playersOnField?: number };
  maxTeams?: number;
  seeds?: string[];
  captains?: Record<string, string[]>;
  teams?: unknown[];
}

export interface PaymentDoc {
  paid?: boolean;
  paidAt?: string | null;
  note?: string;
}

const statusOrder = ["draft", "registration", "seeding", "scheduled", "live", "finished"];
/** HostedStatus.index >= scheduled: the schedule is out. */
export const isScheduled = (t: TournamentDoc) => statusOrder.indexOf(t.status ?? "draft") >= statusOrder.indexOf("scheduled");

const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);
/** "League Mixed", like DivisionSummary.label. */
export const divisionLabel = (d: DivisionDoc) => `${cap(d.level ?? "")} ${cap(d.division ?? "")}`.trim();

/** EntryFee.label: "$25" or "$25.50", other currencies by code. */
export function feeLabel(fee: NonNullable<TournamentDoc["bidFee"]>): string {
  const whole = Math.floor(fee.amountCents / 100);
  const cents = fee.amountCents % 100;
  const symbol = fee.currency === "USD" ? "$" : `${fee.currency} `;
  return cents === 0 ? `${symbol}${whole}` : `${symbol}${whole}.${String(cents).padStart(2, "0")}`;
}
export const dateLabel = (iso: string) => new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });

/** can(team, perm) in the rules, from the host team doc (null when the caller can't read it). */
function canOn(team: Record<string, unknown> | null | undefined, uid: string, perm: TeamPermission): boolean {
  if (!team) return false;
  const role = (team.members as Record<string, string> | undefined)?.[uid];
  if (role === "owner" || role === "coach" || role === "captain") return true;
  const ids = (team.memberIds as string[] | undefined) ?? [];
  const perms = (team.memberPerms as Record<string, string[]> | undefined)?.[uid] ?? [];
  return ids.includes(uid) && perms.includes(perm);
}

const t = (id: string) => `tournaments/${id}`;

/** The tournament, its divisions, and whether the caller manages it. */
export function useTournamentBase(tournamentId: string, uid: string | null) {
  const tournament = useLiveDoc<TournamentDoc>(uid ? t(tournamentId) : null);
  const divisions = useLiveQuery<DivisionDoc>(uid ? `${t(tournamentId)}/divisions` : null, [], `divisions:${tournamentId}`);
  const hostId = tournament.data?.hostId;
  // Only members can read a team; anyone else simply isn't a manager.
  const host = useLiveDoc<Record<string, unknown>>(uid && hostId ? `teams/${hostId}` : null);
  const manager = !!uid && canOn(host.data, uid, "manageEvents");
  const list = [...(divisions.data ?? [])].sort((a, b) => a.id.localeCompare(b.id));
  return { tournament, divisions: { ...divisions, data: divisions.data ? list : undefined }, manager };
}

/** Everyone's signups (managers), or just the caller's own. */
export function useSignups(tournamentId: string, manager: boolean) {
  return useLiveQuery<PlayerSignupDoc>(manager ? `${t(tournamentId)}/signups` : null, [], `signups:${tournamentId}`);
}
export const useMySignup = (tournamentId: string, uid: string | null) => useLiveDoc<PlayerSignupDoc>(uid ? `${t(tournamentId)}/signups/${uid}` : null);
export function usePayments(tournamentId: string, manager: boolean) {
  return useLiveQuery<PaymentDoc>(manager ? `${t(tournamentId)}/payments` : null, [], `payments:${tournamentId}`);
}
export const useMyPayment = (tournamentId: string, uid: string | null) => useLiveDoc<PaymentDoc>(uid ? `${t(tournamentId)}/payments/${uid}` : null);

/** A division's captains' draft board (managers and its accepted players can read it). */
export const useLiveDraft = (tournamentId: string, divisionId: string | null) =>
  useLiveDoc<LiveDraftDoc>(divisionId ? `${t(tournamentId)}/drafts/${divisionId}` : null);
/** Skill and gender (the host and the draft's captains). */
export const useDraftDetails = (tournamentId: string, divisionId: string, can: boolean) =>
  useLiveDoc<DraftDetailsDoc>(can ? `${t(tournamentId)}/drafts/${divisionId}/details/pool` : null);

/** Whether the division has games: the schedule is published. */
export function useHasGames(tournamentId: string, divisionId: string | null) {
  const games = useLiveQuery(divisionId ? `${t(tournamentId)}/divisions/${divisionId}/games` : null, [limit(1)], `games:${tournamentId}:${divisionId}`);
  return games.data === undefined ? undefined : games.data.length > 0;
}

export const teamsOf = (d: Doc<DivisionDoc> | null | undefined): DraftedTeam[] => draftedTeams(d?.teams);

// ---- Writes ------------------------------------------------------------------------

export const draftApi = {
  saveMySignup: (user: User, tournamentId: string, body: SaveSignupInput) =>
    callApi<{ status: string }>(user, draftPaths.mySignup(tournamentId), { method: "PUT", body }),
  setStatus: (user: User, tournamentId: string, uid: string, status: SignupStatus) =>
    callApi<void>(user, draftPaths.signupStatus(tournamentId, uid), { method: "PUT", body: { status } }),
  setPaid: (user: User, tournamentId: string, uid: string, paid: boolean) =>
    callApi<void>(user, draftPaths.signupPayment(tournamentId, uid), { method: "PUT", body: { paid } }),
  saveTeams: (user: User, tournamentId: string, divisionId: string, teams: DraftedTeam[]) =>
    callApi<void>(user, draftPaths.draftedTeams(tournamentId, divisionId), { method: "PUT", body: { teams } }),
  createLeagueTeams: (user: User, tournamentId: string, divisionId: string) =>
    callApi<{ created: number; teams: { teamId: string; name: string }[] }>(user, draftPaths.leagueTeams(tournamentId, divisionId), { method: "POST", body: {} }),
  start: (user: User, tournamentId: string, divisionId: string, captainIds: string[], pickSeconds: number) =>
    callApi<{ captains: number; players: number }>(user, draftPaths.draft(tournamentId, divisionId), { method: "POST", body: { captainIds, pickSeconds } }),
  pick: (user: User, tournamentId: string, divisionId: string, uid: string) =>
    callApi<void>(user, draftPaths.draftPicks(tournamentId, divisionId), { method: "POST", body: { uid } }),
  control: (user: User, tournamentId: string, divisionId: string, action: DraftControlAction) =>
    callApi<void>(user, draftPaths.draftControl(tournamentId, divisionId), { method: "POST", body: { action } }),
  finish: (user: User, tournamentId: string, divisionId: string) =>
    callApi<{ teams: number }>(user, draftPaths.draftFinish(tournamentId, divisionId), { method: "POST", body: {} }),
};

/** Runs [fn], keeping busy and the error message for the view. */
export async function attempt(setBusy: (b: boolean) => void, setError: (e: string | null) => void, fn: () => Promise<unknown>): Promise<boolean> {
  setBusy(true);
  setError(null);
  try {
    await fn();
    return true;
  } catch (e) {
    setError((e as Error).message);
    return false;
  } finally {
    setBusy(false);
  }
}

/** Where each view lives until the hosted tournament page mounts them. */
export const draftHrefs = {
  signups: (tournamentId: string, divisionId?: string) =>
    `/tournaments/${encodeURIComponent(tournamentId)}/signups${divisionId ? `?division=${encodeURIComponent(divisionId)}` : ""}`,
  liveDraft: (tournamentId: string, divisionId: string) => `/tournaments/${encodeURIComponent(tournamentId)}/draft/${encodeURIComponent(divisionId)}`,
  teamDraft: (tournamentId: string, divisionId: string) => `/tournaments/${encodeURIComponent(tournamentId)}/team-draft/${encodeURIComponent(divisionId)}`,
};
