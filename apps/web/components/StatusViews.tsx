import type { ReactNode } from "react";

/**
 * The site's three "not the content yet" states, in one style everywhere:
 * still loading, nothing there (with an optional next step), and an error
 * (with an optional retry).
 */
export function Loading({ label = "Loading…" }: { label?: string }) {
  return (
    <p className="muted status-loading" role="status" aria-busy="true">
      {label}
    </p>
  );
}

export function EmptyState({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="empty empty-state">
      <p>{children}</p>
      {action && <div className="empty-action">{action}</div>}
    </div>
  );
}

export function ErrorNote({ children, onRetry }: { children: ReactNode; onRetry?: () => void }) {
  return (
    <p className="form-error error-note" role="alert">
      {children}
      {onRetry && (
        <>
          {" "}
          <button type="button" className="text-btn" onClick={onRetry}>
            Try again
          </button>
        </>
      )}
    </p>
  );
}

/**
 * A live list's three states before its rows: [Loading], [ErrorNote] or an
 * [EmptyState] saying [empty] (with [emptyAction]); otherwise [children].
 */
export function LiveList<T>({
  live,
  empty,
  emptyAction,
  children,
}: {
  live: { data?: T[]; error: string | null };
  empty: ReactNode;
  emptyAction?: ReactNode;
  children: (rows: T[]) => ReactNode;
}) {
  if (live.error) return <ErrorNote>{live.error}</ErrorNote>;
  if (!live.data) return <Loading />;
  if (live.data.length === 0) return <EmptyState action={emptyAction}>{empty}</EmptyState>;
  return <>{children(live.data)}</>;
}
