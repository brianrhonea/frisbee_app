"use client";
import type { ReactNode } from "react";
import { Button } from "./Button";
import "./ui.css";

/**
 * The three "not the content yet" states, one look everywhere (the app's
 * EmptyState, ErrorState and LoadingState). components/StatusViews.tsx's
 * Loading, EmptyState and ErrorNote are these.
 */

/** Still loading: announced as a busy status, with a spinner that stills for reduced motion. */
export function LoadingState({ label = "Loading…" }: { label?: string }) {
  return (
    <p className="muted status-loading ui-loading" role="status" aria-busy="true">
      <span className="ui-spinner" aria-hidden="true" />
      {label}
    </p>
  );
}

/**
 * Nothing there yet: what it means in [children], an optional [title], and the next step as [action].
 * [quiet] is for one inside a card (the card is the frame): no dashed box, left aligned, secondary size.
 */
export function EmptyState({ children, title, action, quiet = false }: { children: ReactNode; title?: string; action?: ReactNode; quiet?: boolean }) {
  return (
    <div className={`empty empty-state ui-empty${quiet ? " ui-empty-quiet" : ""}`}>
      {title ? <b className="ui-empty-title">{title}</b> : null}
      <p>{children}</p>
      {action && <div className="empty-action">{action}</div>}
    </div>
  );
}

/**
 * Something failed: announced at once (`role="alert"`), saying what and, with
 * [onRetry], a Try again button (48 px). Stays in the page's flow.
 */
export function ErrorState({ children, title, onRetry, retryLabel = "Try again" }: { children: ReactNode; title?: string; onRetry?: () => void; retryLabel?: string }) {
  return (
    <div className="ui-error" role="alert">
      <svg className="ui-error-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v6M12 16.5v.01" />
      </svg>
      <div className="ui-error-text">
        {title ? <b>{title}</b> : null}
        <span>{children}</span>
      </div>
      {onRetry && (
        <Button onClick={onRetry}>
          {retryLabel}
        </Button>
      )}
    </div>
  );
}
