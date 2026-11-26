"use client";

import { ErrorView } from "@/components/ErrorView";

// `retry` re-fetches the segment (this Next.js version); `reset` is the older name.
export default function ErrorPage({ error, retry, reset }: { error: unknown; retry?: () => void; reset?: () => void }) {
  return <ErrorView error={error} onRetry={() => (retry ?? reset)?.()} />;
}
