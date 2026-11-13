"use client";

export default function ErrorPage({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <section className="center-card">
      <h1>Something went wrong</h1>
      <p className="lead">We couldn&apos;t load this page. Try again in a moment.</p>
      <button className="btn btn-primary" type="button" onClick={reset}>
        Try again
      </button>
    </section>
  );
}
