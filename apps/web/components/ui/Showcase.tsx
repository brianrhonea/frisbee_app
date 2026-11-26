"use client";
import type { CSSProperties } from "react";
import { NeedsPill, RsvpPill } from "../RsvpPill";
import { StatusPill } from "./StatusPill";

const row: CSSProperties = { display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" };

/** The component gallery at /dev/ui (non-production only). Synthetic content. */
export function Showcase() {
  return (
    <div className="page" style={{ display: "grid", gap: 24 }}>
      <h1>Components</h1>

      <section className="card" data-showcase="statuspill" aria-labelledby="sc-pill">
        <h2 id="sc-pill">Status pill</h2>
        <div style={row}>
          <StatusPill tone="success" icon="check">
            Going
          </StatusPill>
          <StatusPill>Maybe</StatusPill>
          <StatusPill tone="success">Open</StatusPill>
          <StatusPill tone="live" icon="dot">
            Live
          </StatusPill>
          <StatusPill tone="accent">Captain</StatusPill>
          <StatusPill tone="attention" icon="alert">
            Needs you
          </StatusPill>
          <StatusPill tone="error">Declined</StatusPill>
          <StatusPill tone="neutral">Final</StatusPill>
        </div>
        <div style={{ ...row, marginTop: 12 }}>
          <RsvpPill answer="going" />
          <RsvpPill answer="maybe" />
          <RsvpPill answer="notGoing" />
          <NeedsPill>Needs RSVP</NeedsPill>
        </div>
      </section>
    </div>
  );
}
