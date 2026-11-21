// The word filter's backstop for app builds that write straight to
// Firestore without it (the API and newer apps filter before saving). On
// each create or edit of the text below: a blocked word deletes a message,
// comment or post, or replaces a name or title with "Removed"; mild
// swearing is rewritten masked. Masked text passes on the next run, so the
// rewrite doesn't loop. Exported in the `api` group.

import type { DocumentSnapshot } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { filterText } from "./word_filter";

/** What a blocked word does: delete the document, or blank the field. */
type OnBlocked = "delete" | "replace";

/** The fix for a document's [fields]: null when nothing needs changing. */
export function textFix(
  data: Record<string, unknown> | undefined,
  fields: readonly string[],
  onBlocked: OnBlocked,
): "delete" | Record<string, string> | null {
  if (!data) return null;
  const update: Record<string, string> = {};
  for (const f of fields) {
    const value = data[f];
    if (typeof value !== "string" || value === "") continue;
    const { text, blocked } = filterText(value);
    if (blocked) {
      if (onBlocked === "delete") return "delete";
      update[f] = "Removed";
    } else if (text !== value) {
      update[f] = text;
    }
  }
  return Object.keys(update).length ? update : null;
}

async function apply(
  before: DocumentSnapshot | undefined,
  after: DocumentSnapshot | undefined,
  fields: readonly string[],
  onBlocked: OnBlocked,
): Promise<void> {
  if (!after?.exists) return;
  const now = after.data();
  // Only text that changed (a like or a read receipt doesn't need a look).
  const old = before?.exists ? before.data() : undefined;
  const changed = fields.filter((f) => now?.[f] !== old?.[f]);
  if (changed.length === 0) return;
  const fix = textFix(now, changed, onBlocked);
  if (!fix) return;
  logger.info("Word filter", { path: after.ref.path, action: fix === "delete" ? "deleted" : Object.keys(fix) });
  if (fix === "delete") await after.ref.delete();
  else await after.ref.update(fix);
}

const filtered = (path: string, fields: readonly string[], onBlocked: OnBlocked) =>
  onDocumentWritten(path, (e) => apply(e.data?.before, e.data?.after, fields, onBlocked));

export const postTextFilter = filtered("posts/{postId}", ["body"], "delete");
export const commentTextFilter = filtered("posts/{postId}/comments/{id}", ["body"], "delete");
export const teamMessageTextFilter = filtered("teams/{teamId}/chats/{roomId}/messages/{id}", ["text"], "delete");
export const directMessageTextFilter = filtered("conversations/{convId}/messages/{id}", ["text"], "delete");
export const meetingMessageTextFilter = filtered("teams/{teamId}/meetings/{meetingId}/messages/{id}", ["text"], "delete");
export const teamPostTextFilter = filtered("teams/{teamId}/posts/{postId}", ["title", "body", "location"], "delete");
export const groupNameTextFilter = filtered("conversations/{convId}", ["name"], "replace");
export const eventTextFilter = filtered("teams/{teamId}/events/{eventId}", ["title", "location", "notes"], "replace");
