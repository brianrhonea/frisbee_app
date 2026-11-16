import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { TournamentForEveryone } from "@/components/tournaments/PublicTournament";
import { TournamentPage } from "@/components/tournaments/TournamentPage";
import { formatDate, serverLocale } from "@/lib/dates";
import { loadTournament, loadTournamentNews } from "@/lib/tournamentPage";

type Search = { host?: string | string[]; division?: string | string[] };
type Props = { params: Promise<{ tournamentId: string }>; searchParams: Promise<Search> };

const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) || undefined;

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { tournamentId } = await params;
  // The overview only: the same for every division.
  const page = await loadTournament(tournamentId);
  if (!page) return { title: "Tournament" };
  const t = page.tournament;
  const day = t.startsOn ? formatDate(t.startsOn, { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" }, serverLocale) : "";
  const when = [day, t.location].filter(Boolean).join(" · ");
  return {
    title: t.name || "Tournament",
    description: (t.description || `${t.name} hosted by ${t.hostName}. ${when}. Schedule, scores and standings on Stall 10.`).slice(0, 200),
  };
}

/**
 * A hosted tournament or league: overview, teams, schedule and results.
 * Published events are server-rendered from the public page, so visitors
 * and search engines see them; members get the live page. Drafts and
 * private groups' events stay members-only (the host's managers open
 * drafts there). ?host= falls back to that group's tournament.
 */
export default async function HostedTournamentPage({ params, searchParams }: Props) {
  const { tournamentId } = await params;
  const { host, division } = await searchParams;
  const fallbackHostId = first(host);
  const page = await loadTournament(tournamentId, first(division));
  if (!page) {
    return (
      <div className="page">
        <MembersOnly next={`/tournaments/${encodeURIComponent(tournamentId)}${fallbackHostId ? `?host=${encodeURIComponent(fallbackHostId)}` : ""}`} what="Sign up free or log in to see this event.">
          <TournamentPage tournamentId={tournamentId} fallbackHostId={fallbackHostId} />
        </MembersOnly>
      </div>
    );
  }
  const news = await loadTournamentNews(page.tournament.hostId, tournamentId);
  return (
    <div className="page">
      <TournamentForEveryone page={page} news={news} fallbackHostId={fallbackHostId} />
    </div>
  );
}
