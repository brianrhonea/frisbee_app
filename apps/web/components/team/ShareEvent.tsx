"use client";
// "Share with my followers" on a new event (the app's event editor share
// switch and EventEditorViewModel._share): after the event is saved, a post
// on the member's profile carries a copy of its details (the API copies
// them from the stored event). RSVPs and notes stay on the event.
import type { User } from "firebase/auth";
import { callApi } from "@/lib/client";
import "./share_event.css";

/** The app's message box caps at 1,000 characters. */
const shareMessageMax = 1000;

export interface ShareChoice {
  on: boolean;
  message: string;
}

/** [personal]: an event on one of the member's calendars, which has no team members to reach. */
export function ShareEventField({ value, onChange, personal = false }: { value: ShareChoice; onChange: (v: ShareChoice) => void; personal?: boolean }) {
  return (
    <fieldset className="share-event">
      <label className="check-row">
        <input type="checkbox" checked={value.on} onChange={(e) => onChange({ ...value, on: e.target.checked })} />
        Share with my followers
      </label>
      <small className="muted">
        {personal
          ? "Posts it on your profile, so the people who follow you see it in their feed. RSVPs and notes stay here."
          : "Posts it on your profile, so the people who follow you and the team's members see it in their feed. RSVPs and notes stay here."}
      </small>
      {value.on && (
        <label>
          Say something (optional)
          <textarea
            rows={2}
            maxLength={shareMessageMax}
            placeholder="Come out and play!"
            value={value.message}
            onChange={(e) => onChange({ ...value, message: e.target.value })}
          />
        </label>
      )}
    </fieldset>
  );
}

/**
 * Posts the saved event, from team [teamId]'s schedule or (teamId null)
 * calendar [calendarId]'s; false when it couldn't (the event is saved
 * either way).
 */
export async function shareEvent(user: User, teamId: string | null, eventId: string, message: string, calendarId: string | null = null): Promise<boolean> {
  try {
    await callApi(user, "/v1/posts", { method: "POST", body: { body: message.trim(), shareEvent: { eventId, teamId, ...(calendarId && { calendarId }) } } });
    return true;
  } catch {
    return false;
  }
}
