"use client";
// Host an event (HostEventScreen): what to host — tournament, league or hat
// tournament, as cards — then who hosts it, from the teams, groups and
// schools or clubs the viewer has Manage events on.
import { type HostedType, hostedTypeLabels } from "@stall10/shared";
import Link from "next/link";
import { useState } from "react";
import { useAuth } from "@/components/AuthProvider";
import type { TeamDoc } from "@/components/team/TeamContext";
import { useMyTeams } from "../useMyTeams";
import { canOn } from "./useTournament";
import "./tournaments.css";
import "./host_event.css";

const sections = [
  { key: "official", title: "Official organizer", blurb: "Events you run for an official organizer like Stall 10 carry its verified badge." },
  { key: "organization", title: "Your schools and clubs", blurb: "Host for everyone in the school or club, across its teams." },
  { key: "community", title: "Your pickup communities", blurb: "Pickup and hat events for the community to sign up to." },
  { key: "team", title: "Your teams", blurb: "Host as a team, for example your own tournament." },
] as const;

/** The kinds of event, in the app's order, with what each is (typeBlurb). */
const types: Array<{ type: HostedType; blurb: string; icon: string }> = [
  { type: "tournament", blurb: "A one or two day event. Teams apply, you seed them and publish pools and brackets.", icon: "M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4zM17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3" },
  { type: "league", blurb: "A weekly season with standings and optional playoffs. Teams enter, or players sign up and you draft teams.", icon: "M4 6h16v14H4zM4 10h16M8 3v4M16 3v4" },
  { type: "hat", blurb: "Players sign up on their own and you draft balanced teams for the day.", icon: "M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5" },
];

const initials = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() ?? "")
    .join("") || "?";

/** Who can host: the teams, groups and schools or clubs the viewer has Manage events on (HostEventScreen). */
export function HostEvent() {
  const { user } = useAuth();
  const [type, setType] = useState<HostedType>("league");
  const mine = useMyTeams<TeamDoc & { official?: boolean }>(user?.uid);
  if (mine.error) return <p className="form-error">{mine.error}</p>;
  if (!mine.data) return <p className="muted" aria-busy="true">Loading…</p>;
  const hosts = mine.data.filter((t) => canOn(t, user?.uid, "manageEvents")).sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""));
  const of = (key: (typeof sections)[number]["key"]) =>
    hosts.filter((t) => (key === "official" ? t.official : !t.official && (t.kind ?? "team") === key));
  return (
    <div className="stack host-event">
      <section className="stack">
        <h2 className="host-event-title">What are you hosting?</h2>
        <div className="host-types" role="group" aria-label="What to host">
          {types.map((x) => (
            <button key={x.type} type="button" className={`host-type${type === x.type ? " on" : ""}`} aria-pressed={type === x.type} onClick={() => setType(x.type)}>
              <span className="host-type-icon" aria-hidden>
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d={x.icon} />
                </svg>
              </span>
              <b>{hostedTypeLabels[x.type]}</b>
              <small>{x.blurb}</small>
            </button>
          ))}
        </div>
      </section>
      {hosts.length === 0 ? (
        <div className="card">
          <h2 className="card-title">Host as</h2>
          <p className="muted">
            Events are run by a team, group or school or club, so they have organizers, a page and followers. Ask to manage
            events on one you&apos;re in, or start one.
          </p>
          <div className="home-actions">
            <Link className="btn btn-primary btn-small" href="/teams/new">
              Start a team or group
            </Link>
          </div>
        </div>
      ) : (
        <section className="stack">
          <div>
            <h2 className="host-event-title">Host as</h2>
            <p className="muted small">Pick who runs it: you can host where you&apos;re the owner or can manage events.</p>
          </div>
          {sections.map((s) => {
            const list = of(s.key);
            if (list.length === 0) return null;
            return (
              <div key={s.key} className="host-section">
                <div className="host-section-head">
                  <b>{s.title}</b>
                  <small>{s.blurb}</small>
                </div>
                {list.map((t) => (
                  <Link key={t.id} className="host-row" href={`/tournaments/new?host=${encodeURIComponent(t.id)}&type=${type}`}>
                    <span className={`host-mark host-mark-${t.kind ?? "team"}`} aria-hidden>
                      {initials(t.name || "Team")}
                    </span>
                    <span className="host-row-text">
                      <b>{t.name || "Team"}</b>
                      <small>
                        Host a {hostedTypeLabels[type].toLowerCase()} as {t.name}
                      </small>
                    </span>
                    <span className="host-row-go" aria-hidden>
                      ›
                    </span>
                  </Link>
                ))}
              </div>
            );
          })}
        </section>
      )}
    </div>
  );
}
