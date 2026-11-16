// Raw reads for visitors' tournament pages (public_service.ts decides what
// is shown). Timestamps come back as ISO strings.
import { type Firestore, Timestamp } from "firebase-admin/firestore";
import { plain } from "../browse/repository.js";

export type Data = Record<string, unknown>;
export interface Doc {
  id: string;
  data: Data;
}

export interface PublicTournamentRepository {
  /** Up to [max] tournaments with a status in [statuses] starting from [since], soonest first. */
  startingFrom(statuses: readonly string[], since: Date, max: number): Promise<Doc[]>;
  /** Up to [max] tournaments with a status in [statuses] ending from [since], soonest first (leagues still running). */
  endingFrom(statuses: readonly string[], since: Date, max: number): Promise<Doc[]>;
  tournament(id: string): Promise<Data | null>;
  divisions(id: string): Promise<Doc[]>;
  /** Entries' team names, divisions and statuses only. */
  entries(id: string): Promise<Doc[]>;
  /** A division's games, in order. */
  games(id: string, divisionId: string): Promise<Doc[]>;
  /** teamDirectory listings by team id (missing ones left out). */
  listings(teamIds: string[]): Promise<Map<string, Data>>;
  /** tournamentDirectory/{listingId}: a group tournament's public listing. */
  groupListing(listingId: string): Promise<Data | null>;
}

/** Most divisions, entries and games read for one page (rules: 12 divisions; 2,100 games a division). */
export const readCaps = { divisions: 20, entries: 1000, games: 2200 } as const;

const doc = (d: { id: string; data: () => Record<string, unknown> | undefined }): Doc => ({
  id: d.id,
  data: plain(d.data() ?? {}) as Data,
});

export class FirestorePublicTournamentRepository implements PublicTournamentRepository {
  constructor(private readonly db: Firestore) {}

  private async upcoming(field: "startsOn" | "endsOn", statuses: readonly string[], since: Date, max: number) {
    const snap = await this.db
      .collection("tournaments")
      .where("status", "in", [...statuses])
      .where(field, ">=", Timestamp.fromDate(since))
      .orderBy(field)
      .limit(max)
      .get();
    return snap.docs.map(doc);
  }

  startingFrom(statuses: readonly string[], since: Date, max: number) {
    return this.upcoming("startsOn", statuses, since, max);
  }

  endingFrom(statuses: readonly string[], since: Date, max: number) {
    return this.upcoming("endsOn", statuses, since, max);
  }

  async tournament(id: string): Promise<Data | null> {
    const snap = await this.db.doc(`tournaments/${id}`).get();
    return snap.exists ? (plain(snap.data()) as Data) : null;
  }

  async divisions(id: string): Promise<Doc[]> {
    const snap = await this.db.collection(`tournaments/${id}/divisions`).limit(readCaps.divisions).get();
    return snap.docs.map(doc);
  }

  async entries(id: string): Promise<Doc[]> {
    const snap = await this.db
      .collection(`tournaments/${id}/entries`)
      .select("teamName", "divisionId", "status")
      .limit(readCaps.entries)
      .get();
    return snap.docs.map(doc);
  }

  async games(id: string, divisionId: string): Promise<Doc[]> {
    const snap = await this.db
      .collection(`tournaments/${id}/divisions/${divisionId}/games`)
      .orderBy("order")
      .limit(readCaps.games)
      .get();
    return snap.docs.map(doc);
  }

  async listings(teamIds: string[]): Promise<Map<string, Data>> {
    const unique = [...new Set(teamIds)];
    if (unique.length === 0) return new Map();
    const snaps = await this.db.getAll(...unique.map((id) => this.db.doc(`teamDirectory/${id}`)));
    return new Map(snaps.filter((s) => s.exists).map((s) => [s.id, plain(s.data()) as Data]));
  }

  async groupListing(listingId: string): Promise<Data | null> {
    const snap = await this.db.doc(`tournamentDirectory/${listingId}`).get();
    return snap.exists ? (plain(snap.data()) as Data) : null;
  }
}
