"use client";
import { type PlayDoc, playCategoryLabels } from "@stall10/shared";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { type Doc, useLiveQuery } from "@/lib/live";
import { useAuth } from "../../AuthProvider";
import { Dialog } from "../../Dialog";
import { ErrorNote, LiveList, Loading } from "../../StatusViews";
import { PlayField } from "./PlayField";
import "./whiteboard.css";

const isWhiteboard = (p: PlayDoc) => p.kind === "whiteboard";

/**
 * A team's playbook, as the app's playbook tab: a "Plays | Whiteboard"
 * switch (?view=whiteboard) over the plays by category, or the blank
 * whiteboard and the saved ones.
 */
export function Playbook({ teamId, editor }: { teamId: string; editor: boolean }) {
  const plays = useLiveQuery<PlayDoc>(`teams/${teamId}/plays`, [], "plays");
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const view = params.get("view") === "whiteboard" ? "whiteboard" : "plays";
  const show = (v: "plays" | "whiteboard") => {
    const q = new URLSearchParams(params.toString());
    if (v === "whiteboard") q.set("view", "whiteboard");
    else q.delete("view");
    const s = q.toString();
    router.replace(s ? `${pathname}?${s}` : pathname, { scroll: false });
  };
  return (
    <>
      <div className="playbook-bar">
        <div className="segmented playbook-switch" role="tablist" aria-label="Playbook">
          {(["plays", "whiteboard"] as const).map((v) => (
            <button key={v} type="button" role="tab" aria-selected={view === v} className={view === v ? "on" : undefined} onClick={() => show(v)}>
              {v === "plays" ? "Plays" : "Whiteboard"}
            </button>
          ))}
        </div>
        {editor && view === "plays" && (
          <Link href={`/teams/${encodeURIComponent(teamId)}/plays/new`} className="btn btn-primary btn-small">
            New play
          </Link>
        )}
      </div>
      {view === "plays" ? (
        <PlayList teamId={teamId} editor={editor} live={{ data: plays.data?.filter((p) => !isWhiteboard(p)), error: plays.error }} />
      ) : (
        <WhiteboardList teamId={teamId} editor={editor} live={{ data: plays.data?.filter(isWhiteboard), error: plays.error }} />
      )}
    </>
  );
}

type Rows = { data?: Doc<PlayDoc>[]; error: string | null };

/** Plays in category sections, each with its count and a grid of plays (whiteboards left out). */
function PlayList({ teamId, editor, live }: { teamId: string; editor: boolean; live: Rows }) {
  const base = `/teams/${encodeURIComponent(teamId)}/plays`;
  return (
    <LiveList live={live} empty={editor ? "No plays yet. Draw your first one." : "No plays yet."}>
      {(rows) => {
        const sorted = rows.slice().sort((a, b) => (a.category ?? "").localeCompare(b.category ?? "") || (a.name ?? "").localeCompare(b.name ?? ""));
        const sections = [...new Set(sorted.map((p) => p.category ?? "offense"))];
        return (
          <div className="playbook-sections">
            {sections.map((cat) => {
              const plays = sorted.filter((p) => (p.category ?? "offense") === cat);
              return (
                <section key={cat} className="playbook-section">
                  <h2 className="playbook-section-head">
                    {playCategoryLabels[cat] ?? "Plays"}
                    <span className="muted">
                      {plays.length} {plays.length === 1 ? "play" : "plays"}
                    </span>
                  </h2>
                  <div className="play-grid">
                    {plays.map((p) => (
                      <Link key={p.id} href={`${base}/${encodeURIComponent(p.id)}`} className="card play-card">
                        <PlayField elements={p.elements ?? []} arrows={p.arrows ?? []} drawings={p.drawings ?? []} label={`${p.name ?? "Play"} diagram`} />
                        <h3>{p.name || "Play"}</h3>
                        <p className="muted small">
                          {playCategoryLabels[p.category ?? "offense"] ?? "Play"}
                          {p.steps?.length ? ` · ${p.steps.length + 1} steps` : ""}
                        </p>
                        {p.notes && <p className="small play-notes">{p.notes}</p>}
                      </Link>
                    ))}
                  </div>
                </section>
              );
            })}
          </div>
        );
      }}
    </LiveList>
  );
}

/** The blank whiteboard to open, then the saved whiteboards by name (as the app). */
function WhiteboardList({ teamId, editor, live }: { teamId: string; editor: boolean; live: Rows }) {
  const { user } = useAuth();
  const base = `/teams/${encodeURIComponent(teamId)}/whiteboards`;
  const [confirm, setConfirm] = useState<Doc<PlayDoc> | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function remove(p: Doc<PlayDoc>) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/plays/${encodeURIComponent(p.id)}`, { method: "DELETE" });
      setConfirm(null);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="playbook-sections">
      <div className="card wb-blank">
        <PlayField elements={[]} arrows={[]} label="Blank whiteboard" />
        <div className="wb-blank-text">
          <h2 className="card-title">Blank whiteboard</h2>
          <p className="muted small">Sketch a chalk talk: draw, drop players and the disc, then save it or throw it away.</p>
          <Link href={`${base}/new`} className="btn btn-primary btn-small">
            Open whiteboard
          </Link>
        </div>
      </div>
      {error && !confirm && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {live.error ? (
        <ErrorNote>{live.error}</ErrorNote>
      ) : live.data === undefined ? (
        <Loading />
      ) : live.data.length === 0 ? null : (
        <section className="playbook-section">
          <h2 className="playbook-section-head">
            Saved whiteboards
            <span className="muted">
              {live.data.length} {live.data.length === 1 ? "whiteboard" : "whiteboards"}
            </span>
          </h2>
          <div className="play-grid">
            {live.data
              .slice()
              .sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""))
              .map((p) => (
                <div key={p.id} className="card play-card wb-card">
                  <Link href={`${base}/${encodeURIComponent(p.id)}`} className="wb-card-link">
                    <PlayField elements={p.elements ?? []} arrows={[]} drawings={p.drawings ?? []} label={`${p.name || "Untitled whiteboard"} sketch`} />
                    <h3>{p.name || "Untitled whiteboard"}</h3>
                    <p className="muted small">Whiteboard</p>
                  </Link>
                  {editor && (
                    <button type="button" className="text-btn danger wb-card-delete" onClick={() => setConfirm(p)}>
                      Delete
                    </button>
                  )}
                </div>
              ))}
          </div>
        </section>
      )}
      {confirm && (
        <Dialog label="Delete whiteboard" onClose={() => !busy && setConfirm(null)} className="card wb-dialog" dismissOnBackdrop>
          <h2 className="card-title">Delete &ldquo;{confirm.name || "Untitled whiteboard"}&rdquo;?</h2>
          <p className="muted">This whiteboard will be removed from the playbook.</p>
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
          <div className="form-actions">
            <button type="button" className="btn btn-quiet btn-small" disabled={busy} onClick={() => setConfirm(null)}>
              Cancel
            </button>
            <button type="button" className="btn btn-ink btn-small" disabled={busy} onClick={() => void remove(confirm)}>
              {busy ? "Deleting…" : "Delete"}
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}
