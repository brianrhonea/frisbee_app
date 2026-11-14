"use client";
import { type PlayDoc, playCategoryLabels } from "@stall10/shared";
import { orderBy, where } from "firebase/firestore";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { LocalTime } from "../LocalTime";
import { type Doc, useLiveQuery } from "@/lib/live";
import { useTeamHub } from "./TeamContext";
import { MembersOnlySection, moreTabs } from "./TeamNav";
import { PlayField } from "./playbook/PlayField";
import { TeamVideos } from "./videos/TeamVideos";

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
      {tab === "playbook" && <Playbook teamId={teamId} editor={viewer.can("manageTeam")} />}
      {tab === "videos" && <TeamVideos />}
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

function Playbook({ teamId, editor }: { teamId: string; editor: boolean }) {
  const plays = useLiveQuery<PlayDoc>(`teams/${teamId}/plays`, [], "plays");
  const base = `/teams/${encodeURIComponent(teamId)}/plays`;
  return (
    <>
      {editor && (
        <div className="home-actions">
          <Link href={`${base}/new`} className="btn btn-primary btn-small">
            New play
          </Link>
        </div>
      )}
      <Loading live={plays} empty={editor ? "No plays yet. Draw your first one." : "No plays yet."}>
        {(rows) => (
          <div className="play-grid">
            {rows
              .slice()
              .sort((a, b) => (a.category ?? "").localeCompare(b.category ?? "") || (a.name ?? "").localeCompare(b.name ?? ""))
              .map((p) => (
                <Link key={p.id} href={`${base}/${encodeURIComponent(p.id)}`} className="card play-card">
                  <PlayField elements={p.elements ?? []} arrows={p.arrows ?? []} label={`${p.name ?? "Play"} diagram`} />
                  <h3>{p.name || "Play"}</h3>
                  <p className="muted small">
                    {playCategoryLabels[p.category ?? "offense"] ?? "Play"}
                    {p.steps?.length ? ` · ${p.steps.length + 1} steps` : ""}
                  </p>
                  {p.notes && <p className="small play-notes">{p.notes}</p>}
                </Link>
              ))}
          </div>
        )}
      </Loading>
    </>
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
