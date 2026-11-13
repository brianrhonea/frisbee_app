// Ports of lib/domain/models/model_utils.dart (searchKeywords, searchWords)
// in apps/mobile. Directory documents store these as `keywords`, so every
// writer must produce exactly the same list; test/fixtures/team_create.json
// is checked by both the Dart and the TypeScript tests.

/** Lowercased words of a name or search query. */
export function searchWords(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[\s\-_.]+/)
    .filter((w) => w.length > 0);
}

/**
 * Every prefix of every word in [text], lowercased, so a search for "jo" or
 * "smi" finds "Jo Smith". At most 20 characters per prefix and 100 prefixes.
 */
export function searchKeywords(text: string): string[] {
  const out = new Set<string>();
  for (const w of searchWords(text)) {
    // Dart's String.length and substring count UTF-16 units, as JS does.
    for (let i = 1; i <= w.length && i <= 20; i++) out.add(w.substring(0, i));
  }
  return [...out].slice(0, 100);
}
