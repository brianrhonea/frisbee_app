"use client";

import "./site.css";
import "./app.css";
import { ErrorView } from "@/components/ErrorView";

// Replaces the root layout when it fails, so it brings its own <html>, <body> and styles.
export default function GlobalError({
  error,
  retry,
  reset,
}: {
  error: unknown;
  retry?: () => void;
  reset?: () => void;
}) {
  return (
    <html lang="en">
      <body>
        <ErrorView error={error} onRetry={() => (retry ?? reset)?.()} home="a" />
      </body>
    </html>
  );
}
