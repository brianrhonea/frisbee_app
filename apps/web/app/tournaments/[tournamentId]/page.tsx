import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { TournamentPage } from "@/components/tournaments/TournamentPage";

export const metadata: Metadata = { title: "Tournament" };

type Props = { params: Promise<{ tournamentId: string }>; searchParams: Promise<{ host?: string | string[] }> };

/** A hosted tournament or league: overview, teams, schedule and results. ?host= falls back to that group's tournament. */
export default async function HostedTournamentPage({ params, searchParams }: Props) {
  const { tournamentId } = await params;
  const { host } = await searchParams;
  const fallbackHostId = (Array.isArray(host) ? host[0] : host) || undefined;
  return (
    <div className="page">
      <MembersOnly next={`/tournaments/${encodeURIComponent(tournamentId)}${fallbackHostId ? `?host=${encodeURIComponent(fallbackHostId)}` : ""}`} what="Sign up free or log in to see this event.">
        <TournamentPage tournamentId={tournamentId} fallbackHostId={fallbackHostId} />
      </MembersOnly>
    </div>
  );
}
