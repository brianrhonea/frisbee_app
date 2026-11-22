// Player profiles and usernames (ARCHITECTURE.md §10, item 3). Ports of
// Username (apps/mobile/lib/domain/models/username.dart) and
// profileKeywords (model_utils.dart), with the limits firestore.rules
// checks on profiles/{uid} (validProfile) and its private/details doc.
import { z } from "zod";
import { searchKeywords } from "./keywords.js";

export const usernameLimits = { min: 3, max: 20 } as const;

/** Names that would look official (Username._reserved). */
const reservedUsernames = new Set([
  "admin",
  "administrator",
  "stall10",
  "support",
  "help",
  "team",
  "official",
  "moderator",
  "null",
  "undefined",
]);

/** [input] as stored: trimmed, without a leading "@", lowercase. */
export function normalizeUsername(input: string): string {
  const t = input.trim().toLowerCase();
  return t.startsWith("@") ? t.substring(1) : t;
}

/** What's wrong with [input] as a username, or null (Username.problem). */
export function usernameProblem(input: string): string | null {
  const name = normalizeUsername(input);
  if (name.length < usernameLimits.min) return `At least ${usernameLimits.min} characters`;
  if (name.length > usernameLimits.max) return `At most ${usernameLimits.max} characters`;
  if (!/^[a-z0-9_.]+$/.test(name)) return "Use only letters, numbers, _ and .";
  if (name.startsWith(".") || name.endsWith(".") || name.includes("..")) {
    return "Periods can't be first, last or doubled";
  }
  if (reservedUsernames.has(name)) return "That username is reserved";
  return null;
}

/** "@name is taken. Try another." (UsernameTakenException). */
export const usernameTakenMessage = (name: string) => `@${name} is taken. Try another.`;

/** A profile's search keywords: its name and username words, plus username prefixes. */
export function profileKeywords(name: string, username?: string | null): string[] {
  const out = new Set(searchKeywords(`${name} ${username ?? ""}`));
  if (username != null) {
    for (let i = 1; i <= username.length && i <= 20; i++) out.add(username.substring(0, i));
  }
  return [...out].slice(0, 100);
}

/**
 * "pat.lee" from "Pat Lee": a starting suggestion they can change, or ""
 * when the name makes no valid one (Username.suggest in the app).
 */
export function suggestUsername(name: string | null | undefined): string {
  const n = (name ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.+|\.+$/g, "");
  const s = n.length > usernameLimits.max ? n.slice(0, usernameLimits.max).replace(/\.+$/, "") : n;
  return usernameProblem(s) == null ? s : "";
}

/**
 * The first and last name boxes of sign-up and of "Your name and
 * username" (PersonName in the app). Together, with a space, they fit
 * the profile's name.
 */
export const personNameLimits = { first: 30, last: 30 } as const;

/**
 * A display name (Google's or Apple's, or the profile's) split into first
 * and last to start the name boxes from: the first word, then the rest,
 * each cut to [personNameLimits]. Nothing for an empty name or one that
 * looks like an email (PersonName.split in the app).
 */
export function splitDisplayName(name: string | null | undefined): { first: string; last: string } {
  const t = (name ?? "").trim();
  if (!t || t.includes("@")) return { first: "", last: "" };
  const [first = "", ...rest] = t.split(/\s+/);
  return {
    first: first.slice(0, personNameLimits.first).trim(),
    last: rest.join(" ").slice(0, personNameLimits.last).trim(),
  };
}

/** "Pat Lee": the name everyone sees, from the two boxes (PersonName.join). */
export const joinPersonName = (first: string, last: string) => `${first.trim()} ${last.trim()}`.trim();

/**
 * Whether the username step asks for their name too (PersonName.asks):
 * they signed in with Google or Apple (no password), whose name nobody
 * typed, or the account has no usable name (Apple can hide it).
 */
export function asksForName(displayName: string | null | undefined, hasPassword: boolean): boolean {
  return !hasPassword || nameMissing(displayName);
}

/** No usable name on the account: empty, or an email (PersonName.missing). */
export const nameMissing = (displayName: string | null | undefined) => splitDisplayName(displayName).first === "";

export const profileLimits = {
  name: 80,
  bio: 280,
  pronouns: 30,
  hometown: 60,
  school: 60,
  tags: 100,
} as const;

export const throwingHands = ["right", "left", "both"] as const;

/** Which sections others see (ProfileVisibility). */
export const profileVisibilitySchema = z.strictObject({
  stats: z.boolean().default(true),
  teams: z.boolean().default(true),
  games: z.boolean().default(true),
});

/** Search tags (school, hometown, teams), as the app works them out. */
const tags = z.array(z.string().max(100)).max(profileLimits.tags).default([]);

/** `POST /v1/me/username`: claim a username, once per account. */
export const claimUsernameRequestSchema = z.strictObject({ username: z.string().max(64) });

/** `PUT /v1/me/profile/details`: what the player writes about themselves (ProfileDetails). */
export const profileDetailsRequestSchema = z.strictObject({
  bio: z.string().trim().max(profileLimits.bio).default(""),
  pronouns: z.string().trim().max(profileLimits.pronouns).default(""),
  hometown: z.string().trim().max(profileLimits.hometown).default(""),
  school: z.string().trim().max(profileLimits.school).default(""),
  throwingHand: z.enum(throwingHands).nullable().default(null),
  playingSince: z.number().int().nullable().default(null),
  visibility: profileVisibilitySchema.default({ stats: true, teams: true, games: true }),
  tags,
});

/** `PUT /v1/me/profile/privacy`: a private profile shows only the name, username and photo. */
export const profilePrivacyRequestSchema = z.strictObject({ private: z.boolean() });

/** `PUT /v1/me/profile/visibility`. */
export const profileVisibilityRequestSchema = z.strictObject({
  visibility: profileVisibilitySchema,
  tags,
});

/**
 * Fields that move to profiles/{uid}/private/details when the profile is
 * private (PlayerProfile.privateFields).
 */
export const privateProfileFields = [
  "bio",
  "pronouns",
  "hometown",
  "school",
  "throwingHand",
  "playingSince",
  "visibility",
  "teams",
  "stats",
  "teamStats",
  "games",
  "summaryUpdatedAt",
  "tags",
] as const;
