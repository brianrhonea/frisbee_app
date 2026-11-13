// Reposts carry their original (as the app shows a repost: the original as
// it is now, under the reposter's note), and paging cursors. Shared by the
// public reads and the member's own feed.
import type { PublicPost } from "@stall10/shared";
import { pageSize } from "./model.js";
import type { Data, Doc } from "./repository.js";

/** The original post id a repost points at, if [data] is a repost. */
export function originalIdOf(data: Data): string | null {
  const r = data.repostOf;
  const id = r && typeof r === "object" ? (r as Data).postId : null;
  return typeof id === "string" && id.length > 0 && !id.includes("/") ? id : null;
}

/** The originals of the reposts among [docs], by id (null when deleted). */
export async function originalsOf(docs: Doc[], read: (id: string) => Promise<Doc | null>): Promise<Map<string, Doc | null>> {
  const ids = [...new Set(docs.map((d) => originalIdOf(d.data)).filter((id): id is string => id !== null))];
  const found = await Promise.all(ids.map(async (id) => [id, await read(id)] as const));
  return new Map(found);
}

/** [view] of [doc], with its original when it's a repost. */
export function withOriginal(
  view: PublicPost,
  doc: Doc,
  originals: Map<string, Doc | null>,
  show: (original: Doc) => PublicPost,
): PublicPost {
  const id = originalIdOf(doc.data);
  if (!id) return view;
  const original = originals.get(id);
  return { ...view, original: original ? show(original) : null };
}

/** The `before` cursor for the page after [docs]: null on a short (last) page. */
export function nextCursor(docs: Doc[], size: number = pageSize): number | null {
  const last = docs.at(-1)?.data.createdAt;
  if (docs.length < size || typeof last !== "string") return null;
  const ms = Date.parse(last);
  return Number.isFinite(ms) ? ms : null;
}
