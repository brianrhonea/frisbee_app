"use client";
// A division's bracket on its own page, /tournaments/:id/bracket?division=
// (the app's HostedBracketScreen, opened from Results' "Open bracket"):
// the whole bracket with room to scroll, the division chips, and each
// game's card with what the viewer can do. Members get the live state;
// visitors the server's public page, read-only.
import type { PublicHostedPage, PublicTeamPost } from "@stall10/shared";
import { divisionLabel } from "@stall10/shared";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef } from "react";
import { useAuth } from "@/components/AuthProvider";
import { usePublicTournamentState } from "./PublicTournament";
import { BracketView, DivisionPicker, NoDivisions } from "./TournamentGames";
import { type TournamentState, useTournament } from "./useTournament";
import "./tournaments.css";

const noNews: PublicTeamPost[] = [];

/** The live bracket for members, the server's for visitors (and while sign-in is still loading). */
export function BracketForEveryone({ page, divisionId }: { page: PublicHostedPage; divisionId?: string }) {
  const { user } = useAuth();
  if (user) return <MemberBracket tournamentId={page.tournament.id} divisionId={divisionId} />;
  return <VisitorBracket page={page} />;
}

/** A member's bracket, from the live state; [divisionId] is picked once the divisions are in. */
export function MemberBracket({ tournamentId, divisionId }: { tournamentId: string; divisionId?: string }) {
  const s = useTournament(tournamentId);
  const picked = useRef(false);
  const router = useRouter();
  const path = usePathname();
  const has = !!divisionId && s.divisions.some((d) => d.id === divisionId);
  useEffect(() => {
    if (picked.current || !has || !divisionId) return;
    picked.current = true;
    s.selectDivision(divisionId);
  }, [has, divisionId, s]);
  // The chips keep the address in step, so a copied link opens the same division.
  const state: TournamentState = {
    ...s,
    selectDivision: (id: string | null) => {
      s.selectDivision(id);
      if (id) router.replace(`${path}?division=${encodeURIComponent(id)}`, { scroll: false });
    },
  };
  if (!s.loaded) return <p className="muted" aria-busy="true">Loading…</p>;
  if (!s.t) return <p className="empty">This event isn&apos;t here: it may have been removed, or it hasn&apos;t been published yet.</p>;
  return <BracketPage s={state} />;
}

function VisitorBracket({ page }: { page: PublicHostedPage }) {
  const router = useRouter();
  const path = usePathname();
  const params = useSearchParams();
  const next = `${path}${params.size ? `?${params.toString()}` : ""}`;
  // Another division's games come from the server: ?division= rereads the page.
  const select = useCallback(
    (divisionId: string) => {
      const q = new URLSearchParams(params);
      q.set("division", divisionId);
      router.replace(`${path}?${q.toString()}`, { scroll: false });
    },
    [params, path, router],
  );
  const s = usePublicTournamentState(page, noNews, next, select);
  return <BracketPage s={s} />;
}

function BracketPage({ s }: { s: TournamentState }) {
  const t = s.t!;
  const d = s.division;
  const hasBracket = s.games.some((g) => g.stage !== "pool");
  return (
    <div className="stack hosted-page">
      <header className="bracket-page-head">
        <small className="muted">
          <Link href={`/tournaments/${encodeURIComponent(s.id)}?tab=results`}>← {t.name}</Link>
        </small>
        <h1>Bracket</h1>
        {d && <p className="hosted-meta">{divisionLabel(d)}</p>}
      </header>
      <DivisionPicker s={s} />
      {!d ? (
        <NoDivisions s={s} />
      ) : hasBracket ? (
        <BracketView s={s} />
      ) : (
        <p className="empty">No bracket yet. The bracket shows here once the schedule is out and pool play is done.</p>
      )}
    </div>
  );
}
