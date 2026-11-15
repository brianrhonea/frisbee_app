"use client";
// "Share with my followers" on a new event (the app's event editor share
// switch and EventEditorViewModel._share): after the event is saved, a post
// on the member's profile carries a copy of its details (the API copies
// them from the stored event). RSVPs and notes stay on the event.
import type { User } from "firebase/auth";
import { callApi } from "@/lib/client";
import "./share_event.css";

/** The app's message box caps at 1,000 characters. */
export const shareMessageMax = 1000;

export interface ShareChoice {
  on: boolean;
  message: string;
}

export function ShareEventField({ value, onChange }: { value: ShareChoice; onChange: (v: ShareChoice) => void }) {
  return (
    <fieldset className="share-event">
      <label className="check-row">
        <input type="checkbox" checked={value.on} onChange={(e) => onChange({ ...value, on: e.target.checked })} />
        Share with my followers
      </label>
      <small className="muted">
        Posts it on your profile, so the people who follow you and the team&apos;s members see it in their feed. RSVPs and notes stay here.
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

/** Posts the saved event; false when it couldn't (the event is saved either way). */
export async function shareEvent(user: User, teamId: string | null, eventId: string, message: string): Promise<boolean> {
  try {
    await callApi(user, "/v1/posts", { method: "POST", body: { body: message.trim(), shareEvent: { eventId, teamId } } });
    return true;
  } catch {
    return false;
  }
}
