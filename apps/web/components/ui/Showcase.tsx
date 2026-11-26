"use client";
import { type CSSProperties, useState } from "react";
import { NeedsPill, RsvpPill } from "../RsvpPill";
import { Avatar, AvatarStack, TeamLogo } from "./Avatar";
import { Button, IconButton } from "./Button";
import { buttonClass } from "./buttonClass";
import { FilterChips } from "./FilterChips";
import { SegmentedTabs } from "./SegmentedTabs";
import { StatusPill } from "./StatusPill";

const row: CSSProperties = { display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" };

/** The component gallery at /dev/ui (non-production only). Synthetic content. */
export function Showcase() {
  const [seg, setSeg] = useState("chats");
  const [line, setLine] = useState("teams");
  const [long, setLong] = useState("t3");
  const [chip, setChip] = useState("all");
  const [many, setMany] = useState<string[]>(["games"]);
  return (
    <div className="page" style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: 24 }}>
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

      <section className="card" data-showcase="button" aria-labelledby="sc-btn">
        <h2 id="sc-btn">Button</h2>
        <div style={row}>
          <Button variant="primary">Primary</Button>
          <Button>Secondary</Button>
          <Button variant="ghost">Ghost</Button>
          <Button variant="destructive">Destructive</Button>
        </div>
        <div style={{ ...row, marginTop: 12 }}>
          <Button variant="primary" size="small">
            Small
          </Button>
          <Button variant="primary" size="large">
            Large
          </Button>
          <Button variant="primary" disabled>
            Disabled
          </Button>
          <Button variant="primary" loading>
            Saving
          </Button>
          <Button loading>Loading</Button>
          <Button variant="ghost" disabled>
            Ghost off
          </Button>
          <Button variant="destructive" disabled>
            Delete off
          </Button>
        </div>
        <div style={{ ...row, marginTop: 12 }}>
          <IconButton label="Close">×</IconButton>
          <IconButton label="Next">›</IconButton>
          <IconButton label="Refresh" disabled>
            ↻
          </IconButton>
          <IconButton label="Saving" loading>
            ↻
          </IconButton>
          <a className={buttonClass({ variant: "primary", size: "small" })} href="#sc-btn">
            Link as button
          </a>
        </div>
      </section>

      <section className="card" data-showcase="tabs" aria-labelledby="sc-tabs">
        <h2 id="sc-tabs">Segmented tabs</h2>
        <SegmentedTabs
          label="Inbox"
          items={[
            { id: "chats", label: "Chats" },
            { id: "requests", label: "Requests (2)" },
            { id: "archived", label: "Archived" },
            { id: "off", label: "Disabled", disabled: true },
          ]}
          value={seg}
          onChange={setSeg}
        />
        <div style={{ height: 12 }} />
        <SegmentedTabs
          variant="underline"
          label="Feed"
          items={[
            { id: "teams", label: "Your teams" },
            { id: "following", label: "Following" },
            { id: "everyone", label: "Everyone" },
          ]}
          value={line}
          onChange={setLine}
        />
        <div style={{ height: 12 }} />
        <SegmentedTabs
          label="Many tabs, scrolling"
          items={["Overview", "Schedule", "Roster", "Stats", "Playbook", "Videos", "Meetings", "Settings"].map((l, i) => ({ id: `t${i}`, label: l }))}
          value={long}
          onChange={setLong}
        />
      </section>

      <section className="card" data-showcase="chips" aria-labelledby="sc-chips">
        <h2 id="sc-chips">Filter chips</h2>
        <FilterChips
          label="Show"
          items={[
            { id: "all", label: "All" },
            { id: "games", label: "Games" },
            { id: "practice", label: "Practices" },
            { id: "tourney", label: "Tournaments" },
            { id: "social", label: "Social" },
          ]}
          value={chip}
          onChange={setChip}
        />
        <div style={{ height: 12 }} />
        <FilterChips
          multiple
          label="Types"
          items={[
            { id: "games", label: "Games" },
            { id: "practice", label: "Practices" },
            { id: "tourney", label: "Tournaments" },
            { id: "off", label: "Disabled", disabled: true },
          ]}
          value={many}
          onChange={setMany}
        />
      </section>

      <section className="card" data-showcase="avatar" aria-labelledby="sc-avatar">
        <h2 id="sc-avatar">Avatar, team logo, stack</h2>
        <div style={row}>
          <Avatar name="Sam Rivera" />
          <Avatar name="Sam Rivera" url="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='80' height='80'%3E%3Crect width='80' height='80' fill='%23a1a1aa'/%3E%3Ccircle cx='40' cy='32' r='14' fill='%23f4f4f5'/%3E%3Crect x='14' y='52' width='52' height='40' rx='20' fill='%23f4f4f5'/%3E%3C/svg%3E" />
          <Avatar name="Sam Rivera" url="data:image/png;base64,AAAA" />
          <Avatar />
          <Avatar name="Sam Rivera" size={28} />
          <Avatar name="Sam Rivera" size={64} />
        </div>
        <div style={{ ...row, marginTop: 12 }}>
          <TeamLogo name="Seattle Ultimate" kind="team" size={48} />
          <TeamLogo name="Sunday Pickup" kind="community" size={48} />
          <TeamLogo name="Lakeside School" kind="organization" size={48} />
          <TeamLogo name="Seattle Ultimate" kind="team" url="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='80' height='80'%3E%3Crect width='80' height='80' fill='%23a1a1aa'/%3E%3Ccircle cx='40' cy='32' r='14' fill='%23f4f4f5'/%3E%3Crect x='14' y='52' width='52' height='40' rx='20' fill='%23f4f4f5'/%3E%3C/svg%3E" size={48} />
          <TeamLogo name="Seattle Ultimate" kind="team" size={34} />
        </div>
        <div style={{ ...row, marginTop: 12 }}>
          <AvatarStack people={["Ann Lee", "Bo Chen", "Cy Diaz", "Di Evans", "Ed Fox", "Fay Gu"].map((name, i) => ({ id: String(i), name }))} max={4} size={32} label="6 members" />
          <AvatarStack people={["Ann Lee", "Bo Chen"].map((name, i) => ({ id: String(i), name }))} size={32} label="2 members" />
          <AvatarStack people={["Ann Lee", "Bo Chen", "Cy Diaz", "Di Evans", "Ed Fox", "Fay Gu"].map((name, i) => ({ id: String(i), name }))} max={3} size={20} label="6 members" />
        </div>
      </section>
    </div>
  );
}
