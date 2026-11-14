// Calendars, as in Outlook or Apple Calendar (docs/requirements.md U11, D4).
// Everyone has "My calendar" (its events are users/{uid}/events, as the app
// has always stored them) and may make more (calendars/{id}/events). The
// owner invites people as "Can view" or "Can edit"; an invitee sees nothing
// until they accept. Viewers see each event's title, type, time and place,
// never its notes; editors and the owner see and change everything. All
// shared reads and writes go through the API, which checks the calendar's
// members on every request. A private subscription link (ICS) keeps
// Outlook, Apple and Google Calendar in step.
import { z } from "zod";

/** Event types a calendar event may have (validEventDetails; not meetings). */
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
/** What the editors offer for a personal calendar (EventType.editableFor(community: false)). */
export const calendarEventTypes = eventTypes.filter((t) => t !== "pickup");

/** A calendar's colors, as named swatches the apps draw in their own palette. */
export const calendarColors = ["green", "blue", "purple", "pink", "red", "orange", "yellow", "teal", "gray"] as const;
export type CalendarColor = (typeof calendarColors)[number];
/** Hex values for each color (the website and the app use the same). */
export const calendarColorHex: Record<CalendarColor, string> = {
  green: "#3fa34d",
  blue: "#2f7fd8",
  purple: "#8b5cf6",
  pink: "#e0559b",
  red: "#e5484d",
  orange: "#f08c2e",
  yellow: "#d9a400",
  teal: "#14a3a3",
  gray: "#7c8a86",
};

/** Roles on a calendar. The owner is the one who made it. */
export const calendarRoles = ["owner", "edit", "view"] as const;
export type CalendarRole = (typeof calendarRoles)[number];
/** What an invite or a member change may grant. */
export const shareRoles = ["edit", "view"] as const;
export type ShareRole = (typeof shareRoles)[number];
export const shareRoleLabels: Record<ShareRole, string> = { edit: "Can edit", view: "Can view" };

/** Most calendars one person owns ("My calendar" included). */
export const ownedCalendarsMax = 20;
/** Most people on one calendar, members and pending invites together. */
export const calendarPeopleMax = 50;
/** Longest calendar name. */
export const calendarNameMax = 60;
/** Longest stretch one events request covers. */
export const calendarWindowDays = 92;
/** Most events returned per calendar per request. */
export const calendarEventsMax = 300;
/** "My calendar" when its owner hasn't renamed it. */
export const defaultCalendarName = "My calendar";

/** Someone on a calendar, as their profile shows them. */
export interface CalendarPerson {
  uid: string;
  name: string;
  username: string | null;
  photoUrl: string | null;
}

/** A calendar as the caller sees it. [members] and [pending] are the owner's to see. */
export interface CalendarInfo {
  id: string;
  name: string;
  color: CalendarColor;
  owner: CalendarPerson;
  /** The caller's role. */
  role: CalendarRole;
  /** "My calendar": its events live in users/{owner}/events; it can't be deleted. */
  isDefault: boolean;
  /** Owner only: everyone on it, the owner first. */
  members?: Array<CalendarPerson & { role: CalendarRole }>;
  /** Owner only: people invited who haven't answered. */
  pending?: Array<CalendarPerson & { role: ShareRole }>;
}

/** `GET /v1/me/calendars`. */
export interface CalendarsResponse {
  calendars: CalendarInfo[];
}

/** `POST /v1/me/calendars` and `PATCH /v1/calendars/:id`. */
export const calendarRequestSchema = z.strictObject({
  name: z.string().trim().min(1, "Give the calendar a name.").max(calendarNameMax, `Keep names under ${calendarNameMax} characters.`),
  color: z.enum(calendarColors).default("green"),
});
export type CalendarRequest = z.input<typeof calendarRequestSchema>;
export const calendarPatchSchema = calendarRequestSchema.partial();

const uid = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);

/** `POST /v1/calendars/:id/invites`: invite someone, or change a pending invite's role. */
export const calendarInviteRequestSchema = z.strictObject({ uid, role: z.enum(shareRoles).default("view") });
export type CalendarInviteRequest = z.input<typeof calendarInviteRequestSchema>;

/** `PATCH /v1/calendars/:id/members/:uid`. */
export const calendarRoleRequestSchema = z.strictObject({ role: z.enum(shareRoles) });

/** An invite waiting for the caller (users/{uid}/calendarInvites/{calendarId}). */
export interface CalendarInvite {
  calendarId: string;
  calendarName: string;
  color: CalendarColor;
  role: ShareRole;
  from: CalendarPerson;
  createdAt: string | null;
}

/** `GET /v1/me/calendar-invites`. */
export interface CalendarInvitesResponse {
  invites: CalendarInvite[];
}

const isoDate = z.iso.datetime({ offset: true, message: "Pick a date and time." });

/**
 * `POST /v1/calendars/:id/events` and `PATCH /v1/calendars/:id/events/:eventId`:
 * an event, replaced whole (validMine: no poll, no responses).
 */
export const calendarEventSchema = z
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
export type CalendarEventRequest = z.input<typeof calendarEventSchema>;

/** After `POST /v1/calendars/:id/events`. */
export interface CalendarEventResult {
  id: string;
}

/** An event on one of the caller's calendars. [notes] is left out for viewers. */
export interface CalendarEvent {
  id: string;
  calendarId: string;
  title: string;
  type: EventType;
  startsAt: string;
  endsAt: string | null;
  location: string;
  notes?: string;
}

/** `GET /v1/me/calendar-events?from=&to=`: events starting in [from, to) on every calendar the caller is on. */
export interface CalendarEventsResponse {
  events: CalendarEvent[];
}

/** `GET` / `POST /v1/me/calendar-feed`: the caller's private subscription link. */
export interface CalendarFeedResponse {
  /** https link (Outlook on the web, Google Calendar: "From URL"); null until made. */
  url: string | null;
  /** The same as webcal:// (Apple Calendar and Outlook open it to subscribe). */
  webcal: string | null;
}
