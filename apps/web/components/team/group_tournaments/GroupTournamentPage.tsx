"use client";
import {
  type GroupGame,
  type GroupTournamentDoc,
  type GroupTournamentListing,
  type PublicGroupTournament,
  groupEngine,
  groupFormatHasBracket,
  groupFormatHasPools,
  groupGameStageLabels,
  groupTournamentFormatInfo,
  readGroupGame,
} from "@stall10/shared";
import { orderBy } from "firebase/firestore";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { useAuth } from "../../AuthProvider";
import { Dialog } from "@/components/Dialog";
import { FollowButton } from "../../FollowButton";
import { callApi } from "@/lib/client";
import { formatDateTime } from "@/lib/dates";
import { localeFor, useRenderZone } from "@/lib/renderZone";
import { useLiveDoc, useLiveQuery } from "@/lib/live";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { JoinToTakePart } from "../../tournaments/VisitorParts";
import {
  type GroupTournamentView,
  gameDay,
  gameTime,
  playerName,
  sameDay,
  shortDay,
  slotLabel,
  tournamentSummary,
  tournamentView,
  tournamentWhen,
} from "./format";
import "./group_tournaments.css";

type Tab = "schedule" | "standings" | "bracket" | "teams";
/** What a captain can do with a game (GameAction in the app). */
type Action = "report" | "confirm" | "awaiting";

/**
 * A group tournament (/teams/:id/tournaments/:tournamentId): schedule,
 * pools, bracket and teams. Captains report and confirm scores;
 * organizers set any score, seed the bracket, edit and delete it. People
 * who can't see it get its public listing and a Follow button
 * (GroupTournamentScreen in the app).
 */
export function GroupTournamentPage({ tournamentId, publicListing }: { tournamentId: string; publicListing?: PublicGroupTournament | null }) {
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const router = useRouter();
  const member = viewer.state === "member" ? viewer : null;
  const signedIn = viewer.state === "member" || viewer.state === "outsider";
  const uid = signedIn ? viewer.uid : "";
  const organizer = member?.can("manageEvents") ?? false;
  const path = `teams/${teamId}/groupTournaments/${tournamentId}`;
  const doc = useLiveDoc<GroupTournamentDoc>(signedIn ? path : null);
  const readable = !!doc.data;
  const gameDocs = useLiveQuery<Record<string, unknown>>(readable ? `${path}/games` : null, [orderBy("order")], "games");
  const listing = useLiveDoc<GroupTournamentListing>(signedIn ? `tournamentDirectory/${teamId}_${tournamentId}` : null);
  const [tab, setTab] = useState<Tab>("schedule");
  const [open, setOpen] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const t = useMemo(() => (doc.data ? tournamentView(doc.data) : null), [doc.data]);
  const games = useMemo(() => (gameDocs.data ?? []).map((g) => readGroupGame(g.id, g)), [gameDocs.data]);
  const names = useMemo(() => new Map((t?.teams ?? []).map((x) => [x.id, x.name])), [t]);
  const myTeam = t?.teams.find((x) => x.playerIds.includes(uid)) ?? null;
  const api = `/v1/teams/${encodeURIComponent(teamId)}/group-tournaments/${encodeURIComponent(tournamentId)}`;

  async function run(fn: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await fn();
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }

  // Moves teams on if a finished game's bracket update didn't land (it
  // goes with the confirm, so this is rare). Anyone playing may do it;
  // once per set of missing moves.
  const caughtUp = useRef<string>("");
  const pending = groupEngine.pendingFills(games);
  const pendingKey = pending.map((f) => `${f.gameId}:${f.teamA}:${f.teamB}`).join("|");
  useEffect(() => {
    if (!user || !pendingKey || caughtUp.current === pendingKey || (!organizer && !myTeam)) return;
    caughtUp.current = pendingKey;
    void callApi(user, `${api}/advance`, { method: "POST" }).catch(() => undefined);
  }, [user, pendingKey, organizer, myTeam, api]);

  // Visitors (and the server's render) get the public listing, as outsiders do, unless the group is private.
  if (!signedIn && publicListing) {
    const back = (
      <Link href={`/teams/${encodeURIComponent(teamId)}/tournaments`} className="text-btn">
        ← Tournaments
      </Link>
    );
    return <PublicTournament teamId={teamId} listing={publicListing} back={back} visitorNext={`/teams/${encodeURIComponent(teamId)}/tournaments/${encodeURIComponent(tournamentId)}`} />;
  }
  if (viewer.state === "loading" || (signedIn && doc.data === undefined && !doc.error)) {
    return (
      <p className="muted" aria-busy="true">
        Loading…
      </p>
    );
  }
  if (!signedIn) return <MembersOnlySection what="tournaments" />;
  const back = (
    <Link href={`/teams/${encodeURIComponent(teamId)}/tournaments`} className="text-btn">
      ← Tournaments
    </Link>
  );
  if (!t) {
    if (listing.data) return <PublicTournament teamId={teamId} listing={listing.data} back={back} />;
    if (listing.data === undefined && !listing.error) {
      return (
        <p className="muted" aria-busy="true">
          Loading…
        </p>
      );
    }
    return (
      <div className="stack">
        {back}
        <p className="empty">Tournament not available. It may have been deleted, or you&apos;re not on a team in it.</p>
      </div>
    );
  }

  const format = t.settings.format;
  const tabs: Array<[Tab, string]> = [
    ["schedule", "Schedule"],
    ...(groupFormatHasPools(format) ? [["standings", "Standings"] as [Tab, string]] : []),
    ...(groupFormatHasBracket(format) ? [["bracket", "Bracket"] as [Tab, string]] : []),
    ["teams", "Teams"],
  ];
  const shown = tabs.some(([k]) => k === tab) ? tab : "schedule";
  const isCaptainOf = (team: string | null) => team !== null && t.teams.find((x) => x.id === team)?.captainId === uid;
  const actionFor = (g: GroupGame): Action | null => {
    if (!groupEngine.hasTeams(g) || groupEngine.isDone(g)) return null;
    const mineA = isCaptainOf(g.teamA);
    if (!mineA && !isCaptainOf(g.teamB)) return null;
    if (g.status !== "reported" || !g.report) return "report";
    return g.report.byTeam === (mineA ? g.teamA : g.teamB) ? "awaiting" : "confirm";
  };
  const canSetScore = (g: GroupGame) => organizer && groupEngine.hasTeams(g) && !groupEngine.laterGamesPlayed(g, games);
  const champion = groupEngine.championOf(format, games);
  const canSeed = organizer && groupEngine.bracketSeeds(games).length > 0;
  const badge = (a: Action | null) => (a === "report" ? "Report score" : a === "confirm" ? "Confirm score" : a === "awaiting" ? "Waiting for the other captain" : null);

  const tile = (g: GroupGame, withNumber = true) => (
    <GameTile
      key={g.id}
      game={g}
      number={withNumber ? g.order + 1 : null}
      nameA={slotLabel(names, games, g, true)}
      nameB={slotLabel(names, games, g, false)}
      mine={!!myTeam && (g.teamA === myTeam.id || g.teamB === myTeam.id)}
      skipped={groupEngine.skippedGame(g, games)}
      badge={badge(actionFor(g))}
      onOpen={() => setOpen(g.id)}
    />
  );

  const upcoming = myTeam ? groupEngine.gamesToPlay(games).filter((g) => g.teamA === myTeam.id || g.teamB === myTeam.id) : [];
  const openGame = games.find((g) => g.id === open) ?? null;

  return (
    <div className="stack">
      {back}
      <div className="gt-head">
        <div>
          <h2 className="gt-title">{t.name || "Tournament"}</h2>
          <p className="muted small">{tournamentWhen(t.settings.startsAt)}</p>
        </div>
        <div className="gt-head-actions">
          <FollowButton type="tournament" targetId={tournamentId} groupId={teamId} />
          {organizer && (
            <>
              <Link className="btn btn-small" href={`/teams/${encodeURIComponent(teamId)}/tournaments/${encodeURIComponent(tournamentId)}/edit`}>
                Setup
              </Link>
              <button
                type="button"
                className="btn btn-small btn-danger"
                disabled={busy}
                onClick={() => {
                  if (!user || !window.confirm(`Delete ${t.name || "this tournament"}? Its teams, schedule and scores are deleted for everyone.`)) return;
                  void run(() => callApi(user, api, { method: "DELETE" })).then((ok) => ok && router.push(`/teams/${encodeURIComponent(teamId)}/tournaments`));
                }}
              >
                Delete
              </button>
            </>
          )}
        </div>
      </div>
      {error && <p className="form-error">{error}</p>}
      <div className="segmented" role="tablist" aria-label="Tournament">
        {tabs.map(([k, label]) => (
          <button key={k} type="button" role="tab" aria-selected={k === shown} className={k === shown ? "on" : ""} onClick={() => setTab(k)}>
            {label}
          </button>
        ))}
      </div>

      {shown === "schedule" && (
        <div className="stack">
          <p className="muted small">{tournamentSummary(t.settings)}</p>
          {champion && <div className="card gt-champion">🏆 {names.get(champion) ?? "TBD"} wins!</div>}
          {myTeam && (
            <div className="card gt-mine">
              <b>You&apos;re on {myTeam.name}</b>
              {myTeam.captainId === uid ? (
                <span className="muted small">You&apos;re the captain: report your scores</span>
              ) : myTeam.captainId ? (
                <span className="muted small">Captain: {playerName(myTeam, myTeam.captainId)}</span>
              ) : null}
              {upcoming[0] && (
                <span className="muted small">
                  Next: {gameTime(upcoming[0].startsAt)}, field {upcoming[0].field}
                </span>
              )}
            </div>
          )}
          {canSeed && (
            <div className="home-actions">
              <button type="button" className="btn btn-primary" disabled={busy} onClick={() => user && void run(() => callApi(user, `${api}/seed-bracket`, { method: "POST" }))}>
                Pools are done: seed the bracket
              </button>
            </div>
          )}
          {gameDocs.error && <p className="form-error">{gameDocs.error}</p>}
          {gameDocs.data && games.length === 0 && (
            <p className="empty">
              {organizer ? "No schedule yet. Open Setup to make teams and publish it." : "The schedule will appear here once organizers publish it."}
            </p>
          )}
          {games.map((g, i) => (
            <div key={g.id} className="stack gt-day">
              {t.settings.laterDays.length > 0 && g.startsAt && (i === 0 || !sameDay(games[i - 1]!.startsAt, g.startsAt)) && (
                <h3 className="gt-day-title">{gameDay(g.startsAt)}</h3>
              )}
              {tile(g)}
            </div>
          ))}
        </div>
      )}

      {shown === "standings" && <Standings games={games} names={names} awaiting={groupEngine.awaitingSeeds(games) && !canSeed} />}

      {shown === "bracket" && <Bracket games={games} tile={tile} />}

      {shown === "teams" && (
        <div className="gt-teams">
          {t.teams.map((team) => (
            <div key={team.id} className={`card${team.id === myTeam?.id ? " gt-mine" : ""}`}>
              <h3 className="card-title">{team.name}</h3>
              {team.playerIds.length === 0 && <p className="muted small">No players yet.</p>}
              <ul className="gt-players">
                {team.playerIds.map((p) => (
                  <li key={p}>
                    {p === team.captainId ? "★ " : ""}
                    {playerName(team, p)}
                    {p === team.captainId ? " (captain)" : ""}
                    {p === uid ? " · you" : ""}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}

      {openGame && (
        <GameSheet
          key={openGame.id}
          t={t}
          game={openGame}
          nameA={slotLabel(names, games, openGame, true)}
          nameB={slotLabel(names, games, openGame, false)}
          action={actionFor(openGame)}
          canSetScore={canSetScore(openGame)}
          skipped={groupEngine.skippedGame(openGame, games)}
          reportedBy={openGame.report ? (names.get(openGame.report.byTeam) ?? "A captain") : ""}
          api={`${api}/games/${encodeURIComponent(openGame.id)}`}
          onClose={() => setOpen(null)}
        />
      )}
    </div>
  );
}

function GameTile({
  game: g,
  number,
  nameA,
  nameB,
  mine = false,
  skipped = false,
  badge,
  onOpen,
}: {
  game: GroupGame;
  number: number | null;
  nameA: string;
  nameB: string;
  mine?: boolean;
  skipped?: boolean;
  badge?: string | null;
  onOpen?: () => void;
}) {
  const winner = groupEngine.winnerOf(g);
  const side = (team: string | null) => (winner === null ? "" : winner === team ? "gt-won" : "gt-lost");
  const status = skipped ? "Not needed" : g.status === "done" ? "Final" : g.status === "reported" ? "Score reported" : null;
  const body = (
    <>
      <span className="gt-game-meta">
        {[number !== null ? `Game ${number}` : null, g.startsAt ? gameTime(g.startsAt) : null, `Field ${g.field}`, g.label].filter(Boolean).join(" · ")}
      </span>
      <span className={`gt-side ${side(g.teamA)}`}>
        <span>{nameA}</span>
        {g.status === "done" && <b>{g.scoreA}</b>}
      </span>
      <span className={`gt-side ${side(g.teamB)}`}>
        <span>{nameB}</span>
        {g.status === "done" && <b>{g.scoreB}</b>}
      </span>
      {(status || badge) && (
        <span className="gt-game-status">
          {status && <span className="muted small">{status}</span>}
          {badge && <span className="gt-badge">{badge}</span>}
        </span>
      )}
    </>
  );
  return onOpen ? (
    <button type="button" className={`card gt-game${mine ? " gt-mine" : ""}`} onClick={onOpen}>
      {body}
    </button>
  ) : (
    <div className={`card gt-game${mine ? " gt-mine" : ""}`}>{body}</div>
  );
}

function Standings({ games, names, awaiting }: { games: GroupGame[]; names: Map<string, string>; awaiting: boolean }) {
  const pools = [...groupEngine.poolTeams(games).entries()];
  if (pools.length === 0) return <p className="empty">No pool games yet.</p>;
  return (
    <div className="stack">
      {pools.map(([pool, teams]) => (
        <div key={pool} className="card table-scroll">
          {pools.length > 1 && <h3 className="card-title">Pool {pool}</h3>}
          <table className="data-table">
            <thead>
              <tr>
                <th className="narrow">#</th>
                <th>Team</th>
                <th className="num">W</th>
                <th className="num">L</th>
                <th className="num">+/-</th>
              </tr>
            </thead>
            <tbody>
              {groupEngine
                .standings(
                  teams,
                  games.filter((g) => g.pool === pool),
                )
                .map((s, i) => {
                  const diff = s.pointsFor - s.pointsAgainst;
                  return (
                    <tr key={s.teamId}>
                      <td className="narrow">{i + 1}</td>
                      <td>{names.get(s.teamId) ?? "TBD"}</td>
                      <td className="num">{s.wins}</td>
                      <td className="num">{s.losses}</td>
                      <td className="num">{`${diff > 0 ? "+" : ""}${diff}`}</td>
                    </tr>
                  );
                })}
            </tbody>
          </table>
        </div>
      ))}
      {awaiting && <p className="muted small">The bracket is seeded from these standings once every pool game is final.</p>}
    </div>
  );
}

function Bracket({ games, tile }: { games: GroupGame[]; tile: (g: GroupGame, withNumber?: boolean) => React.ReactNode }) {
  const columns = new Map<string, GroupGame[]>();
  for (const g of games) {
    if (!groupEngine.isBracket(g.stage)) continue;
    const key = `${g.stage}|${g.round}`;
    columns.set(key, [...(columns.get(key) ?? []), g]);
  }
  if (columns.size === 0) return <p className="empty">No bracket games yet.</p>;
  const title = (g: GroupGame) =>
    g.stage === "losers" ? `Losers' round ${g.round}` : g.stage === "grandFinal" || g.stage === "reset" ? groupGameStageLabels[g.stage] : g.label;
  return (
    <div className="gt-bracket">
      {[...columns.values()].map((col) => (
        <div key={`${col[0]!.stage}${col[0]!.round}`} className="gt-column">
          <h3 className="gt-day-title">{title(col[0]!)}</h3>
          {col.map((g) => tile(g))}
        </div>
      ))}
    </div>
  );
}

/**
 * A game's details and what the viewer can do: report, confirm or dispute
 * a score as a captain, or set it as an organizer.
 */
function GameSheet({
  t,
  game: g,
  nameA,
  nameB,
  action,
  canSetScore,
  skipped,
  reportedBy,
  api,
  onClose,
}: {
  t: GroupTournamentView;
  game: GroupGame;
  nameA: string;
  nameB: string;
  action: Action | null;
  canSetScore: boolean;
  skipped: boolean;
  reportedBy: string;
  api: string;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const [entering, setEntering] = useState<null | { mode: "report" | "score"; title: string; message?: string }>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const r = g.report;

  async function send(path: string, method: string, body: object) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, path, { method, body });
      setEntering(null);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog label={`Game ${g.order + 1}`} onClose={onClose} className="card gt-sheet" dismissOnBackdrop>
        <div className="gt-head">
          <h2 className="card-title">
            Game {g.order + 1} · {g.label}
          </h2>
          <button type="button" className="text-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="muted small">{[g.startsAt ? `${shortDay(g.startsAt)} ${gameTime(g.startsAt)}` : null, `Field ${g.field}`, `to ${t.settings.scoreCap}`].filter(Boolean).join(" · ")}</p>
        <GameTile game={g} number={null} nameA={nameA} nameB={nameB} />
        {skipped ? (
          <p className="small">Not needed: the winners&apos; bracket champion won the final.</p>
        ) : !groupEngine.hasTeams(g) ? (
          <p className="small">Teams are decided by earlier games.</p>
        ) : null}
        {r && g.status !== "done" && (
          <p className="small">
            {reportedBy} reported {nameA} {r.scoreA}, {nameB} {r.scoreB}.
          </p>
        )}
        {entering ? (
          <ScoreForm
            title={entering.title}
            message={entering.message}
            nameA={nameA}
            nameB={nameB}
            initialA={g.scoreA ?? r?.scoreA ?? null}
            initialB={g.scoreB ?? r?.scoreB ?? null}
            busy={busy}
            onCancel={() => setEntering(null)}
            onSubmit={(s) => void send(entering.mode === "report" ? `${api}/report` : `${api}/score`, entering.mode === "report" ? "POST" : "PUT", s)}
          />
        ) : (
          <div className="home-actions">
            {action === "report" && (
              <button
                type="button"
                className="btn btn-primary"
                disabled={busy}
                onClick={() => setEntering({ mode: "report", title: "Report the score", message: "The other captain confirms it before it counts." })}
              >
                Report score
              </button>
            )}
            {action === "confirm" && r && (
              <>
                <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void send(`${api}/confirm`, "POST", { scoreA: r.scoreA, scoreB: r.scoreB })}>
                  Confirm {r.scoreA}–{r.scoreB}
                </button>
                <button
                  type="button"
                  className="btn"
                  disabled={busy}
                  onClick={() => setEntering({ mode: "report", title: "Report a different score", message: "The other captain will be asked to confirm yours instead." })}
                >
                  That&apos;s not right
                </button>
              </>
            )}
            {action === "awaiting" && (
              <>
                <p className="small">Waiting for the other captain to confirm.</p>
                <button type="button" className="btn" disabled={busy} onClick={() => setEntering({ mode: "report", title: "Change your report" })}>
                  Change my report
                </button>
              </>
            )}
            {canSetScore && (
              <button
                type="button"
                className="text-btn"
                disabled={busy}
                onClick={() =>
                  setEntering({
                    mode: "score",
                    title: g.status === "done" ? "Correct the score" : "Set the final score",
                    message: "As an organizer, this is final right away.",
                  })
                }
              >
                {g.status === "done" ? "Correct the score" : "Set final score"}
              </button>
            )}
          </div>
        )}
        {error && <p className="form-error">{error}</p>}
    </Dialog>
  );
}

function ScoreForm({
  title,
  message,
  nameA,
  nameB,
  initialA,
  initialB,
  busy,
  onCancel,
  onSubmit,
}: {
  title: string;
  message?: string;
  nameA: string;
  nameB: string;
  initialA: number | null;
  initialB: number | null;
  busy: boolean;
  onCancel: () => void;
  onSubmit: (s: { scoreA: number; scoreB: number }) => void;
}) {
  const [a, setA] = useState(initialA === null ? "" : String(initialA));
  const [b, setB] = useState(initialB === null ? "" : String(initialB));
  const [why, setWhy] = useState<string | null>(null);
  function submit(e: FormEvent) {
    e.preventDefault();
    const sa = /^\d+$/.test(a.trim()) ? Number(a) : null;
    const sb = /^\d+$/.test(b.trim()) ? Number(b) : null;
    const problem = groupEngine.scoreError(sa, sb);
    if (problem) return setWhy(problem);
    onSubmit({ scoreA: sa!, scoreB: sb! });
  }
  return (
    <form className="settings-form" onSubmit={submit}>
      <h3 className="card-title">{title}</h3>
      {message && <p className="small muted">{message}</p>}
      <div className="form-grid">
        <label>
          {nameA}
          <input inputMode="numeric" value={a} autoFocus onChange={(e) => setA(e.target.value.replace(/\D/g, ""))} />
        </label>
        <label>
          {nameB}
          <input inputMode="numeric" value={b} onChange={(e) => setB(e.target.value.replace(/\D/g, ""))} />
        </label>
      </div>
      {why && <p className="form-error">{why}</p>}
      <div className="home-actions">
        <button type="submit" className="btn btn-primary" disabled={busy}>
          Submit
        </button>
        <button type="button" className="btn" onClick={onCancel}>
          Cancel
        </button>
      </div>
    </form>
  );
}

/** What someone outside the tournament sees: when, how it's played, and Follow. */
/** The public listing; [visitorNext] (signed out) swaps Follow for a sign-up prompt that comes back there. */
function PublicTournament({ teamId, listing, back, visitorNext }: { teamId: string; listing: GroupTournamentListing; back: React.ReactNode; visitorNext?: string }) {
  // Server-rendered for visitors: UTC until the page hydrates (useRenderZone).
  const zone = useRenderZone();
  const f = (iso: string, o: Intl.DateTimeFormatOptions) => formatDateTime(iso, { ...o, timeZone: zone }, localeFor(zone));
  const day = (iso: string) => f(iso, { weekday: "long", month: "short", day: "numeric" });
  const when = listing.endsOn ? `${day(listing.startsAt)} to ${day(listing.endsOn)}` : `${day(listing.startsAt)} at ${f(listing.startsAt, { hour: "numeric", minute: "2-digit" })}`;
  const status = listing.status === "scheduled" ? "Schedule published" : listing.status === "done" ? "Finished" : "Teams are being picked";
  return (
    <div className="stack">
      {back}
      <div className="card stack">
        <h2 className="gt-title">{listing.name || "Tournament"}</h2>
        <p>{when}</p>
        <p>
          {groupTournamentFormatInfo[listing.format]?.label ?? "Tournament"} <span className="muted small">· {status}</span>
        </p>
        {visitorNext ? (
          <JoinToTakePart next={visitorNext} />
        ) : (
          <>
            <div>
              <FollowButton type="tournament" targetId={listing.tournamentId} groupId={teamId} />
            </div>
            <p className="muted small">Follow to see its updates on Home. To play, join the community and sign up there.</p>
          </>
        )}
        <div>
          <Link className="btn btn-small" href={`/teams/${encodeURIComponent(teamId)}`}>
            Open the community
          </Link>
        </div>
      </div>
    </div>
  );
}
