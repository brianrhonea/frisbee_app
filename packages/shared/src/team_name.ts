// Port of apps/mobile/lib/domain/models/team_name.dart. Team names must be
// unique: two teams can't share a name (or a near-identical one, like
// "TX BQQ" and "Texas BQQ") unless their divisions differ. Groups and
// communities can't share one with another of their kind.
import type { Division, TeamKind } from "./team.js";
import { aliases, common, states, twoWordStates } from "./team_name_tables.js";

// Maps, not object lookups: a word like "constructor" must not match
// Object.prototype.
const stateMap = new Map(Object.entries(states));
const aliasMap = new Map(Object.entries(aliases));
const stateNames = new Set(stateMap.values());

/**
 * The words of [name], lowercased, without punctuation, with abbreviations
 * spelled out: "TX B.Q.Q." → ["texas", "bqq"].
 */
export function teamNameWords(name: string): string[] {
  let text = name.toLowerCase().replaceAll("&", " and ");
  // "B.Q.Q." and "B-Q-Q" are one word; other punctuation splits words.
  text = text.replace(/\b(?:[a-z0-9][.\-]){1,}[a-z0-9]\b\.?/g, (m) => m.replace(/[.\-]/g, ""));
  text = text.replace(/['’]/g, "");
  text = text.replace(/[^a-z0-9]+/g, " ").trim();
  for (const s of twoWordStates) {
    text = text.replace(new RegExp(`\\b${s}\\b`, "g"), s.replaceAll(" ", ""));
  }
  const words = text
    .split(" ")
    .filter((w) => w.length > 0)
    .map((w) => stateMap.get(w) ?? aliasMap.get(w) ?? w);
  // "The Haze" and "Haze" are the same team.
  if (words.length > 1 && words[0] === "the") words.shift();
  return words;
}

/** What a name is compared by: its words run together ("BQQ" = "B QQ"). */
export function teamNameKey(name: string): string {
  return teamNameWords(name).join("");
}

/** The parts of a directory listing a name clash is decided on. */
export interface NameListing {
  id: string;
  name: string;
  kind: TeamKind;
  division: Division;
}

/** Whether [name] for a [kind] team in [division] is taken by [listing]. */
export function teamNameClashes(
  listing: NameListing,
  opts: { name: string; kind: TeamKind; division: Division; excludeId?: string },
): boolean {
  if (listing.id === opts.excludeId) return false;
  if (listing.kind !== opts.kind) return false;
  // Teams in different divisions can share a name; groups have none.
  if (opts.kind === "team" && listing.division !== opts.division) return false;
  const key = teamNameKey(opts.name);
  return key.length > 0 && teamNameKey(listing.name) === key;
}

const clip = (w: string) => (w.length > 20 ? w.substring(0, 20) : w);

/**
 * The search keywords to look for a name's possible clashes by: its most
 * distinctive word, in every spelling a listing's keywords could hold it.
 */
export function teamNameProbe(name: string): string[] {
  const words = teamNameWords(name);
  if (words.length === 0) return [];
  // States are shared by many teams; anything else tells them apart better.
  let distinctive = words.filter((w) => !common.has(w) && !stateNames.has(w));
  if (distinctive.length === 0) distinctive = words.filter((w) => !common.has(w));
  const pool = distinctive.length === 0 ? words : distinctive;
  // The first longest word, as Dart's reduce keeps.
  const pick = pool.reduce((a, b) => (b.length > a.length ? b : a));
  // Listing keywords are prefixes of the words as typed, so also look for
  // the abbreviations and the first word of two-word states.
  const out = new Set<string>([clip(pick)]);
  for (const [key, value] of new Map([...stateMap, ...aliasMap])) {
    if (value === pick) out.add(clip(key));
  }
  for (const s of twoWordStates) {
    if (s.replaceAll(" ", "") === pick) out.add(s.split(" ")[0]);
  }
  return [...out].slice(0, 10);
}

/** The message the app shows when a name is taken (TeamNameTakenException). */
export function nameTakenMessage(name: string, kind: TeamKind, division: Division): string {
  return kind === "team"
    ? `There's already a ${divisionLabels[division]} team called "${name}". Pick a different name.`
    : `There's already a ${teamKindLabels[kind].toLowerCase()} called "${name}". Pick a different name.`;
}

const divisionLabels: Record<Division, string> = {
  mixed: "Mixed",
  open: "Open",
  women: "Women",
  masters: "Masters",
};

const teamKindLabels: Record<TeamKind, string> = {
  team: "Team",
  community: "Community group",
  organization: "School or club",
};
