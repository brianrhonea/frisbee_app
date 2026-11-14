import { type Firestore, Timestamp } from "firebase-admin/firestore";
import { type Doc, plain } from "../browse/repository.js";
import type { Data } from "../store.js";

/**
 * The queries shared calendars need, which DocStore can't make. Values come
 * back with Timestamps as ISO strings.
 */
export interface CalendarRepository {
  /** Owners whose users/{owner}.calendarViewers lists [uid]. */
  sharersOf(uid: string, limit: number): Promise<string[]>;
  /** [owner]'s personal events starting in [from, to) ms, soonest first. */
  eventsBetween(owner: string, from: number, to: number, limit: number): Promise<Doc[]>;
}

export class FirestoreCalendarRepository implements CalendarRepository {
  constructor(private readonly db: Firestore) {}

  async sharersOf(uid: string, limit: number) {
    const snap = await this.db.collection("users").where("calendarViewers", "array-contains", uid).limit(limit).get();
    return snap.docs.map((d) => d.id);
  }

  async eventsBetween(owner: string, from: number, to: number, limit: number) {
    const snap = await this.db
      .collection(`users/${owner}/events`)
      .where("startsAt", ">=", Timestamp.fromMillis(from))
      .where("startsAt", "<", Timestamp.fromMillis(to))
      .orderBy("startsAt")
      .limit(limit)
      .get();
    return snap.docs.map((d) => ({ id: d.id, data: plain(d.data()) as Data }));
  }
}
