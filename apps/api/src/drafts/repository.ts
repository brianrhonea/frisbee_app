// The two queries the draft operations make (DocStore has no queries):
// a division's accepted signups, and whether it has any games yet.
import type { Firestore } from "firebase-admin/firestore";
import type { Data, DocStore } from "../store.js";

export interface DraftQueries {
  /** tournaments/{t}/signups where divisionId == [divisionId] and status == "accepted". */
  acceptedSignups(tournamentId: string, divisionId: string): Promise<Array<{ id: string; data: Data }>>;
  /** Whether tournaments/{t}/divisions/{d}/games has a document (the schedule is published). */
  hasGames(tournamentId: string, divisionId: string): Promise<boolean>;
}

export class FirestoreDraftQueries implements DraftQueries {
  constructor(private readonly db: Firestore) {}

  async acceptedSignups(tournamentId: string, divisionId: string) {
    const snap = await this.db
      .collection(`tournaments/${tournamentId}/signups`)
      .where("divisionId", "==", divisionId)
      .where("status", "==", "accepted")
      .get();
    // Only names, skill and gender are read, so timestamps can stay as they are.
    return snap.docs.map((d) => ({ id: d.id, data: d.data() as Data }));
  }

  async hasGames(tournamentId: string, divisionId: string) {
    const snap = await this.db.collection(`tournaments/${tournamentId}/divisions/${divisionId}/games`).limit(1).get();
    return !snap.empty;
  }
}

/**
 * The same queries by listing documents through [store]: for tests and
 * local runs without FirestoreDraftQueries. Reads at most [cap] signups.
 */
export function listDraftQueries(store: DocStore, cap = 5000): DraftQueries {
  return {
    async acceptedSignups(tournamentId, divisionId) {
      const all = await store.list(`tournaments/${tournamentId}/signups`, cap);
      return all.filter((s) => s.data.divisionId === divisionId && s.data.status === "accepted");
    },
    async hasGames(tournamentId, divisionId) {
      return (await store.list(`tournaments/${tournamentId}/divisions/${divisionId}/games`, 1)).length > 0;
    },
  };
}
