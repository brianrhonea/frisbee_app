import type { ReactNode } from "react";
import { StatusPill } from "./ui/StatusPill";

/**
 * The member's answer on a schedule row (the app's RsvpStatusPill): Going
 * in turf, Maybe and Can't go neutral, and "Needs RSVP" in amber when
 * [needs] and unanswered. Nothing for an event without RSVPs.
 */
const labels: Record<string, string> = { going: "Going", maybe: "Maybe", notGoing: "Can't go" };

/** A meeting's answer as the schedule's (TeamMeeting.toEvent). */
export const meetingAnswer = (a: string | undefined) =>
  a === "attending" ? "going" : a === "notAttending" ? "notGoing" : undefined;

/** Unanswered and not over yet (the app's ScheduleViewModel.needsRsvp). */
export function needsRsvp(answer: string | undefined, startsAt?: string, endsAt?: string | null): boolean {
  if (answer) return false;
  const end = Date.parse(endsAt || startsAt || "");
  return Number.isNaN(end) || end > Date.now();
}

export function RsvpPill({ answer, type, needs = false }: { answer?: string; type?: string; needs?: boolean }) {
  if (!answer) return needs ? <NeedsPill>Needs RSVP</NeedsPill> : null;
  const going = answer === "going";
  // Tournaments ask who's attending; the rows keep the short answers otherwise.
  const label = going && type === "tournament" ? "Attending" : (labels[answer] ?? answer);
  return (
    <StatusPill tone={going ? "success" : "neutral"} icon={going ? "check" : undefined} className={`rsvp-pill${going ? " going" : ""}${answer === "notGoing" ? " notGoing" : ""}`}>
      {label}
    </StatusPill>
  );
}

/** "Needs RSVP", "Vote": theirs to do (the app's NeedsYouPill). */
export function NeedsPill({ children }: { children: ReactNode }) {
  return (
    <StatusPill tone="attention" className="rsvp-pill needs">
      {children}
    </StatusPill>
  );
}
