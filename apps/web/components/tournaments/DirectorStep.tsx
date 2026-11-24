"use client";
// The event form's Director step (DirectorStep in the app): the event's
// main contact for questions and logistics. A Stall 10 member (anyone,
// not only the host's members), found by name, or someone without an
// account by name with an optional email and phone. Not an organizer.
import { type SearchPage, tournamentLimits } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useEffect, useState } from "react";
import type { TeamDoc } from "@/components/team/TeamContext";
import { callApi } from "@/lib/client";
import type { DirectorForm } from "./TournamentForm";

export function DirectorStep({
  user,
  f,
  host,
  onChange,
}: {
  user: User;
  f: { director: DirectorForm | null };
  host: TeamDoc | null | undefined;
  onChange: (director: DirectorForm | null) => void;
}) {
  const d = f.director;
  const [mode, setMode] = useState<"member" | "other">(d && !d.uid ? "other" : "member");
  const [q, setQ] = useState("");
  const [results, setResults] = useState<SearchPage["players"] | null>(null);

  // People by name, as inviting them does (GET /v1/public/search).
  useEffect(() => {
    const term = q.trim();
    if (mode !== "member" || term.length < 2) {
      setResults(null);
      return;
    }
    let live = true;
    const timer = setTimeout(() => {
      callApi<SearchPage>(user, `/v1/public/search?q=${encodeURIComponent(term)}`).then(
        (r) => live && setResults(r.players.slice(0, 8)),
        () => live && setResults([]),
      );
    }, 300);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [q, mode, user]);

  const me = host?.memberNames?.[user.uid] ?? user.displayName ?? "";
  return (
    <section className="card settings-form">
      <h2 className="card-title">Tournament director</h2>
      <p className="muted small">The main contact for questions and logistics. They don&apos;t have to be in {host?.name ?? "the host"}, and they get no organizer rights.</p>
      <div className="segmented" role="group" aria-label="Director">
        <button type="button" className={mode === "member" ? "on" : ""} aria-pressed={mode === "member"} onClick={() => setMode("member")}>
          On Stall 10
        </button>
        <button
          type="button"
          className={mode === "other" ? "on" : ""}
          aria-pressed={mode === "other"}
          onClick={() => {
            setMode("other");
            if (d?.uid) onChange({ uid: null, name: "", email: "", phone: "" });
          }}
        >
          Not on Stall 10
        </button>
      </div>
      {d?.uid && mode === "member" && (
        <div className="row-card">
          <b>{d.name}</b>
          <button type="button" className="text-btn" onClick={() => onChange(null)}>
            Remove
          </button>
        </div>
      )}
      {mode === "member" && !d?.uid && (
        <>
          {me && (
            <div className="home-actions">
              <button type="button" className="btn btn-small" onClick={() => onChange({ uid: user.uid, name: me, email: "", phone: "" })}>
                It&apos;s me
              </button>
            </div>
          )}
          <label>
            Find someone
            <input type="search" value={q} placeholder="Name or username" onChange={(e) => setQ(e.target.value)} />
          </label>
          {results && results.length === 0 && <p className="muted small">Nobody found. Not on Stall 10? Enter their details instead.</p>}
          {results && results.length > 0 && (
            <ul className="stack director-results">
              {results.map((p) => (
                <li key={p.id} className="row-card">
                  <span>
                    <b>{p.name ?? p.username}</b>
                    {p.username && <small className="muted"> @{p.username}</small>}
                  </span>
                  <button
                    type="button"
                    className="btn btn-small"
                    onClick={() => {
                      onChange({ uid: p.id, name: (p.name ?? p.username ?? "").slice(0, tournamentLimits.directorName), email: "", phone: "" });
                      setQ("");
                    }}
                  >
                    Choose
                  </button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
      {mode === "other" && (
        <>
          <label>
            Name
            <input value={d?.name ?? ""} maxLength={tournamentLimits.directorName} onChange={(e) => onChange({ uid: null, name: e.target.value, email: d?.email ?? "", phone: d?.phone ?? "" })} />
          </label>
          <div className="form-grid">
            <label>
              Email (optional)
              <input type="email" value={d?.email ?? ""} maxLength={tournamentLimits.directorEmail} onChange={(e) => onChange({ uid: null, name: d?.name ?? "", email: e.target.value, phone: d?.phone ?? "" })} />
            </label>
            <label>
              Phone (optional)
              <input type="tel" value={d?.phone ?? ""} maxLength={tournamentLimits.directorPhone} onChange={(e) => onChange({ uid: null, name: d?.name ?? "", email: d?.email ?? "", phone: e.target.value })} />
            </label>
          </div>
          <p className="muted small">Signed-in members see the email and phone; visitors see the name only. Better still, ask them to join Stall 10.</p>
          {d && (
            <div className="home-actions">
              <button type="button" className="text-btn" onClick={() => onChange(null)}>
                No director
              </button>
            </div>
          )}
        </>
      )}
    </section>
  );
}
