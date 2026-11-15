// Small text helpers shared across the site.

/**
 * A name's initials, at most [max] letters: "Seattle Ultimate" → "SU";
 * one word gives its first two letters ("Sockeye" → "SO"); nothing → "?".
 * Avatars use one letter (max 1).
 */
export function initials(name: string | undefined, max = 3): string {
  const words = (name ?? "").trim().split(/\s+/).filter(Boolean);
  if (words.length > 1) return words.slice(0, max).map((w) => w[0]).join("").toUpperCase();
  return (words[0] ?? "?").slice(0, Math.min(max, 2)).toUpperCase();
}

/** A document id from the address bar (?c=, ?event=), or null for anything else (`..`, a slash). */
export const validId = (id: string | null | undefined): string | null => (id && /^[A-Za-z0-9_-]{1,300}$/.test(id) ? id : null);

/** Typing in a field (or editable text), where single-key shortcuts mustn't fire. */
export function isTyping(target: EventTarget | null): boolean {
  const el = target as HTMLElement | null;
  return !!el && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));
}
