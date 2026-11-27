import type { ReactNode } from "react";
import { EmptyState, ErrorState, LoadingState } from "./ui/States";

/**
 * The site's three "not the content yet" states, in one style everywhere:
 * still loading, nothing there (with an optional next step), and an error
 * (with an optional retry). These are the shared LoadingState, EmptyState
 * and ErrorState (components/ui/States.tsx) under the names the pages use.
 */
export { EmptyState };

export function Loading({ label = "Loading…" }: { label?: string }) {
  return <LoadingState label={label} />;
}

export function ErrorNote({ children, onRetry }: { children: ReactNode; onRetry?: () => void }) {
  return <ErrorState onRetry={onRetry}>{children}</ErrorState>;
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
