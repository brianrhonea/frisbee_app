// Copied from firebase/functions/src/browse/model.ts, unchanged below this
// header, while the `browse` callables and the API both serve visitors.
// Keep the two in step until the website stops calling the callables;
// test/browse.model.test.ts is the original test file.

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

let imageBuckets: readonly string[] | null = null;

/**
 * The Storage buckets imageUrl trusts. Set once at startup; until then (or
 * with an empty list) any bucket's Storage URL passes, but Google photos
 * are still limited to lh3.
 */
export function configureImageBuckets(buckets: readonly string[]): void {
  imageBuckets = buckets.length > 0 ? buckets : null;
}

/**
 * A picture URL visitors' browsers may load: this app's Firebase Storage
 * buckets (see configureImageBuckets) or Google account photos
 * (lh3.googleusercontent.com) only, over https, so a profile can't make
 * every visitor fetch from a server (or a bucket) of its owner's choosing
 * (the rules let owners store any string).
 */
export function imageUrl(v: unknown): string | undefined {
  if (typeof v !== "string" || v.length > 2000) return undefined;
  try {
    const u = new URL(v);
    if (u.protocol !== "https:" || u.username || u.password || u.port) return undefined;
    if (u.hostname === "lh3.googleusercontent.com") return v;
    let bucket: string | undefined;
    if (u.hostname === "firebasestorage.googleapis.com") bucket = /^\/v0\/b\/([^/]+)\/o\//.exec(u.pathname)?.[1];
    else if (u.hostname === "storage.googleapis.com") bucket = /^\/([^/]+)\//.exec(u.pathname)?.[1];
    else return undefined;
    return bucket && (!imageBuckets || imageBuckets.includes(bucket)) ? v : undefined;
  } catch {
    return undefined;
  }
}

/** A profile's name, pictures (checked by imageUrl) and username. */
function cardOf(profile: Data, fields: string[]): Data {
  const card = pick(profile, fields);
  for (const k of ["photoUrl", "headerUrl"]) {
    if (k in card) {
      const url = imageUrl(card[k]);
      if (url) card[k] = url;
      else delete card[k];
    }
  }
  return card;
}

/**
 * A profile as visitors see it. A private one shows only who it is, as
 * the app does for people who don't follow them. Teams, stats and games
 * follow the player's own visibility settings.
 */
export function profileView(profile: Data): Data {
  const card = cardOf(profile, ["name", "photoUrl", "headerUrl", "username"]);
  if (profile.private === true) return { ...card, private: true };
  const visibility = (profile.visibility ?? {}) as Data;
  const shows = (k: string) => visibility[k] !== false;
  return {
    ...card,
    ...pick(profile, ["bio", "pronouns", "hometown", "school", "throwingHand", "playingSince", "summaryUpdatedAt"]),
    visibility: { stats: shows("stats"), teams: shows("teams"), games: shows("games") },
    ...(shows("teams") ? pick(profile, ["teams"]) : {}),
    ...(shows("stats") ? pick(profile, ["stats"]) : {}),
    // Per-team stats say which teams they're on, so only with both shown.
    ...(shows("stats") && shows("teams") ? pick(profile, ["teamStats"]) : {}),
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
    "allowJoinRequests",
  ]);
}

/**
 * A group that approves who joins keeps its posts and events to members
 * (`showsPublic` in firestore.rules).
 */
export function isPrivateGroup(listing: Data | undefined): boolean {
  // Groups and school/club communities that approve who joins (as the rules treat them).
  return (
    !listing || ((listing.kind === "community" || listing.kind === "organization") && listing.requiresApproval === true)
  );
}

/** A team's public event, as `TeamEvent.toPublicMap` writes it. */
export function eventView(event: Data): Data {
  return pick(event, ["title", "type", "startsAt", "endsAt", "location", "notes"]);
}

/** A team post visitors may see: marked public by its team. */
export function isPublicTeamPost(post: Data): boolean {
  return post.public === true;
}

const teamPostFields = ["title", "body", "location", "links", "images", "authorId", "authorName", "public", "tournamentKey", "createdAt", "updatedAt", "pinnedAt"] as const;

/** A team's public home-page post, without who reacted. */
export function teamPostView(post: Data): Data {
  return pick(post, teamPostFields);
}

/** A profile in search results: the card, as private profiles show it. */
export function searchProfileView(profile: Data): Data {
  return { ...cardOf(profile, ["name", "photoUrl", "username"]), ...(profile.private === true ? { private: true } : {}) };
}
