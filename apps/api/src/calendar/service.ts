import {
  type CalendarPerson,
  type CalendarViewersResponse,
  calendarViewersMax,
  calendarViewersRequestSchema,
  type EventType,
  eventTypes,
  type PersonalEventResult,
  personalEventSchema,
  type SharedCalendarEvent,
  type SharedCalendarsResponse,
  sharedCalendarEventsMax,
  sharedCalendarWindowDays,
} from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import { clip, nameMax, text } from "../posts/author.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import type { CalendarRepository } from "./repository.js";

const p = {
  user: (uid: string) => `users/${uid}`,
  profile: (uid: string) => `profiles/${uid}`,
  event: (uid: string, id: string) => `users/${uid}/events/${id}`,
  events: (uid: string) => `users/${uid}/events`,
};

const dayMs = 86_400_000;
const noEvent = () => new ApiError("not_found", "This event was deleted.");

const viewersOf = (user: Data | null): string[] =>
  Array.isArray(user?.calendarViewers) ? user.calendarViewers.filter((v): v is string => typeof v === "string") : [];

const iso = (v: unknown): string | null =>
  v instanceof Date ? v.toISOString() : typeof v === "string" && !Number.isNaN(Date.parse(v)) ? v : null;

/**
 * A player's personal schedule (users/{uid}/events) and who they share it
 * with (users/{uid}.calendarViewers, docs/requirements.md D4). The Admin
 * SDK skips firestore.rules, so writes check validMine: only the caller's
 * own events, no poll, the event's details within validEventDetails'
 * limits. Viewers get title, type, time and place, never notes, and only
 * while they're on the owner's list: it's checked on every read, and
 * nothing is copied to them.
 */
export class CalendarService {
  constructor(
    private readonly store: DocStore,
    private readonly repo: CalendarRepository,
  ) {}

  private async person(uid: string): Promise<CalendarPerson | null> {
    const profile = await this.store.get(p.profile(uid));
    if (!profile) return null;
    const username = text(profile.username) || null;
    return {
      uid,
      name: clip(text(profile.name) || (username ? `@${username}` : "Player"), nameMax),
      username,
      photoUrl: typeof profile.photoUrl === "string" && profile.photoUrl ? profile.photoUrl : null,
    };
  }

  private async people(uids: string[]): Promise<CalendarPerson[]> {
    const found = await Promise.all(uids.map((u) => this.person(u)));
    return found.filter((x): x is CalendarPerson => x !== null);
  }

  /** `GET /v1/me/calendar/viewers`: who the caller shares with (deleted accounts left out). */
  async viewers(caller: Caller): Promise<CalendarViewersResponse> {
    return { viewers: await this.people(viewersOf(await this.store.get(p.user(caller.uid)))) };
  }

  /** `PUT /v1/me/calendar/viewers`: replaces the list. An empty list stops sharing. */
  async setViewers(caller: Caller, body: unknown): Promise<CalendarViewersResponse> {
    const r = calendarViewersRequestSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const uids = [...new Set(r.data.viewers)];
    if (uids.includes(caller.uid)) throw new ApiError("invalid_argument", "Your calendar is already yours.");
    if (uids.length > calendarViewersMax) {
      throw new ApiError("invalid_argument", `Share with at most ${calendarViewersMax} people.`);
    }
    const viewers = await this.people(uids);
    if (viewers.length !== uids.length) {
      throw new ApiError("invalid_argument", "Someone on the list doesn't have a Stall 10 profile.");
    }
    await this.store.transact(async (tx) => {
      tx.merge(p.user(caller.uid), { calendarViewers: uids });
    });
    return { viewers };
  }

  /** `GET /v1/me/calendar/shared`: events starting in [from, to) on calendars shared with the caller. */
  async shared(caller: Caller, rawFrom: unknown, rawTo: unknown): Promise<SharedCalendarsResponse> {
    const from = typeof rawFrom === "string" ? Date.parse(rawFrom) : NaN;
    const to = typeof rawTo === "string" ? Date.parse(rawTo) : NaN;
    if (!Number.isFinite(from) || !Number.isFinite(to) || to <= from) {
      throw new ApiError("invalid_argument", "Give from and to as dates, from first.");
    }
    if (to - from > sharedCalendarWindowDays * dayMs) {
      throw new ApiError("invalid_argument", `Ask for at most ${sharedCalendarWindowDays} days at a time.`);
    }
    const owners = (await this.repo.sharersOf(caller.uid, calendarViewersMax)).filter((o) => o !== caller.uid);
    const calendars = await Promise.all(
      owners.map(async (owner) => {
        // The query found them; the owner's own list decides.
        const [user, person] = await Promise.all([this.store.get(p.user(owner)), this.person(owner)]);
        if (!person || !viewersOf(user).includes(caller.uid)) return null;
        const docs = await this.repo.eventsBetween(owner, from, to, sharedCalendarEventsMax);
        const events = docs.flatMap((d): SharedCalendarEvent[] => {
          const startsAt = iso(d.data.startsAt);
          if (!startsAt) return [];
          const type = eventTypes.includes(d.data.type as EventType) ? (d.data.type as EventType) : "other";
          return [
            {
              id: d.id,
              title: text(d.data.title) || "Event",
              type,
              startsAt,
              endsAt: iso(d.data.endsAt),
              location: text(d.data.location),
            },
          ];
        });
        return { owner: person, events };
      }),
    );
    return {
      calendars: calendars
        .filter((c): c is NonNullable<typeof c> => c !== null)
        .sort((a, b) => a.owner.name.localeCompare(b.owner.name)),
    };
  }

  /** The event as the app saves it (TeamEvent.toEditableMap, poll null). */
  private record(body: unknown): Data {
    const r = personalEventSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const e = r.data;
    return {
      title: e.title,
      type: e.type,
      startsAt: new Date(e.startsAt),
      endsAt: e.endsAt === null ? null : new Date(e.endsAt),
      location: e.location,
      notes: e.notes,
      poll: null,
    };
  }

  /** `POST /v1/me/events`. */
  async create(caller: Caller, body: unknown): Promise<PersonalEventResult> {
    const data = this.record(body);
    const id = this.store.newId(p.events(caller.uid));
    await this.store.transact(async (tx) => {
      tx.create(p.event(caller.uid, id), { ...data, createdAt: serverTime, updatedAt: serverTime });
    });
    return { id };
  }

  /** `PATCH /v1/me/events/:id`: replaces its details. */
  async update(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const data = this.record(body);
    await this.store.transact(async (tx) => {
      if (!(await tx.get(p.event(caller.uid, id)))) throw noEvent();
      tx.update(p.event(caller.uid, id), { ...data, updatedAt: serverTime });
    });
  }

  /** `DELETE /v1/me/events/:id`. Already gone is fine. */
  async remove(caller: Caller, rawId: unknown): Promise<void> {
    const id = docIdParam(rawId);
    await this.store.transact(async (tx) => {
      tx.delete(p.event(caller.uid, id));
    });
  }
}
