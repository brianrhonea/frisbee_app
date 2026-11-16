// Raw reads for visitors' rankings (public_service.ts decides what is
// shown). Timestamps come back as ISO strings.
import type { Firestore } from "firebase-admin/firestore";
import { plain } from "../browse/repository.js";
import { hostFields } from "../browse/visibility.js";

export type Data = Record<string, unknown>;
export interface Doc {
  id: string;
  data: Data;
}

export interface PublicRankingRepository {
  /** Every `rankings/{level-division}` doc (at most [rankingDocsMax]). */
  rankings(): Promise<Doc[]>;
  /** teamDirectory listings by team id, only the fields visibility.ts checks (hostFields); missing ones left out. */
  listings(teamIds: string[]): Promise<Map<string, Data>>;
  /** Team docs by id, only the fields visibility.ts checks (hostFields); missing ones left out. */
  teams(teamIds: string[]): Promise<Map<string, Data>>;
}

/** More ranking docs than the functions write (4 levels × 4 divisions, plus any old youth ones). */
export const rankingDocsMax = 40;

/** Documents per getAll. */
const readBatch = 300;

async function getAllMasked(db: Firestore, collection: string, ids: string[]): Promise<Map<string, Data>> {
  const unique = [...new Set(ids)];
  const out = new Map<string, Data>();
  for (let i = 0; i < unique.length; i += readBatch) {
    const refs = unique.slice(i, i + readBatch).map((id) => db.doc(`${collection}/${id}`));
    const snaps = await db.getAll(...refs, { fieldMask: [...hostFields] });
    for (const s of snaps) if (s.exists) out.set(s.id, plain(s.data()) as Data);
  }
  return out;
}

export class FirestorePublicRankingRepository implements PublicRankingRepository {
  constructor(private readonly db: Firestore) {}

  async rankings(): Promise<Doc[]> {
    const snap = await this.db.collection("rankings").limit(rankingDocsMax).get();
    return snap.docs.map((d) => ({ id: d.id, data: plain(d.data()) as Data }));
  }

  listings(teamIds: string[]) {
    return getAllMasked(this.db, "teamDirectory", teamIds);
  }

  teams(teamIds: string[]) {
    return getAllMasked(this.db, "teams", teamIds);
  }
}
