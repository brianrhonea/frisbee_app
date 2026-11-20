// An event shared on the caller's profile (SharedEvent in the app's
// user_post.dart; event_editor_viewmodel.dart's _share): a copy of the
// event's details, so followers who can't open the event see them. The
// posts rule's validSharedEvent and sharesOwnTeamEvent, ported: the copy
// is made here from the stored event (never from the client), and a team's
// event is shared only by someone who manages its schedule. A shared
// calendar's event (the app shares those from its editor too, with no
// teamId) is read only for someone who can edit that calendar, as the
// calendar API checks: the rules never let clients read its events, so the
// copy mustn't show them to anyone else.
import { isPrivateGroup } from "../browse/model.js";
import { publicPageOn, teamEventTypes } from "@stall10/shared";
import type { Caller } from "../auth.js";
import { editableEventsPath } from "../calendar/service.js";
import { ApiError } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { Data, DocStore } from "../store.js";
import { can, clipText } from "../teams/access.js";

const asDate = (v: unknown): Date | null => {
  if (v instanceof Date) return v;
  if (typeof v === "string" && !Number.isNaN(Date.parse(v))) return new Date(v);
  return null;
};

/** The event field of an event post (SharedEvent.toMap). */
export async function sharedEvent(
  store: DocStore,
  caller: Caller,
  ref: { eventId: string; teamId: string | null; calendarId?: string | null },
): Promise<Data> {
  const eventId = docIdParam(ref.eventId);
  const teamId = ref.teamId === null ? null : docIdParam(ref.teamId);
  let teamName: string | null = null;
  let event: Data | null;
  if (teamId) {
    const team = await store.get(`teams/${teamId}`);
    // sharesOwnTeamEvent: can(get(teamPath(e.teamId)).data, 'manageEvents').
    if (!team || !can(team, caller.uid, "manageEvents")) {
      throw new ApiError("permission_denied", "Only people who run this team's schedule can share its events.");
    }
    // A private group's events stay with its members (both apps hide sharing there).
    if (isPrivateGroup(team)) {
      throw new ApiError("failed_precondition", "Events of a community that approves who joins stay with its members.");
    }
    // So do a team's whose public page is off (both apps hide sharing there too).
    if (!publicPageOn(team)) {
      throw new ApiError("failed_precondition", "This team's page is private, so its events stay with its members.");
    }
    teamName = clipText(team.name, 100) || null;
    event = await store.get(`teams/${teamId}/events/${eventId}`);
  } else if (ref.calendarId) {
    event = await store.get(`${await editableEventsPath(store, caller.uid, ref.calendarId)}/${eventId}`);
  } else {
    event = await store.get(`users/${caller.uid}/events/${eventId}`);
  }
  if (!event) throw new ApiError("not_found", "That event doesn't exist anymore.");
  // validSharedEvent: a title of 1–100, a known type, a start time.
  const title = clipText(event.title, 100);
  const startsAt = asDate(event.startsAt);
  const type = (teamEventTypes as readonly string[]).includes(String(event.type)) ? String(event.type) : "other";
  if (!title || !startsAt) throw new ApiError("failed_precondition", "That event needs a title and a start time to share.");
  const endsAt = asDate(event.endsAt);
  const location = clipText(event.location, 200);
  return {
    eventId,
    title,
    type,
    startsAt,
    ...(endsAt && { endsAt }),
    ...(location && { location }),
    ...(teamId && { teamId }),
    ...(teamName && { teamName }),
  };
}
