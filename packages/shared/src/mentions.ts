// @mentions in team chat, like Discord: @everyone, @<role name> and
// @<member name> in a message's text. The composer suggests them; the
// message stores what it mentions (`mentions`), which the notifications
// trigger reads to reach those people even in a room they muted.
//
// The app's copy is apps/mobile/lib/domain/models/mentions.dart; both are
// checked against fixtures/mentions (written by the app's
// test/shared_fixtures/mention_fixtures_test.dart).

export const mentionLimits = {
  /** Most people one message mentions by name. */
  maxUsers: 50,
  /** Most roles one message mentions. */
  maxRoles: 20,
} as const;

/** The word that mentions everyone who can read the room. */
export const everyoneMention = "everyone";

export interface MentionTargets {
  /** The team's members: uid and display name (team.memberNames). */
  members: { uid: string; name: string }[];
  /** The team's custom roles: id and name (team.roles). */
  roles: { id: string; name: string }[];
}

/** What a message mentions, as stored on it. */
export interface Mentions {
  users: string[];
  roles: string[];
  everyone: boolean;
}

// Plain code-unit order of lower-cased names, so the app sorts the same.
const byName = (a: { name: string }, b: { name: string }) => {
  const x = a.name.toLowerCase();
  const y = b.name.toLowerCase();
  return x < y ? -1 : x > y ? 1 : 0;
};

export type MentionKind = "everyone" | "role" | "user";

/** One @mention in a text: [start, end) covers the @ and the name. */
export interface MentionSpan {
  start: number;
  end: number;
  kind: MentionKind;
  /** The uid or role id; "everyone" for @everyone. */
  id: string;
}

const wordChar = /[\p{L}\p{N}_]/u;

interface Candidate {
  label: string;
  kind: MentionKind;
  id: string;
}

function candidates(targets: MentionTargets, groups: boolean): Candidate[] {
  const all: Candidate[] = groups ? [{ label: everyoneMention, kind: "everyone", id: everyoneMention }] : [];
  if (groups) for (const r of targets.roles) if (r.name.trim()) all.push({ label: r.name.trim(), kind: "role", id: r.id });
  for (const m of targets.members) if (m.name.trim()) all.push({ label: m.name.trim(), kind: "user", id: m.uid });
  // The longest name wins: "@Sam Lee" over "@Sam". Then everyone, roles, people.
  const order: Record<MentionKind, number> = { everyone: 0, role: 1, user: 2 };
  return all.sort((a, b) => b.label.length - a.label.length || order[a.kind] - order[b.kind]);
}

/**
 * The @mentions in [text], in order. An @ starts one only at the start or
 * after a character that isn't a letter, digit or _ (so emails don't), and
 * the name must end at the end or before one. Names match ignoring case.
 * Without [groups], only people (for someone who can't mention roles).
 */
export function mentionSpans(text: string, targets: MentionTargets, groups = true): MentionSpan[] {
  if (!text.includes("@")) return [];
  const list = candidates(targets, groups);
  const lower = text.toLowerCase();
  const spans: MentionSpan[] = [];
  let i = 0;
  while (i < text.length) {
    const at = text.indexOf("@", i);
    if (at < 0) break;
    if (at > 0 && wordChar.test(text[at - 1])) {
      i = at + 1;
      continue;
    }
    const hit = list.find((c) => {
      const end = at + 1 + c.label.length;
      return lower.startsWith(c.label.toLowerCase(), at + 1) && (end >= text.length || !wordChar.test(text[end]));
    });
    if (!hit) {
      i = at + 1;
      continue;
    }
    const end = at + 1 + hit.label.length;
    spans.push({ start: at, end, kind: hit.kind, id: hit.id });
    i = end;
  }
  return spans;
}

/**
 * What [text] mentions, to store on the message. @everyone and roles count
 * only when [canMentionGroups] (the owner and chat managers; the rules
 * agree), and each list is capped at its limit.
 */
export function mentionsIn(text: string, targets: MentionTargets, canMentionGroups: boolean): Mentions {
  const users: string[] = [];
  const roles: string[] = [];
  let everyone = false;
  for (const s of mentionSpans(text, targets, canMentionGroups)) {
    if (s.kind === "user") {
      if (!users.includes(s.id) && users.length < mentionLimits.maxUsers) users.push(s.id);
    } else if (!canMentionGroups) {
      continue;
    } else if (s.kind === "role") {
      if (!roles.includes(s.id) && roles.length < mentionLimits.maxRoles) roles.push(s.id);
    } else {
      everyone = true;
    }
  }
  return { users, roles, everyone };
}

/** Whether a message's [mentions] (as stored) reach anyone. */
export const mentionsAnyone = (m: Mentions | undefined | null): boolean =>
  !!m && (m.everyone || m.users.length > 0 || m.roles.length > 0);

/**
 * The @word being typed just before the cursor, for suggestions: its start
 * (the @) and what's typed after it. Null when the cursor isn't in one.
 * Up to 30 characters, which may include spaces ("@Sam Le").
 */
export function mentionQuery(text: string, cursor: number): { start: number; query: string } | null {
  if (cursor < 0 || cursor > text.length) return null;
  const before = text.slice(0, cursor);
  const at = before.lastIndexOf("@");
  if (at < 0 || (at > 0 && wordChar.test(before[at - 1]))) return null;
  const query = before.slice(at + 1);
  if (query.length > 30 || query.includes("\n") || query.includes("@") || /^\s/.test(query)) return null;
  return { start: at, query };
}

/**
 * Suggestions for [query]: everyone and roles (when [canMentionGroups]),
 * then members, whose name or any word of it starts with the query. At most
 * [limit].
 */
export function mentionSuggestions(
  query: string,
  targets: MentionTargets,
  canMentionGroups: boolean,
  limit = 8,
): Candidate[] {
  const q = query.trim().toLowerCase();
  const matches = (label: string) => {
    const l = label.toLowerCase();
    return !q || l.startsWith(q) || l.split(/\s+/).some((w) => w.startsWith(q));
  };
  const out: Candidate[] = [];
  if (canMentionGroups) {
    if (matches(everyoneMention)) out.push({ label: everyoneMention, kind: "everyone", id: everyoneMention });
    for (const r of [...targets.roles].sort(byName)) {
      if (r.name.trim() && matches(r.name)) out.push({ label: r.name.trim(), kind: "role", id: r.id });
    }
  }
  for (const m of [...targets.members].sort(byName)) {
    if (m.name.trim() && matches(m.name)) out.push({ label: m.name.trim(), kind: "user", id: m.uid });
  }
  return out.slice(0, limit);
}

export type MentionSuggestion = ReturnType<typeof mentionSuggestions>[number];

/** [text] with the @query at [start]..[cursor] replaced by the mention and a space; and the new cursor. */
export function insertMention(text: string, start: number, cursor: number, label: string): { text: string; cursor: number } {
  const inserted = `@${label} `;
  return { text: text.slice(0, start) + inserted + text.slice(cursor), cursor: start + inserted.length };
}
