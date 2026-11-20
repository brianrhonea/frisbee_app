// API-only visibility checks for the visitor (`/v1/public/*`) answers, on
// top of browse/model.ts (which stays a byte-for-byte copy of the
// `browse` Cloud Functions' file; see test/server_copies.test.ts).
import { isYouthTeam, leagueTeamPrefix, publicPageOn } from "@stall10/shared";
import { isPrivateGroup } from "./model.js";

type Data = Record<string, unknown>;

/** The team-doc fields these checks read (a field mask: never the member maps). */
export const hostFields = ["kind", "requiresApproval", "level", "publicPage"] as const;

const kindOf = (d: Data): string => (typeof d.kind === "string" ? d.kind : "team");

/**
 * Whether a team or group keeps its posts, events and hosted events from
 * visitors: a private group by its directory listing OR its team doc, a
 * listing that disagrees with the team doc about its kind or approval, or
 * either document missing. The listing alone could be stale. A team whose
 * "Public team page" is off (publicPageOn false on either) counts too.
 */
export function isPrivateHost(listing: Data | undefined | null, team: Data | undefined | null): boolean {
  if (!listing || !team) return true;
  if (isPrivateGroup(listing) || isPrivateGroup(team)) return true;
  if (!publicPageOn(listing) || !publicPageOn(team)) return true;
  return kindOf(listing) !== kindOf(team) || (listing.requiresApproval === true) !== (team.requiresApproval === true);
}

/** A youth team by its listing or its team doc: visitors get its card only. */
export const isYouthHost = (listing: Data | undefined | null, team: Data | undefined | null): boolean =>
  isYouthTeam(listing) || isYouthTeam(team);

/** A team a league's draft created (`league_…`): its name is its players', so visitors don't get it. */
export const isDraftedLeagueTeam = (teamId: string): boolean => teamId.startsWith(leagueTeamPrefix);

/** What visitors see as a drafted league team's name. */
export const draftedLeagueTeamName = "League team";

/**
 * The Storage buckets whose photos visitors' browsers may load: the
 * configured one (STORAGE_BUCKET) and the project's default buckets.
 */
export function photoBuckets(projectId: string, configured?: string): string[] {
  return [...new Set([configured, `${projectId}.firebasestorage.app`, `${projectId}.appspot.com`].filter((b): b is string => !!b))];
}

/**
 * A profile picture URL visitors may be sent: Firebase Storage in one of
 * [buckets] (either URL shape) or a Google account photo
 * (lh3.googleusercontent.com), over https. Anything else is dropped, so a
 * profile can't make visitors' browsers fetch from a server (or a bucket)
 * of its owner's choosing.
 */
export function pinnedImageUrl(v: unknown, buckets: readonly string[]): string | undefined {
  if (typeof v !== "string" || v.length > 2000) return undefined;
  let u: URL;
  try {
    u = new URL(v);
  } catch {
    return undefined;
  }
  if (u.protocol !== "https:" || u.username || u.password || u.port) return undefined;
  if (u.hostname === "lh3.googleusercontent.com") return v;
  let bucket: string | undefined;
  if (u.hostname === "firebasestorage.googleapis.com") bucket = /^\/v0\/b\/([^/]+)\/o\//.exec(u.pathname)?.[1];
  else if (u.hostname === "storage.googleapis.com") bucket = /^\/([^/]+)\//.exec(u.pathname)?.[1];
  return bucket && buckets.includes(bucket) ? v : undefined;
}
