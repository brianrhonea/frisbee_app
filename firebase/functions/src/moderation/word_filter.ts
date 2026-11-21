// A copy of packages/shared/src/word_filter.ts (no zod), for the Cloud
// Functions backstop; test/moderation/word_filter.test.ts checks it against
// packages/shared/fixtures/word_filter, as the API's and the app's copies are.

/** Refused outright: slurs, hate terms and telling someone to kill themselves. */
export const blockedTerms: readonly string[] = [
  "beaner",
  "fag",
  "faggot",
  "gook",
  "jigaboo",
  "kike",
  "kys",
  "nigga",
  "nigger",
  "paki",
  "raghead",
  "sandnigger",
  "shemale",
  "spic",
  "towelhead",
  "tranny",
  "wetback",
];

/** Refused as phrases (words in order). */
export const blockedPhrases: readonly string[] = [
  "kill yourself",
  "go kill yourself",
  "heil hitler",
  "sieg heil",
  "white power",
];

/** Shown masked ("f***"): mild swearing and insults. */
export const maskedTerms: readonly string[] = [
  "arse",
  "arsehole",
  "ass",
  "asshat",
  "asshole",
  "bastard",
  "bitch",
  "bollocks",
  "bullshit",
  "chink",
  "cock",
  "cocksucker",
  "coon",
  "cunt",
  "dick",
  "dickhead",
  "dipshit",
  "dumbass",
  "dyke",
  "fuck",
  "fucker",
  "fuckface",
  "fuckhead",
  "goddamn",
  "horseshit",
  "jackass",
  "motherfucker",
  "piss",
  "prick",
  "pussy",
  "retard",
  "shit",
  "shithead",
  "slut",
  "twat",
  "wanker",
  "whore",
];

/** Endings a masked word may take ("fucking", "bitches", "shitty"); not
 * "y" or "er", which would catch "cocky" and "cocker spaniel". */
export const maskedEndings: readonly string[] = ["s", "es", "ed", "ing", "in", "ty", "z"];

/** Endings a blocked word may take: plurals only ("spicy" is fine). */
export const blockedEndings: readonly string[] = ["s", "es", "z"];

/** What the API answers when text has a blocked word. */
export const blockedWordsMessage =
  "That includes words that aren't allowed on Stall 10. See the community guidelines.";

/** Look-alike characters, undone before matching. */
const lookAlikes: Record<string, string> = {
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
  "@": "a", $: "s", "!": "i", "|": "i",
};

/** A run of word characters, look-alikes included. */
const tokenPattern = /[\p{L}\p{N}@$!|]+/gu;

/** [word] lower-cased with look-alikes undone; letters only. A trailing
 * "!" or "|" is punctuation ("yourself!"), not a letter. */
export function normalizeWord(word: string): string {
  let out = "";
  for (const ch of word.toLowerCase().replace(/[!|]+$/u, "")) {
    const c = lookAlikes[ch] ?? ch;
    if (/\p{L}/u.test(c)) out += c;
  }
  return out;
}

/** Repeated letters squeezed to one ("fuuuck" → "fuck", "ass" → "as"). */
const squeeze = (w: string) => w.replace(/(\p{L})\1+/gu, "$1");

function buildIndex(terms: readonly string[], endings: readonly string[]) {
  const exact = new Set(terms);
  // Squeezed forms only when long enough not to hit everyday words
  // ("ass" squeezes to "as").
  const squeezed = new Set(terms.map(squeeze).filter((t) => t.length >= 4));
  return { exact, squeezed, endings };
}
type Index = ReturnType<typeof buildIndex>;
const blockedIndex = buildIndex(blockedTerms, blockedEndings);
const maskedIndex = buildIndex(maskedTerms, maskedEndings);

/** [word] itself, or with one of its endings off, is in [set]. */
function hit(word: string, set: Set<string>, endings: readonly string[]): boolean {
  if (set.has(word)) return true;
  return endings.some((e) => word.length > e.length && word.endsWith(e) && set.has(word.slice(0, -e.length)));
}

/** Whether a normalized [word] is one of [index]'s terms. */
function matches(word: string, index: Index): boolean {
  if (!word) return false;
  return (
    hit(word, index.exact, index.endings) ||
    hit(word, index.squeezed, index.endings) ||
    hit(squeeze(word), index.squeezed, index.endings)
  );
}

interface Token {
  start: number;
  end: number;
  word: string;
}

function tokens(text: string): Token[] {
  return [...text.matchAll(tokenPattern)].map((m) => ({
    start: m.index,
    end: m.index + m[0].length,
    word: normalizeWord(m[0]),
  }));
}

export interface FilteredText {
  /** The text with mild swearing masked; unchanged when there's none. */
  text: string;
  /** Whether it has a blocked word or phrase (refuse it). */
  blocked: boolean;
}

/** Checks [text]: masks mild swearing and says whether it's blocked. */
export function filterText(text: string): FilteredText {
  const toks = tokens(text);
  const words = toks.map((t) => t.word);
  let blocked = words.some((w) => matches(w, blockedIndex));
  // Spaced or dotted out: three or more single letters in a row, joined.
  for (let i = 0; !blocked && i < toks.length; ) {
    let j = i;
    while (j < toks.length && words[j].length === 1) j++;
    if (j - i >= 3 && matches(words.slice(i, j).join(""), blockedIndex)) blocked = true;
    i = j === i ? i + 1 : j;
  }
  if (!blocked) {
    const joined = ` ${words.filter(Boolean).join(" ")} `;
    blocked = blockedPhrases.some((p) => joined.includes(` ${p} `));
  }
  let out = "";
  let at = 0;
  for (const t of toks) {
    if (!matches(t.word, maskedIndex)) continue;
    const chars = [...text.slice(t.start, t.end)];
    out += text.slice(at, t.start) + chars[0] + "*".repeat(chars.length - 1);
    at = t.end;
  }
  return { text: at === 0 ? text : out + text.slice(at), blocked };
}

/** Whether [text] has a blocked word or phrase. */
export const hasBlockedWords = (text: string) => filterText(text).blocked;

/** [text] with mild swearing masked (blocked words left as they are). */
export const maskSwearing = (text: string) => filterText(text).text;
