"use client";
import Link from "next/link";
import { useEffect } from "react";
import { reportClientError } from "@/lib/errorReport";

/**
 * The error page body shared by app/error.tsx and app/global-error.tsx.
 * [home] "a" is a plain link, for global-error where the router may be what broke.
 */
export function ErrorView({
  error,
  onRetry,
  home = "link",
}: {
  error: unknown;
  onRetry: () => void;
  home?: "link" | "a";
}) {
  useEffect(() => {
    reportClientError(error);
  }, [error]);
  return (
    <section className="center-card" role="alert">
      <h1>Something went wrong</h1>
      <p className="lead">We couldn&apos;t load this page. Try again in a moment.</p>
      <button className="btn btn-primary" type="button" onClick={onRetry}>
        Try again
      </button>
      <p>{home === "a" ? <a href="/">Go to the home page</a> : <Link href="/">Go to the home page</Link>}</p>
    </section>
  );
}
