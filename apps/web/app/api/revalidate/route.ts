import { timingSafeEqual } from "node:crypto";
import { revalidateTag } from "next/cache";

// The API calls this the moment something visitors see changes (a profile
// goes private, a post is edited or deleted), so cached public pages never
// show it stale. Tags are the ones lib/api.ts reads with.

const keyHeader = "x-stall10-web-key";
const tagPattern = /^(player:[\w-]{1,128}|post:[\w-]{1,256}|posts|feed|search)$/;
const maxTags = 20;

function sameKey(sent: string | null, key: string | undefined): boolean {
  // Trimmed on both sides: a stray newline in either copy mustn't lock the API out.
  const s = sent?.trim();
  const k = key?.trim();
  if (!s || !k) return false;
  const a = Buffer.from(s);
  const b = Buffer.from(k);
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function POST(req: Request) {
  if (!sameKey(req.headers.get(keyHeader), process.env.WEB_SERVER_KEY)) {
    return Response.json({ error: "Not allowed." }, { status: 401 });
  }
  const body = (await req.json().catch(() => null)) as { tags?: unknown } | null;
  const tags = body?.tags;
  if (!Array.isArray(tags) || tags.length === 0 || tags.length > maxTags || !tags.every((t) => typeof t === "string" && tagPattern.test(t))) {
    return Response.json({ error: "Send up to 20 known tags." }, { status: 400 });
  }
  // expire 0: the next visitor gets fresh content, never a stale copy.
  for (const tag of new Set(tags as string[])) revalidateTag(tag, { expire: 0 });
  return Response.json({ revalidated: [...new Set(tags)] });
}
