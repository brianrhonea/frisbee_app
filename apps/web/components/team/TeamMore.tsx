"use client";
import { orderBy, where } from "firebase/firestore";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { LocalTime } from "../LocalTime";
import { type Doc, useLiveQuery } from "@/lib/live";
import { useTeamHub } from "./TeamContext";
import { MembersOnlySection, moreTabs } from "./TeamNav";

type Point = { x: number; y: number };
interface Play {
  name?: string;
  category?: string;
  notes?: string;
  elements?: Array<{ id: string; kind?: string; position?: Point; label?: string }>;
  arrows?: Array<{ id: string; kind?: string; points?: Point[] }>;
  steps?: unknown[];
  updatedAt?: string;
}
interface Video {
  title?: string;
  description?: string;
  youtubeId?: string;
  file?: { path?: string; name?: string };
  createdAt?: string;
  authorName?: string;
}
interface StatsGame {
  opponent?: string;
  date?: string;
  gameTo?: number;
  finished?: boolean;
  points?: Array<{ result?: string }>;
}
interface GroupTournament {
  name?: string;
  startsAt?: string;
  endsOn?: string;
  status?: string;
  format?: string;
  teams?: unknown[];
}

const categories: Record<string, string> = { offense: "Offense", defense: "Defense", pull: "Pull", endzone: "Endzone" };

/**
 * The rest of the hub (spec §4, More): a team's playbook, videos, stats and
 * tournaments; a community's tournaments. Tabs in the URL (?tab=).
 */
export function TeamMore() {
  const { teamId, kind, viewer } = useTeamHub();
  const params = useSearchParams();
  const pathname = usePathname();
  const tabs = kind === "team" ? moreTabs.team : moreTabs.community;
  const tab = tabs.find(([k]) => k === params.get("tab"))?.[0] ?? tabs[0][0];

  if (viewer.state !== "member") return <MembersOnlySection what={kind === "team" ? "playbook, videos and stats" : "tournaments"} />;
  return (
    <div className="stack">
      {tabs.length > 1 && (
        // Desktops show these as the hub's own tabs (TeamNav).
        <div className="segmented narrow-only" role="tablist" aria-label="Section">
          {tabs.map(([k, label]) => (
            <Link key={k} href={`${pathname}?tab=${k}`} scroll={false} className={k === tab ? "on" : ""} role="tab" aria-selected={k === tab}>
              {label}
            </Link>
          ))}
        </div>
      )}
      {tab === "playbook" && <Playbook teamId={teamId} />}
      {tab === "videos" && <Videos teamId={teamId} />}
      {tab === "stats" && <Stats teamId={teamId} />}
      {tab === "tournaments" && <Tournaments teamId={teamId} manager={viewer.can("manageEvents")} uid={viewer.uid} />}
    </div>
  );
}

function Loading<T>({ live, empty, children }: { live: { data?: T[]; error: string | null }; empty: string; children: (rows: T[]) => React.ReactNode }) {
  if (live.error) return <p className="form-error">{live.error}</p>;
  if (!live.data) return <p className="muted" aria-busy="true">Loading…</p>;
  if (live.data.length === 0) return <p className="empty">{empty}</p>;
  return <>{children(live.data)}</>;
}

function Playbook({ teamId }: { teamId: string }) {
  const plays = useLiveQuery<Play>(`teams/${teamId}/plays`, [], "plays");
  return (
    <Loading live={plays} empty="No plays yet. Draw them in the app.">
      {(rows) => (
        <div className="play-grid">
          {rows
            .slice()
            .sort((a, b) => (a.category ?? "").localeCompare(b.category ?? "") || (a.name ?? "").localeCompare(b.name ?? ""))
            .map((p) => (
              <article key={p.id} className="card play-card">
                <FieldDiagram play={p} />
                <h3>{p.name || "Play"}</h3>
                <p className="muted small">
                  {categories[p.category ?? ""] ?? "Play"}
                  {p.steps?.length ? ` · ${p.steps.length + 1} steps` : ""}
                </p>
                {p.notes && <p className="small play-notes">{p.notes}</p>}
              </article>
            ))}
        </div>
      )}
    </Loading>
  );
}

/**
 * A play's starting positions, sideways: the stored field is portrait
 * (x across its 40 yd width, y along its 110 yd length), drawn here with
 * the length running left to right.
 */
function FieldDiagram({ play }: { play: Play }) {
  const at = (p?: Point) => ({ x: (p?.y ?? 0) * 110, y: (p?.x ?? 0) * 40 });
  return (
    <svg className="field" viewBox="0 0 110 40" role="img" aria-label={`${play.name ?? "Play"} diagram`}>
      <defs>
        <marker id="arrow" viewBox="0 0 6 6" refX="5" refY="3" markerWidth="4" markerHeight="4" orient="auto-start-reverse">
          <path d="M0,0 L6,3 L0,6 z" className="field-arrow-head" />
        </marker>
      </defs>
      <rect x="0" y="0" width="110" height="40" className="field-grass" />
      <line x1="20" y1="0" x2="20" y2="40" className="field-line" />
      <line x1="90" y1="0" x2="90" y2="40" className="field-line" />
      {(play.arrows ?? []).map((a) => (
        <polyline
          key={a.id}
          points={(a.points ?? []).map((p) => `${at(p).x},${at(p).y}`).join(" ")}
          className={a.kind === "throw_" ? "field-throw" : "field-cut"}
          markerEnd="url(#arrow)"
        />
      ))}
      {(play.elements ?? []).map((e) => {
        const p = at(e.position);
        return (
          <g key={e.id} className={`field-el ${e.kind ?? "offense"}`}>
            {e.kind === "cone" ? (
              <path d={`M${p.x},${p.y - 1.6} L${p.x + 1.4},${p.y + 1.2} L${p.x - 1.4},${p.y + 1.2} z`} />
            ) : (
              <circle cx={p.x} cy={p.y} r={e.kind === "disc" ? 1.1 : 2} />
            )}
            {e.label && e.kind !== "disc" && e.kind !== "cone" && (
              <text x={p.x} y={p.y + 0.8} textAnchor="middle">
                {e.label.slice(0, 2)}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}

function Videos({ teamId }: { teamId: string }) {
  const videos = useLiveQuery<Video>(`teams/${teamId}/videos`, [orderBy("createdAt", "desc")], "videos");
  return (
    <Loading live={videos} empty="No videos yet.">
      {(rows) => (
        <div className="video-grid">
          {rows.map((v) => (
            <article key={v.id} className="card video-card">
              {v.youtubeId ? (
                <iframe
                  src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(v.youtubeId)}`}
                  title={v.title || "Video"}
                  loading="lazy"
                  allow="encrypted-media; picture-in-picture; fullscreen"
                  allowFullScreen
                />
              ) : (
                <div className="video-file muted small">Uploaded video: watch in the app</div>
              )}
              <h3>{v.title || "Video"}</h3>
              <p className="muted small">
                {v.authorName ? `${v.authorName} · ` : ""}
                <LocalTime iso={v.createdAt} style="date" />
              </p>
              {v.description && <p className="small">{v.description}</p>}
            </article>
          ))}
        </div>
      )}
    </Loading>
  );
}

function score(g: StatsGame) {
  const points = g.points ?? [];
  return { us: points.filter((p) => p.result === "weScored").length, them: points.filter((p) => p.result === "theyScored").length };
}

function Stats({ teamId }: { teamId: string }) {
  const games = useLiveQuery<StatsGame>(`teams/${teamId}/statsGames`, [orderBy("date", "desc")], "statsGames");
  return (
    <Loading live={games} empty="No games tracked yet. Keep stats in the app.">
      {(rows) => {
        const results = rows.filter((g) => g.finished).map(score);
        const wins = results.filter((r) => r.us > r.them).length;
        return (
          <div className="stack">
            <div className="tiles">
              <div className="tile">
                <b>{rows.length}</b>
                <small>Games</small>
              </div>
              <div className="tile">
                <b>
                  {wins}–{results.length - wins}
                </b>
                <small>Record</small>
              </div>
              <div className="tile">
                <b>{results.reduce((n, r) => n + r.us - r.them, 0)}</b>
                <small>Point diff.</small>
              </div>
            </div>
            <div className="card table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Opponent</th>
                    <th className="num">Score</th>
                    <th>Result</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((g) => {
                    const s = score(g);
                    return (
                      <tr key={g.id}>
                        <td>
                          <LocalTime iso={g.date} style="date" />
                        </td>
                        <td>{g.opponent || "Opponent"}</td>
                        <td className="num">
                          {s.us}–{s.them}
                        </td>
                        <td>{!g.finished ? <span className="pill">Live</span> : s.us > s.them ? "Win" : s.us < s.them ? "Loss" : "Tie"}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        );
      }}
    </Loading>
  );
}

const statusLabels: Record<string, string> = { setup: "Setting up", live: "Live", done: "Finished", finished: "Finished" };

/**
 * Tournaments the group hosts. The rules show event managers all of them
 * and everyone else the ones they play in, so others ask by participantIds
 * as the app does.
 */
function Tournaments({ teamId, manager, uid }: { teamId: string; manager: boolean; uid: string }) {
  const list = useLiveQuery<GroupTournament>(
    `teams/${teamId}/groupTournaments`,
    manager ? [] : [where("participantIds", "array-contains", uid)],
    manager ? "all" : uid,
  );
  return (
    <Loading live={list} empty={manager ? "No tournaments hosted here yet." : "No tournaments here that you're playing in."}>
      {(rows: Array<Doc<GroupTournament>>) => (
        <div className="stack">
          {rows
            .slice()
            .sort((a, b) => (b.startsAt ?? "").localeCompare(a.startsAt ?? ""))
            .map((t) => (
              <div key={t.id} className="row-card">
                <span>
                  <b>{t.name || "Tournament"}</b>
                  <small>
                    <LocalTime iso={t.startsAt} style="date" />
                    {t.teams?.length ? ` · ${t.teams.length} teams` : ""}
                    {t.format ? ` · ${t.format}` : ""}
                  </small>
                </span>
                {t.status && <span className="pill">{statusLabels[t.status] ?? t.status}</span>}
              </div>
            ))}
        </div>
      )}
    </Loading>
  );
}
