import Link from "next/link";
import type { ReactNode } from "react";
import { NeedsPill, RsvpPill } from "../RsvpPill";
import { DateBadge } from "./DateBadge";
import { StatusPill } from "./StatusPill";
import "./ui.css";

/**
 * One event (the app's EventCard): the date badge, the title, a line of
 * details, and the states a schedule row shows: your RSVP answer (or "Needs
 * RSVP"), Cancelled and Repeats. Cancelled and Repeats are words in pills as
 * well as a struck-through title, so colour is never the only signal.
 *
 * With [href] the whole card is one link (its name is the title and details);
 * without it the card is plain content, for rows that hold their own buttons.
 */
export interface EventCardProps {
  startsAt?: string | null;
  title: string;
  /** Time, place: one line under the title. */
  meta?: ReactNode;
  /** "going", "maybe" or "notGoing"; leave out for an event without RSVPs. */
  answer?: string;
  /** Unanswered and still to come: shows "Needs RSVP". */
  needsRsvp?: boolean;
  cancelled?: boolean;
  recurring?: boolean;
  href?: string;
  /** Extra pills or actions after the details. */
  children?: ReactNode;
}

export function EventCard({ startsAt, title, meta, answer, needsRsvp = false, cancelled = false, recurring = false, href, children }: EventCardProps) {
  const body = (
    <>
      <DateBadge startsAt={startsAt} />
      <span className="ui-event-body">
        <b className="ui-event-title">{title}</b>
        {meta ? <small className="ui-event-meta">{meta}</small> : null}
      </span>
    </>
  );
  return (
    <article className={`ui-event${cancelled ? " ui-event-cancelled" : ""}`} data-cancelled={cancelled || undefined}>
      {href ? (
        <Link className="ui-event-main" href={href}>
          {body}
        </Link>
      ) : (
        <div className="ui-event-main">{body}</div>
      )}
      <span className="ui-event-pills">
        {cancelled ? (
          <StatusPill tone="error" icon="alert">
            Cancelled
          </StatusPill>
        ) : (
          <RsvpPill answer={answer} needs={needsRsvp} />
        )}
        {recurring ? <StatusPill tone="neutral">Repeats</StatusPill> : null}
        {children}
      </span>
    </article>
  );
}

export { NeedsPill };
