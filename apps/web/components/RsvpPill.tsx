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
  if (!answer) return needs ? <span className="rsvp-pill needs">Needs RSVP</span> : null;
  const going = answer === "going";
  // Tournaments ask who's attending; the rows keep the short answers otherwise.
  const label = going && type === "tournament" ? "Attending" : (labels[answer] ?? answer);
  return (
    <span className={`rsvp-pill${going ? " going" : ""}`}>
      {going && (
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M5 12l5 5L20 7" />
        </svg>
      )}
      {label}
    </span>
  );
}
