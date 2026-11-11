import Link from "next/link";
import type { ReactNode } from "react";
import { StoreBadges } from "./StoreBadges";

/** "Get the app": for the not-found page and app-only features. */
export function GetTheApp({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <section className="center-card">
      <img className="center-logo" src="/logo.png" alt="Stall 10" width={96} height={96} />
      <h1>{title}</h1>
      {children ?? (
        <p className="lead">Teams, practices, playbooks and live stats are in the Stall 10 app.</p>
      )}
      <StoreBadges center />
      <p className="web-cta">
        Or <Link href="/community">see what&apos;s happening on the web</Link>.
      </p>
    </section>
  );
}
