// A player's personal schedule (users/{uid}/events, TeamEvent in the app)
// and sharing it with chosen people (docs/requirements.md U11, D4). Viewers
// see each event's title, type, time and place, never its notes, and only
// while the owner keeps them on the list.
import { z } from "zod";

/** Event types a personal event may have (validEventDetails; not meetings). */
export const eventTypes = ["practice", "game", "tournament", "scrimmage", "workout", "social", "other", "pickup"] as const;
export type EventType = (typeof eventTypes)[number];
export const eventTypeLabels: Record<EventType, string> = {
  practice: "Practice",
  game: "Game",
  tournament: "Tournament",
  scrimmage: "Scrimmage",
  workout: "Workout",
  social: "Social",
  other: "Other",
  pickup: "Pickup",
};

/** Most people one calendar is shared with. */
export const calendarViewersMax = 50;
/** Longest stretch one `GET /v1/me/calendar/shared` covers. */
export const sharedCalendarWindowDays = 92;
/** Most events shown from one shared calendar per request. */
export const sharedCalendarEventsMax = 200;

const isoDate = z.iso.datetime({ offset: true, message: "Pick a date and time." });

/**
 * `POST /v1/me/events` and `PATCH /v1/me/events/:id`: a personal event,
 * replaced whole (validMine: no poll, no responses). Times are ISO 8601.
 */
export const personalEventSchema = z
  .strictObject({
    title: z.string().trim().min(1, "Give the event a title.").max(100, "Keep titles under 100 characters."),
    type: z.enum(eventTypes).default("other"),
    startsAt: isoDate,
    endsAt: isoDate.nullable().default(null),
    location: z.string().trim().max(200, "Keep the place under 200 characters.").default(""),
    notes: z.string().max(5000, "Keep notes under 5,000 characters.").default(""),
  })
  .refine((e) => e.endsAt === null || Date.parse(e.endsAt) >= Date.parse(e.startsAt), {
    message: "It can't end before it starts.",
    path: ["endsAt"],
  });
export type PersonalEventRequest = z.input<typeof personalEventSchema>;

/** After `POST /v1/me/events`. */
export interface PersonalEventResult {
  id: string;
}

/** `PUT /v1/me/calendar/viewers`: everyone the caller shares their calendar with. */
export const calendarViewersRequestSchema = z.strictObject({
  viewers: z
    .array(z.string().regex(/^[A-Za-z0-9_-]{1,128}$/))
    .max(calendarViewersMax, `Share with at most ${calendarViewersMax} people.`),
});
export type CalendarViewersRequest = z.input<typeof calendarViewersRequestSchema>;

/** Someone on a share list, or sharing with the caller, as their profile shows them. */
export interface CalendarPerson {
  uid: string;
  name: string;
  username: string | null;
  photoUrl: string | null;
}

/** `GET` / `PUT /v1/me/calendar/viewers`. */
export interface CalendarViewersResponse {
  viewers: CalendarPerson[];
}

/** An event on someone else's shared calendar: no notes. */
export interface SharedCalendarEvent {
  id: string;
  title: string;
  type: EventType;
  startsAt: string;
  endsAt: string | null;
  location: string;
}

/** `GET /v1/me/calendar/shared?from=&to=`: calendars shared with the caller, events starting in [from, to). */
export interface SharedCalendarsResponse {
  calendars: Array<{ owner: CalendarPerson; events: SharedCalendarEvent[] }>;
}
