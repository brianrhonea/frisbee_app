import { createHash, randomBytes } from "node:crypto";
import {
  type CalendarColor,
  type CalendarEvent,
  type CalendarEventResult,
  type CalendarEventsResponse,
  type CalendarFeedResponse,
  type CalendarInfo,
  type CalendarInvitesResponse,
  type CalendarPerson,
  type CalendarRole,
  type CalendarsResponse,
  calendarColors,
  calendarEventSchema,
  calendarEventsMax,
  calendarInviteRequestSchema,
  calendarPatchSchema,
  calendarPeopleMax,
  calendarRequestSchema,
  calendarRoleRequestSchema,
  calendarWindowDays,
  defaultCalendarName,
  type EventType,
  eventTypes,
  type IcsEvent,
  icsCalendar,
  ownedCalendarsMax,
  type ShareRole,
  shareRoles,
} from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import { checkNotMuted, clip, nameMax, text } from "../posts/author.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import type { CalendarRepository } from "./repository.js";

const p = {
  profile: (uid: string) => `profiles/${uid}`,
  calendar: (id: string) => `calendars/${id}`,
  invite: (uid: string, calendarId: string) => `users/${uid}/calendarInvites/${calendarId}`,
  invites: (uid: string) => `users/${uid}/calendarInvites`,
  feed: (hash: string) => `calendarFeeds/${hash}`,
  feedOwner: (uid: string) => `calendarFeedOwners/${uid}`,
};

const dayMs = 86_400_000;
/** Most calendars anyone is on (their own and others'). */
const listedMax = 100;
/** The subscription feed covers a month back and a year ahead. */
const feedPastDays = 31;
const feedAheadDays = 366;

const noCalendar = () => new ApiError("not_found", "This calendar was deleted, or you're not on it.");
const noEvent = () => new ApiError("not_found", "This event was deleted.");
const ownerOnly = () => new ApiError("permission_denied", "Only the calendar's owner can do that.");

const iso = (v: unknown): string | null =>
  v instanceof Date ? v.toISOString() : typeof v === "string" && !Number.isNaN(Date.parse(v)) ? v : null;

const roleMap = <R extends string>(v: unknown, allowed: readonly R[]): Record<string, R> =>
  v && typeof v === "object" && !Array.isArray(v)
    ? Object.fromEntries(Object.entries(v).filter((e): e is [string, R] => allowed.includes(e[1] as R)))
    : {};

/** A calendars/{id} document. */
interface Cal {
  id: string;
  ownerId: string;
  name: string;
  color: CalendarColor;
  members: Record<string, CalendarRole>;
  pending: Record<string, ShareRole>;
}

function parse(id: string, d: Data): Cal | null {
  const ownerId = text(d.ownerId);
  if (!ownerId) return null;
  const members = roleMap(d.members, ["owner", "edit", "view"] as const);
  members[ownerId] = "owner";
  return {
    id,
    ownerId,
    name: text(d.name) || defaultCalendarName,
    color: calendarColors.includes(d.color as CalendarColor) ? (d.color as CalendarColor) : "green",
    members,
    pending: roleMap(d.pending, shareRoles),
  };
}

/** "My calendar" has its owner's uid for id; its events are where the app has always kept them. */
const isDefault = (c: Cal) => c.id === c.ownerId;
const eventsOf = (c: Cal) => (isDefault(c) ? `users/${c.ownerId}/events` : `calendars/${c.id}/events`);
const canEdit = (role: CalendarRole | undefined) => role === "owner" || role === "edit";

/** The hash a feed token is stored under; the token itself is only on its owner's record. */
export const feedHash = (token: string) => createHash("sha256").update(token).digest("hex");
const tokenPattern = /^[A-Za-z0-9_-]{24,64}$/;

/**
 * Calendars as in Outlook or Apple Calendar (docs/requirements.md D4).
 * calendars/{id} holds the owner, name, color, members ({uid: role},
 * mirrored in memberIds for queries) and pending invites; the invitee's
 * copy is users/{uid}/calendarInvites/{id}, which a function turns into a
 * push. Nobody sees a calendar until they accept. Clients only read
 * calendars they're on; every other read and every write goes through
 * here, which checks the caller's role each time. Viewers never get notes.
 */
export class CalendarService {
  constructor(
    private readonly store: DocStore,
    private readonly repo: CalendarRepository,
    private readonly now: () => number = Date.now,
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

  private async people(uids: string[]): Promise<Map<string, CalendarPerson>> {
    const found = await Promise.all(uids.map((u) => this.person(u)));
    return new Map(found.filter((x): x is CalendarPerson => x !== null).map((x) => [x.uid, x]));
  }

  private async load(rawId: unknown): Promise<Cal> {
    const id = docIdParam(rawId);
    const d = await this.store.get(p.calendar(id));
    const cal = d && parse(id, d);
    if (!cal) throw noCalendar();
    return cal;
  }

  /** The caller's calendar, or not_found if they aren't on it (so nobody learns it exists). */
  private async mine(caller: Caller, rawId: unknown): Promise<{ cal: Cal; role: CalendarRole }> {
    const cal = await this.load(rawId);
    const role = cal.members[caller.uid];
    if (!role) throw noCalendar();
    return { cal, role };
  }

  private async owned(caller: Caller, rawId: unknown): Promise<Cal> {
    const { cal, role } = await this.mine(caller, rawId);
    if (role !== "owner") throw ownerOnly();
    return cal;
  }

  /** "My calendar", made the first time it's needed. */
  private async ensureDefault(uid: string): Promise<void> {
    if (await this.store.get(p.calendar(uid))) return;
    await this.store.transact(async (tx) => {
      if (await tx.get(p.calendar(uid))) return;
      tx.create(p.calendar(uid), {
        ownerId: uid,
        name: defaultCalendarName,
        color: "green",
        members: { [uid]: "owner" },
        memberIds: [uid],
        pending: {},
        createdAt: serverTime,
        updatedAt: serverTime,
      });
    });
  }

  private async info(cal: Cal, uid: string): Promise<CalendarInfo> {
    const role = cal.members[uid];
    const owner = role === "owner";
    const uids = owner ? [...Object.keys(cal.members), ...Object.keys(cal.pending)] : [cal.ownerId];
    const people = await this.people([...new Set(uids)]);
    const ownerPerson = people.get(cal.ownerId) ?? { uid: cal.ownerId, name: "Player", username: null, photoUrl: null };
    const base: CalendarInfo = {
      id: cal.id,
      name: cal.name,
      color: cal.color,
      owner: ownerPerson,
      role,
      isDefault: isDefault(cal),
    };
    if (!owner) return base;
    const members = Object.entries(cal.members)
      .flatMap(([u, r]) => {
        const person = people.get(u);
        return person ? [{ ...person, role: r }] : [];
      })
      .sort((a, b) => (a.role === "owner" ? -1 : b.role === "owner" ? 1 : a.name.localeCompare(b.name)));
    const pending = Object.entries(cal.pending)
      .flatMap(([u, r]) => {
        const person = people.get(u);
        return person ? [{ ...person, role: r }] : [];
      })
      .sort((a, b) => a.name.localeCompare(b.name));
    return { ...base, members, pending };
  }

  private async calendarsOf(uid: string): Promise<Cal[]> {
    const docs = await this.repo.calendarsOf(uid, listedMax);
    // The query found them; each calendar's own members map decides.
    return docs.map((d) => parse(d.id, d.data)).filter((c): c is Cal => c !== null && c.members[uid] !== undefined);
  }

  /** `GET /v1/me/calendars`: "My calendar" first, then the caller's others, then ones shared with them. */
  async list(caller: Caller): Promise<CalendarsResponse> {
    await this.ensureDefault(caller.uid);
    const cals = await this.calendarsOf(caller.uid);
    const infos = await Promise.all(cals.map((c) => this.info(c, caller.uid)));
    const rank = (c: CalendarInfo) => (c.isDefault && c.role === "owner" ? 0 : c.role === "owner" ? 1 : 2);
    infos.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
    return { calendars: infos };
  }

  /** `POST /v1/me/calendars`. */
  async create(caller: Caller, body: unknown): Promise<CalendarInfo> {
    const r = calendarRequestSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    await checkNotMuted(this.store, caller.uid, this.now());
    await this.ensureDefault(caller.uid);
    if ((await this.repo.ownedBy(caller.uid, ownedCalendarsMax + 1)).length >= ownedCalendarsMax) {
      throw new ApiError("failed_precondition", `You can have up to ${ownedCalendarsMax} calendars.`);
    }
    const id = this.store.newId("calendars");
    await this.store.transact(async (tx) => {
      tx.create(p.calendar(id), {
        ownerId: caller.uid,
        name: r.data.name,
        color: r.data.color,
        members: { [caller.uid]: "owner" },
        memberIds: [caller.uid],
        pending: {},
        createdAt: serverTime,
        updatedAt: serverTime,
      });
    });
    const cal: Cal = { id, ownerId: caller.uid, name: r.data.name, color: r.data.color, members: { [caller.uid]: "owner" }, pending: {} };
    return this.info(cal, caller.uid);
  }

  /** `PATCH /v1/calendars/:id`: name and color (owner). */
  async rename(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const r = calendarPatchSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const cal = await this.owned(caller, rawId);
    const change: Data = { updatedAt: serverTime };
    if (r.data.name !== undefined) change.name = r.data.name;
    if (r.data.color !== undefined) change.color = r.data.color;
    await this.store.transact(async (tx) => {
      if (!(await tx.get(p.calendar(cal.id)))) throw noCalendar();
      tx.update(p.calendar(cal.id), change);
    });
  }

  /** `DELETE /v1/calendars/:id` (owner; not "My calendar"): the calendar, its invites, then its events. */
  async remove(caller: Caller, rawId: unknown): Promise<void> {
    const cal = await this.owned(caller, rawId);
    if (isDefault(cal)) throw new ApiError("failed_precondition", "You can't delete My calendar.");
    await this.store.transact(async (tx) => {
      const d = await tx.get(p.calendar(cal.id));
      const now = d && parse(cal.id, d);
      if (!now) return;
      for (const uid of Object.keys(now.pending)) tx.delete(p.invite(uid, cal.id));
      tx.delete(p.calendar(cal.id));
    });
    // Nobody can reach them now; clear them out in pieces.
    for (;;) {
      const batch = await this.store.list(eventsOf(cal), 400);
      if (batch.length === 0) break;
      await this.store.transact(async (tx) => {
        for (const e of batch) tx.delete(`${eventsOf(cal)}/${e.id}`);
      });
    }
  }

  /** `POST /v1/calendars/:id/invites`: invite someone, or change a pending invite's role (owner). */
  async invite(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const r = calendarInviteRequestSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const { uid, role } = r.data;
    const cal = await this.owned(caller, rawId);
    if (uid === caller.uid) throw new ApiError("invalid_argument", "This calendar is already yours.");
    await checkNotMuted(this.store, caller.uid, this.now());
    if (!(await this.person(uid))) throw new ApiError("not_found", "That player doesn't have a Stall 10 profile.");
    await this.store.transact(async (tx) => {
      const d = await tx.get(p.calendar(cal.id));
      const now = d && parse(cal.id, d);
      if (!now) throw noCalendar();
      const existing = await tx.get(p.invite(uid, cal.id));
      if (now.members[uid]) throw new ApiError("already_exists", "They're already on this calendar.");
      const count = Object.keys(now.members).length + Object.keys(now.pending).length;
      if (!now.pending[uid] && count >= calendarPeopleMax) {
        throw new ApiError("failed_precondition", `A calendar can have up to ${calendarPeopleMax} people.`);
      }
      tx.update(p.calendar(cal.id), { pending: { ...now.pending, [uid]: role }, updatedAt: serverTime });
      tx.set(p.invite(uid, cal.id), {
        calendarId: cal.id,
        calendarName: now.name,
        color: now.color,
        role,
        fromId: caller.uid,
        createdAt: existing?.createdAt instanceof Date ? existing.createdAt : serverTime,
      });
    });
  }

  /** `DELETE /v1/calendars/:id/invites/:uid`: withdraw an invite (owner). */
  async cancelInvite(caller: Caller, rawId: unknown, rawUid: unknown): Promise<void> {
    const uid = docIdParam(rawUid);
    const cal = await this.owned(caller, rawId);
    await this.store.transact(async (tx) => {
      const d = await tx.get(p.calendar(cal.id));
      const now = d && parse(cal.id, d);
      if (!now) throw noCalendar();
      const { [uid]: _gone, ...rest } = now.pending;
      tx.update(p.calendar(cal.id), { pending: rest, updatedAt: serverTime });
      tx.delete(p.invite(uid, cal.id));
    });
  }

  /** `PATCH /v1/calendars/:id/members/:uid`: Can view or Can edit (owner). */
  async setRole(caller: Caller, rawId: unknown, rawUid: unknown, body: unknown): Promise<void> {
    const uid = docIdParam(rawUid);
    const r = calendarRoleRequestSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const cal = await this.owned(caller, rawId);
    await this.store.transact(async (tx) => {
      const d = await tx.get(p.calendar(cal.id));
      const now = d && parse(cal.id, d);
      if (!now) throw noCalendar();
      const current = now.members[uid];
      if (!current) throw new ApiError("not_found", "They're not on this calendar.");
      if (current === "owner") throw new ApiError("invalid_argument", "The owner can always edit.");
      tx.update(p.calendar(cal.id), { members: { ...now.members, [uid]: r.data.role }, updatedAt: serverTime });
    });
  }

  /** `DELETE /v1/calendars/:id/members/:uid`: the owner removes someone, or someone leaves. */
  async removeMember(caller: Caller, rawId: unknown, rawUid: unknown): Promise<void> {
    const uid = docIdParam(rawUid);
    const { cal, role } = await this.mine(caller, rawId);
    if (uid !== caller.uid && role !== "owner") throw ownerOnly();
    if (uid === cal.ownerId) throw new ApiError("invalid_argument", "The owner can't leave their own calendar.");
    await this.store.transact(async (tx) => {
      const d = await tx.get(p.calendar(cal.id));
      const now = d && parse(cal.id, d);
      if (!now || !now.members[uid]) return;
      const { [uid]: _gone, ...rest } = now.members;
      tx.update(p.calendar(cal.id), { members: rest, memberIds: Object.keys(rest), updatedAt: serverTime });
    });
  }

  /** `GET /v1/me/calendar-invites`: invites still waiting (withdrawn ones are left out). */
  async invites(caller: Caller): Promise<CalendarInvitesResponse> {
    const docs = await this.store.list(p.invites(caller.uid), listedMax);
    const found = await Promise.all(
      docs.map(async (doc) => {
        const d = await this.store.get(p.calendar(doc.id));
        const cal = d && parse(doc.id, d);
        const role = cal?.pending[caller.uid];
        if (!cal || !role) return null;
        const from = await this.person(cal.ownerId);
        if (!from) return null;
        return {
          calendarId: cal.id,
          calendarName: cal.name,
          color: cal.color,
          role,
          from,
          createdAt: iso(doc.data.createdAt),
        };
      }),
    );
    return {
      invites: found
        .filter((x): x is NonNullable<typeof x> => x !== null)
        .sort((a, b) => (b.createdAt ?? "").localeCompare(a.createdAt ?? "")),
    };
  }

  /** `POST /v1/me/calendar-invites/:id/accept`: join with the role the owner picked. */
  async accept(caller: Caller, rawId: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const joined = await this.store.transact(async (tx) => {
      const d = await tx.get(p.calendar(id));
      const cal = d && parse(id, d);
      const role = cal?.pending[caller.uid];
      if (!cal || !role) {
        tx.delete(p.invite(caller.uid, id));
        return false;
      }
      const { [caller.uid]: _accepted, ...pending } = cal.pending;
      const members = { ...cal.members, [caller.uid]: role };
      tx.update(p.calendar(id), { members, memberIds: Object.keys(members), pending, updatedAt: serverTime });
      tx.delete(p.invite(caller.uid, id));
      return true;
    });
    if (!joined) throw new ApiError("not_found", "This invite was withdrawn.");
  }

  /** `POST /v1/me/calendar-invites/:id/decline`. Already gone is fine. */
  async decline(caller: Caller, rawId: unknown): Promise<void> {
    const id = docIdParam(rawId);
    await this.store.transact(async (tx) => {
      const d = await tx.get(p.calendar(id));
      const cal = d && parse(id, d);
      if (cal?.pending[caller.uid]) {
        const { [caller.uid]: _declined, ...pending } = cal.pending;
        tx.update(p.calendar(id), { pending, updatedAt: serverTime });
      }
      tx.delete(p.invite(caller.uid, id));
    });
  }

  private eventOf(cal: Cal, role: CalendarRole, d: { id: string; data: Data }): CalendarEvent | null {
    const startsAt = iso(d.data.startsAt);
    if (!startsAt) return null;
    const type = eventTypes.includes(d.data.type as EventType) ? (d.data.type as EventType) : "other";
    return {
      id: d.id,
      calendarId: cal.id,
      title: text(d.data.title) || "Event",
      type,
      startsAt,
      endsAt: iso(d.data.endsAt),
      location: text(d.data.location),
      ...(role !== "view" && { notes: typeof d.data.notes === "string" ? d.data.notes : "" }),
    };
  }

  private async eventsBetween(cals: Cal[], uid: string, from: number, to: number) {
    const lists = await Promise.all(
      cals.map(async (cal) => {
        const docs = await this.repo.eventsBetween(eventsOf(cal), from, to, calendarEventsMax);
        return docs.flatMap((d) => {
          const e = this.eventOf(cal, cal.members[uid], d);
          return e ? [{ cal, e }] : [];
        });
      }),
    );
    return lists.flat().sort((a, b) => a.e.startsAt.localeCompare(b.e.startsAt));
  }

  /** `GET /v1/me/calendar-events`: events starting in [from, to) on every calendar the caller is on. */
  async events(caller: Caller, rawFrom: unknown, rawTo: unknown): Promise<CalendarEventsResponse> {
    const from = typeof rawFrom === "string" ? Date.parse(rawFrom) : NaN;
    const to = typeof rawTo === "string" ? Date.parse(rawTo) : NaN;
    if (!Number.isFinite(from) || !Number.isFinite(to) || to <= from) {
      throw new ApiError("invalid_argument", "Give from and to as dates, from first.");
    }
    if (to - from > calendarWindowDays * dayMs) {
      throw new ApiError("invalid_argument", `Ask for at most ${calendarWindowDays} days at a time.`);
    }
    await this.ensureDefault(caller.uid);
    const found = await this.eventsBetween(await this.calendarsOf(caller.uid), caller.uid, from, to);
    return { events: found.map((x) => x.e) };
  }

  /** `GET /v1/calendars/:id/events/:eventId`: one event, for editing (no notes for viewers). */
  async event(caller: Caller, rawId: unknown, rawEventId: unknown): Promise<CalendarEvent> {
    const eventId = docIdParam(rawEventId);
    const { cal, role } = await this.mine(caller, rawId);
    const d = await this.store.get(`${eventsOf(cal)}/${eventId}`);
    const e = d && this.eventOf(cal, role, { id: eventId, data: d });
    if (!e) throw noEvent();
    return e;
  }

  /** The event as the app saves it (TeamEvent.toEditableMap, poll null): validMine's fields, nothing more. */
  private record(body: unknown): Data {
    const r = calendarEventSchema.safeParse(body ?? {});
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

  private async editable(caller: Caller, rawId: unknown): Promise<Cal> {
    const { cal, role } = await this.mine(caller, rawId);
    if (!canEdit(role)) throw new ApiError("permission_denied", "You can view this calendar but not change it.");
    return cal;
  }

  /** `POST /v1/calendars/:id/events` (owner or Can edit). */
  async addEvent(caller: Caller, rawId: unknown, body: unknown): Promise<CalendarEventResult> {
    const data = this.record(body);
    if (rawId === caller.uid) await this.ensureDefault(caller.uid);
    const cal = await this.editable(caller, rawId);
    await checkNotMuted(this.store, caller.uid, this.now());
    const id = this.store.newId(eventsOf(cal));
    await this.store.transact(async (tx) => {
      tx.create(`${eventsOf(cal)}/${id}`, { ...data, createdAt: serverTime, updatedAt: serverTime });
    });
    return { id };
  }

  /** `PATCH /v1/calendars/:id/events/:eventId`: replaces its details. */
  async updateEvent(caller: Caller, rawId: unknown, rawEventId: unknown, body: unknown): Promise<void> {
    const eventId = docIdParam(rawEventId);
    const data = this.record(body);
    const cal = await this.editable(caller, rawId);
    const path = `${eventsOf(cal)}/${eventId}`;
    await this.store.transact(async (tx) => {
      if (!(await tx.get(path))) throw noEvent();
      tx.update(path, { ...data, updatedAt: serverTime });
    });
  }

  /** `DELETE /v1/calendars/:id/events/:eventId`. Already gone is fine. */
  async removeEvent(caller: Caller, rawId: unknown, rawEventId: unknown): Promise<void> {
    const eventId = docIdParam(rawEventId);
    const cal = await this.editable(caller, rawId);
    await this.store.transact(async (tx) => {
      tx.delete(`${eventsOf(cal)}/${eventId}`);
    });
  }

  private static links(base: string, token: unknown): CalendarFeedResponse {
    if (typeof token !== "string" || !token) return { url: null, webcal: null };
    const url = `${base.replace(/\/+$/, "")}/v1/ical/${token}.ics`;
    return { url, webcal: url.replace(/^https?:\/\//, "webcal://") };
  }

  /** `GET /v1/me/calendar-feed`. */
  async feed(caller: Caller, base: string): Promise<CalendarFeedResponse> {
    return CalendarService.links(base, (await this.store.get(p.feedOwner(caller.uid)))?.token);
  }

  /** `POST /v1/me/calendar-feed`: a new link; the old one stops working. */
  async resetFeed(caller: Caller, base: string): Promise<CalendarFeedResponse> {
    const token = randomBytes(24).toString("base64url");
    const hash = feedHash(token);
    await this.store.transact(async (tx) => {
      const old = await tx.get(p.feedOwner(caller.uid));
      if (typeof old?.hash === "string" && old.hash) tx.delete(p.feed(old.hash));
      tx.set(p.feed(hash), { uid: caller.uid, createdAt: serverTime });
      tx.set(p.feedOwner(caller.uid), { token, hash, createdAt: serverTime });
    });
    return CalendarService.links(base, token);
  }

  /** `DELETE /v1/me/calendar-feed`: turns the link off. */
  async stopFeed(caller: Caller): Promise<void> {
    await this.store.transact(async (tx) => {
      const old = await tx.get(p.feedOwner(caller.uid));
      if (typeof old?.hash === "string" && old.hash) tx.delete(p.feed(old.hash));
      tx.delete(p.feedOwner(caller.uid));
    });
  }

  /**
   * `GET /v1/ical/:token.ics`: every calendar the link's owner is on, as
   * iCalendar. Membership is looked up on each request, so someone removed
   * from a calendar stops seeing it at the next refresh. Null for an
   * unknown token.
   */
  async ical(token: string): Promise<string | null> {
    if (!tokenPattern.test(token)) return null;
    const owner = await this.store.get(p.feed(feedHash(token)));
    const uid = typeof owner?.uid === "string" ? owner.uid : "";
    if (!uid) return null;
    const now = this.now();
    const cals = await this.calendarsOf(uid);
    const found = await this.eventsBetween(cals, uid, now - feedPastDays * dayMs, now + feedAheadDays * dayMs);
    const events: IcsEvent[] = found.map(({ cal, e }) => {
      const where = isDefault(cal) && cal.ownerId === uid ? "" : `Calendar: ${cal.name}`;
      return {
        uid: `${cal.id}-${e.id}@stall10.app`,
        title: e.title,
        startsAt: e.startsAt,
        endsAt: e.endsAt,
        location: e.location,
        description: [e.notes ?? "", where].filter(Boolean).join("\n\n"),
      };
    });
    return icsCalendar({ name: "Stall 10", events, now: new Date(now).toISOString(), refreshHours: 1 });
  }
}

