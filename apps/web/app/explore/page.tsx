import type { EventsPage, PublicHostedList } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { Discover } from "@/components/explore/Explore";
import { parseFilter } from "@/components/explore/filters";
import { ForVisitors } from "@/components/ForVisitors";
import { getPublicOrNull } from "@/lib/api";
import { loadTournaments } from "@/lib/tournamentPage";

// Rendered per request (the API answers themselves are cached for a minute),
// so an API outage during a build can't be baked into the page.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Discover",
  description: "Find ultimate tournaments, leagues, pickup, teams and communities on Stall 10. No account needed to look around.",
};

type Props = { searchParams: Promise<{ q?: string | string[]; only?: string | string[] }> };

const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

/** Public events and tournaments for the page, or null when the API can't answer (the browser asks again). */
async function loadEvents(): Promise<EventsPage | null> {
  try {
    return await getPublicOrNull<EventsPage>("/v1/public/events");
  } catch {
    return null;
  }
}

/**
 * Discover (the app's Discover tab; it was Explore and Events): search and
 * everything coming up, for members and visitors alike. The public lists
 * are server-rendered, so visitors and search engines see them without
 * waiting for sign-in; player search stays members only.
 */
export default async function DiscoverPage({ searchParams }: Props) {
  const params = await searchParams;
  const q = first(params.q)?.trim().slice(0, 100) ?? "";
  const only = parseFilter(first(params.only));
  const [list, events] = await Promise.all([loadTournaments(), loadEvents()]);
  return (
    <div className="page">
      <div className="page-head">
        <h1>Discover</h1>
        <p>
          Tournaments, leagues, pickup, teams and communities.
          <ForVisitors> No account needed to look around.</ForVisitors>
        </p>
      </div>
      <Link className="learn-entry" href="/learn">
        <span>
          <b>New to ultimate?</b>
          <small>Learn to play: the rules, the throws and the spirit of the game.</small>
        </span>
        <span aria-hidden="true">Learn to play →</span>
      </Link>
      <Discover initialQuery={q} initialFilter={only} tournaments={list?.tournaments ?? null} events={events} />
    </div>
  );
}
