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

/** Web addresses in plain text: http(s) links and bare `www.` ones (as the app's LinkifiedText). */
const urlPattern = /(https?:\/\/|www\.)[^\s<>"']+/gi;
/** Trailing punctuation that usually ends the sentence, not the link. */
const trailingPunctuation = /[.,;:!?)\]]+$/;

/** [text] in plain runs and links: `href` is set on links only. */
export function splitLinks(text: string): Array<{ text: string; href?: string }> {
  const parts: Array<{ text: string; href?: string }> = [];
  let at = 0;
  for (const m of text.matchAll(urlPattern)) {
    const start = m.index ?? 0;
    const raw = m[0].replace(trailingPunctuation, "");
    const href = raw.toLowerCase().startsWith("www.") ? `https://${raw}` : raw;
    let ok = false;
    try {
      const u = new URL(href);
      ok = (u.protocol === "https:" || u.protocol === "http:") && u.hostname.length > 0;
    } catch {
      ok = false;
    }
    if (!ok) continue;
    if (start > at) parts.push({ text: text.slice(at, start) });
    parts.push({ text: raw, href });
    at = start + raw.length;
  }
  if (at < text.length) parts.push({ text: text.slice(at) });
  return parts;
}
