import type { NameListing, TeamKind } from "@stall10/shared";
import { FieldValue, type Firestore, Timestamp } from "firebase-admin/firestore";
import { newTeamDocuments, type Owner } from "./documents.js";
import type { CreateTeamInput } from "@stall10/shared";

/** Team data access. The service holds the rules; this only reads and writes. */
export interface TeamRepository {
  /** When the user's flood mute ends (limits/{uid}.mutedUntil), in millis. */
  mutedUntil(uid: string): Promise<number | null>;
  /** Whether tournaments/{id} exists and takes teams (teamEntry). */
  leagueTakesTeams(leagueId: string): Promise<boolean>;
  /** Directory listings holding any of [keywords] (at most [limit]). */
  listingsWithKeywords(keywords: string[], limit: number): Promise<NameListing[]>;
  /** Writes every document of a new team at once; returns its id. */
  createTeam(input: CreateTeamInput, owner: Owner): Promise<string>;
}

const teamKinds: readonly TeamKind[] = ["team", "community", "organization"];

export class FirestoreTeamRepository implements TeamRepository {
  constructor(private readonly db: Firestore) {}

  async mutedUntil(uid: string): Promise<number | null> {
    const snap = await this.db.doc(`limits/${uid}`).get();
    const until = snap.get("mutedUntil");
    return until instanceof Timestamp ? until.toMillis() : null;
  }

  async leagueTakesTeams(leagueId: string): Promise<boolean> {
    const snap = await this.db.doc(`tournaments/${leagueId}`).get();
    return snap.exists && snap.get("teamEntry") === true;
  }

  async listingsWithKeywords(keywords: string[], limit: number): Promise<NameListing[]> {
    if (keywords.length === 0) return [];
    const snap = await this.db
      .collection("teamDirectory")
      .where("keywords", "array-contains-any", keywords)
      .limit(limit)
      .get();
    return snap.docs.map((d) => {
      const kind = d.get("kind");
      return {
        id: d.id,
        name: String(d.get("name") ?? ""),
        kind: teamKinds.includes(kind) ? kind : "team",
        division: d.get("division") ?? "mixed",
      };
    });
  }

  async createTeam(input: CreateTeamInput, owner: Owner): Promise<string> {
    const ref = this.db.collection("teams").doc();
    const batch = this.db.batch();
    const docs = newTeamDocuments(ref.id, input, owner, FieldValue.serverTimestamp());
    for (const [path, data] of Object.entries(docs)) batch.create(this.db.doc(path), data);
    await batch.commit();
    return ref.id;
  }
}
