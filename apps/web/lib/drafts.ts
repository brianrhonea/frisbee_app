// Unsent composer text, per member, in this browser (no Firebase import,
// so the auth provider can clear it on every page).
import { legacyMessageDraftsKey, messageDraftsKey, withDraft } from "@stall10/shared";

// ---- Drafts ------------------------------------------------------------------
//
// Kept per member (messageDraftsKey), as the app keeps them, and cleared
// when that member signs out (clearDrafts), so nobody else on this browser
// sees what they left unsent.

function readDrafts(uid: string): Record<string, string> {
  try {
    // Drafts from before they were kept per member can't be told apart: forget them.
    window.localStorage.removeItem(legacyMessageDraftsKey);
    const raw = window.localStorage.getItem(messageDraftsKey(uid));
    const map = raw ? (JSON.parse(raw) as unknown) : null;
    if (!map || typeof map !== "object" || Array.isArray(map)) return {};
    return Object.fromEntries(Object.entries(map).filter((e): e is [string, string] => typeof e[1] === "string"));
  } catch {
    return {};
  }
}

/** What [uid] left unsent in [key]'s composer (`dm_<id>`, `chat_<team>_<room>`, as the app keys them). */
export function loadDraft(uid: string, key: string): string {
  return readDrafts(uid)[key] ?? "";
}

/** Remembers [text] for [uid]'s [key] in this browser; blank forgets it. */
export function saveDraft(uid: string, key: string, text: string) {
  try {
    window.localStorage.setItem(messageDraftsKey(uid), JSON.stringify(withDraft(readDrafts(uid), key, text)));
  } catch {
    // No storage (a private window, say): drafts just aren't kept.
  }
}

/** Forgets [uid]'s drafts on this browser (on signing out). */
export function clearDrafts(uid: string) {
  try {
    window.localStorage.removeItem(messageDraftsKey(uid));
    window.localStorage.removeItem(legacyMessageDraftsKey);
  } catch {
    // No storage: nothing was kept.
  }
}
