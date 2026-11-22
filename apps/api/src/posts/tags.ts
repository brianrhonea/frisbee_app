// "At a tournament": which followed tournaments a post can be tagged with
// now (tournamentTagOpen in packages/shared). Hosted tournaments are
// tournaments/{id} (startsOn/endsOn, hidden while a draft); group
// tournaments are their public listing tournamentDirectory/{groupId}_{id}
// (startsAt/endsOn). Both clients' pickers use this.
import { parseTournamentKey, type TagTournament, type TagTournaments, tournamentTagOpen } from "@stall10/shared";
import type { Data, DocStore } from "../store.js";

/** Follows read per call: far more tournaments than anyone follows. */
export const tagFollowsMax = 500;

const iso = (v: unknown): string | null => {
  if (v instanceof Date) return v.toISOString();
  if (typeof v === "string" && !Number.isNaN(Date.parse(v))) return new Date(v).toISOString();
  if (v && typeof (v as { toDate?: unknown }).toDate === "function") return (v as { toDate: () => Date }).toDate().toISOString();
  return null;
};

export async function tagTournaments(store: DocStore, uid: string, now: Date): Promise<TagTournaments> {
  const follows = (await store.list(`users/${uid}/follows`, tagFollowsMax)).filter((f) => f.data.type === "tournament");
  const targets = follows.flatMap((f) => {
    const t = parseTournamentKey(f.id);
    return t ? [{ key: f.id, name: typeof f.data.name === "string" ? f.data.name : "", ...t }] : [];
  });
  const [hosted, listed] = await Promise.all([
    store.getAll(targets.map((t) => `tournaments/${t.tournamentId}`)),
    store.getAll(targets.map((t) => `tournamentDirectory/${t.hostId}_${t.tournamentId}`)),
  ]);
  const out: TagTournament[] = [];
  targets.forEach((t, i) => {
    const h: Data | null = hosted[i] && hosted[i]!.hostId === t.hostId ? hosted[i] : null;
    // A draft isn't out yet; a missing one may have been deleted.
    if (h && (h.status ?? "draft") === "draft") return;
    const d = h ?? listed[i];
    if (!d) return;
    const startsOn = iso(h ? d.startsOn : d.startsAt);
    const endsOn = iso(d.endsOn);
    if (!startsOn || !tournamentTagOpen(startsOn, endsOn, now)) return;
    const name = (typeof d.name === "string" && d.name) || t.name || "Tournament";
    out.push({ key: t.key, name: name.slice(0, 100), startsOn, endsOn });
  });
  out.sort((a, b) => a.startsOn.localeCompare(b.startsOn));
  return { tournaments: out };
}
