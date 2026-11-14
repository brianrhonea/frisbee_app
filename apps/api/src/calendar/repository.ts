import { type Firestore, type QuerySnapshot, Timestamp } from "firebase-admin/firestore";
import { type Doc, plain } from "../browse/repository.js";
import type { Data } from "../store.js";

/**
 * The queries calendars need, which DocStore can't make. Values come back
 * with Timestamps as ISO strings.
 */
export interface CalendarRepository {
  /** Calendars whose memberIds hold [uid] (the owner is a member of their own). */
  calendarsOf(uid: string, limit: number): Promise<Doc[]>;
  /** Calendars [uid] owns. */
  ownedBy(uid: string, limit: number): Promise<Doc[]>;
  /** Events in [collection] starting in [from, to) ms, soonest first. */
  eventsBetween(collection: string, from: number, to: number, limit: number): Promise<Doc[]>;
}

export class FirestoreCalendarRepository implements CalendarRepository {
  constructor(private readonly db: Firestore) {}

  private static docs(snap: QuerySnapshot): Doc[] {
    return snap.docs.map((d) => ({ id: d.id, data: plain(d.data()) as Data }));
  }

  async calendarsOf(uid: string, limit: number) {
    const snap = await this.db.collection("calendars").where("memberIds", "array-contains", uid).limit(limit).get();
    return FirestoreCalendarRepository.docs(snap);
  }

  async ownedBy(uid: string, limit: number) {
    const snap = await this.db.collection("calendars").where("ownerId", "==", uid).limit(limit).get();
    return FirestoreCalendarRepository.docs(snap);
  }

  async eventsBetween(collection: string, from: number, to: number, limit: number) {
    const snap = await this.db
      .collection(collection)
      .where("startsAt", ">=", Timestamp.fromMillis(from))
      .where("startsAt", "<", Timestamp.fromMillis(to))
      .orderBy("startsAt")
      .limit(limit)
      .get();
    return FirestoreCalendarRepository.docs(snap);
  }
}
