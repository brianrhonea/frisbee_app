// Pure helpers for the `browse` group: what signed-out visitors to the
// website may see. Everything here decides by allow-list, so a field added
// to a document later stays hidden until it's added here on purpose.

import { createHash } from "node:crypto";

type Data = Record<string, unknown>;

/** Posts, events and listings per page. */
export const pageSize = 20;

/** Upcoming events per call. */
export const eventLimit = 50;

/**
 * The rate-limit key for a visitor: a hash of their IP address, so
 * `limits/` never stores the address itself.
 */
export function visitorKey(ip: string): string {
  return "ip_" + createHash("sha256").update(ip).digest("hex").slice(0, 32);
}

/** The caller's IP: the first X-Forwarded-For hop, else the socket's. */
export function clientIp(forwardedFor: unknown, socketIp: unknown): string {
  const first = typeof forwardedFor === "string" ? forwardedFor.split(",")[0]?.trim() : "";
  if (first) return first;
  return typeof socketIp === "string" && socketIp ? socketIp : "unknown";
}

/** A document id the app could have made; anything else is refused. */
export function validId(id: unknown): id is string {
  return typeof id === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(id);
}

/** A `before` cursor in ms since epoch, or null for the first page. */
export function parseBefore(before: unknown): number | null {
  return typeof before === "number" && Number.isFinite(before) && before > 0 ? before : null;
}

const pick = (d: Data, keys: readonly string[]): Data =>
  Object.fromEntries(keys.filter((k) => d[k] !== undefined).map((k) => [k, d[k]]));

const listLength = (v: unknown): number => (Array.isArray(v) ? v.length : 0);

const postFields = [
  "kind",
  "body",
  "links",
  "images",
  "event",
  "repostOf",
  "tournamentKey",
  "tournamentName",
  "authorId",
  "authorName",
  "authorPhotoUrl",
  "commentCount",
  "createdAt",
  "updatedAt",
] as const;

/**
 * A post as visitors see it: who liked or reposted it becomes counts, and a
 * workout keeps its numbers but not its GPS route, which can show where
 * someone lives.
 */
export function postView(data: Data): Data {
  const view = pick(data, postFields);
  view.likeCount = listLength(data.likedBy);
  view.repostCount = listLength(data.repostedBy);
  const workout = data.workout;
  if (data.kind === "workout" && workout && typeof workout === "object") {
    const { route: _route, ...rest } = workout as Data;
    view.workout = rest;
  }
  return view;
}

/** Whose privacy a post depends on: its author and, for a repost, the original's. */
export function postAuthors(data: Data): string[] {
  const ids = [data.authorId];
  const repost = data.repostOf;
  if (repost && typeof repost === "object") ids.push((repost as Data).authorId);
  return ids.filter((id): id is string => typeof id === "string" && id.length > 0);
}

/** Whether a profile document is private (or missing, which hides too). */
export function isPrivateProfile(profile: Data | undefined): boolean {
  return !profile || profile.private === true;
}

/**
 * A profile as visitors see it. A private one shows only who it is, as
 * the app does for people who don't follow them. Teams, stats and games
 * follow the player's own visibility settings.
 */
export function profileView(profile: Data): Data {
  const card = pick(profile, ["name", "photoUrl", "username"]);
  if (profile.private === true) return { ...card, private: true };
  const visibility = (profile.visibility ?? {}) as Data;
  const shows = (k: string) => visibility[k] !== false;
  return {
    ...card,
    ...pick(profile, ["bio", "pronouns", "hometown", "school", "throwingHand", "playingSince", "summaryUpdatedAt"]),
    visibility: { stats: shows("stats"), teams: shows("teams"), games: shows("games") },
    ...(shows("teams") ? pick(profile, ["teams"]) : {}),
    ...(shows("stats") ? pick(profile, ["stats"]) : {}),
    ...(shows("games") ? pick(profile, ["games"]) : {}),
  };
}

/**
 * A team or group's directory listing as visitors see it. It's already
 * public to anyone signed in (firestore.rules keeps it in step with the
 * team, without a private group's location); search keywords stay behind.
 */
export function listingView(listing: Data): Data {
  return pick(listing, [
    "name",
    "division",
    "level",
    "city",
    "kind",
    "description",
    "requiresApproval",
    "location",
  ]);
}

/**
 * A group that approves who joins keeps its posts and events to members
 * (`showsPublic` in firestore.rules).
 */
export function isPrivateGroup(listing: Data | undefined): boolean {
  return !listing || (listing.kind === "community" && listing.requiresApproval === true);
}

/** A team's public event, as `TeamEvent.toPublicMap` writes it. */
export function eventView(event: Data): Data {
  return pick(event, ["title", "type", "startsAt", "endsAt", "location", "notes"]);
}

/** A team post visitors may see: marked public by its team. */
export function isPublicTeamPost(post: Data): boolean {
  return post.public === true;
}

const teamPostFields = ["title", "body", "location", "links", "images", "authorId", "authorName", "public", "tournamentKey", "createdAt", "updatedAt"] as const;

/** A team's public home-page post, without who reacted. */
export function teamPostView(post: Data): Data {
  return pick(post, teamPostFields);
}

/** A profile in search results: the card, as private profiles show it. */
export function searchProfileView(profile: Data): Data {
  return { ...pick(profile, ["name", "photoUrl", "username"]), ...(profile.private === true ? { private: true } : {}) };
}
