"use client";
import { type CSSProperties, useState } from "react";
import { NeedsPill, RsvpPill } from "../RsvpPill";
import { Avatar, AvatarStack, TeamLogo } from "./Avatar";
import { ConfirmDialog } from "./ConfirmDialog";
import { CoverHeader } from "./CoverHeader";
import { DateBadge } from "./DateBadge";
import { EventCard } from "./EventCard";
import { SearchField, TextArea, TextField } from "./Fields";
import { ListRow } from "./ListRow";
import { EmptyState, ErrorState, LoadingState } from "./States";
import { SummaryTiles } from "./SummaryTiles";
import { Button, IconButton } from "./Button";
import { buttonClass } from "./buttonClass";
import { FilterChips } from "./FilterChips";
import { SegmentedTabs } from "./SegmentedTabs";
import { StatusPill } from "./StatusPill";

const cover =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='800' height='200'%3E%3Crect width='800' height='200' fill='%23a1a1aa'/%3E%3Cpath d='M0 150 Q200 60 400 130 T800 90 V200 H0Z' fill='%2371717a'/%3E%3C/svg%3E";

const row: CSSProperties = { display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" };

/** The component gallery at /dev/ui (non-production only). Synthetic content. */
export function Showcase() {
  const [seg, setSeg] = useState("chats");
  const [line, setLine] = useState("teams");
  const [long, setLong] = useState("t3");
  const [chip, setChip] = useState("all");
  const [many, setMany] = useState<string[]>(["games"]);
  const [name, setName] = useState("Seattle Ultimate");
  const [query, setQuery] = useState("");
  const [confirm, setConfirm] = useState<null | "plain" | "destructive">(null);
  const [result, setResult] = useState("");
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

      <section className="card" data-showcase="cover" aria-labelledby="sc-cover">
        <h2 id="sc-cover">Cover header and summary tiles</h2>
        <div style={{ display: "grid", gap: 16 }}>
          <CoverHeader
            as="h3"
            coverUrl={cover}
            avatar={<Avatar name="Jamie Carter" size={88} />}
            title="Jamie Carter"
            subtitle="@jamiecarter · Seattle, WA"
            actions={<Button size="small">Edit profile</Button>}
          >
            <SummaryTiles label="Your numbers" items={[{ id: "u", label: "Upcoming", value: 2 }, { id: "t", label: "Teams", value: 3, href: "#sc-cover" }, { id: "f", label: "Following", value: 12 }]} />
          </CoverHeader>
          <CoverHeader as="h3" avatar={<TeamLogo name="Seattle Ultimate" size={88} />} title="Seattle Ultimate" subtitle="Team · Club · Open" />
        </div>
      </section>

      <section className="card" data-showcase="listrow" aria-labelledby="sc-row">
        <h2 id="sc-row">List row</h2>
        <div>
          <ListRow leading={<Avatar name="Alex Chen" />} title="Alex Chen" subtitle="Great turnout at practice last night" meta="2m" href="#sc-row" />
          <ListRow leading={<Avatar name="Morgan Reed" />} title="Morgan Reed" subtitle="Unread message" meta="4h" unread onClick={() => undefined} />
          <ListRow leading={<TeamLogo name="Lakefront" size={40} />} title="Lakefront captains" subtitle="Muted chat" muted onClick={() => undefined} />
          <ListRow leading={<Avatar name="Taylor Brooks" />} title="Taylor Brooks" subtitle="Selected" selected href="#sc-row" />
          <ListRow title="Plain row with a control" subtitle="No link" trailing={<StatusPill tone="success">Open</StatusPill>} />
        </div>
      </section>

      <section className="card" data-showcase="event" aria-labelledby="sc-event">
        <h2 id="sc-event">Event card and date badge</h2>
        <div style={{ display: "grid", gap: 12 }}>
          <EventCard startsAt="2027-01-14T19:00:00Z" title="Rivertown practice" meta="7:00 PM · Rivertown Fields" answer="going" href="#sc-event" />
          <EventCard startsAt="2027-01-16T18:00:00Z" title="Lake City scrimmage" meta="10:00 AM · Lake City Park" needsRsvp recurring />
          <EventCard startsAt="2027-01-18T18:00:00Z" title="Cascadia Classic" meta="All day · Seattle" answer="maybe" />
          <EventCard startsAt="2027-01-21T02:00:00Z" title="Thursday throw-around" meta="Cancelled by the organizer" cancelled recurring />
          <div style={row}>
            <DateBadge startsAt="2027-01-14T19:00:00Z" />
            <DateBadge startsAt="2027-01-14T19:00:00Z" unit="month" />
            <DateBadge startsAt={null} />
          </div>
        </div>
      </section>

      <section className="card" data-showcase="states" aria-labelledby="sc-states">
        <h2 id="sc-states">Loading, empty and error</h2>
        <div style={{ display: "grid", gap: 12 }}>
          <LoadingState />
          <EmptyState title="No teams yet" action={<a className="btn btn-primary" href="#sc-states">Create a team</a>}>
            Teams you join or create show up here.
          </EmptyState>
          <EmptyState>Nothing scheduled.</EmptyState>
          <ErrorState onRetry={() => undefined}>We couldn&apos;t load the schedule.</ErrorState>
          <ErrorState title="Offline">You are offline. Changes will send when you reconnect.</ErrorState>
        </div>
      </section>

      <section className="card" data-showcase="fields" aria-labelledby="sc-fields">
        <h2 id="sc-fields">Text field, search field and confirm dialog</h2>
        <div style={{ display: "grid", gap: 12, maxWidth: 420 }}>
          <TextField label="Team name" hint="Shown on your team page" value={name} onChange={(e) => setName(e.target.value)} />
          <TextField label="Username" error="That username is taken." defaultValue="jamie" />
          <TextField label="Disabled" disabled defaultValue="Read only" />
          <TextArea label="About" defaultValue="Two lines of text." />
          <SearchField label="Search the gallery" value={query} onChange={setQuery} placeholder="Search players, teams and events" />
        </div>
        <div style={{ ...row, marginTop: 12 }}>
          <Button onClick={() => setConfirm("plain")}>Open confirm</Button>
          <Button variant="destructive" onClick={() => setConfirm("destructive")}>
            Open destructive confirm
          </Button>
          <span role="status" data-testid="confirm-result">
            {result}
          </span>
        </div>
        {confirm ? (
          <ConfirmDialog
            title={confirm === "destructive" ? "Delete this event?" : "Publish the schedule?"}
            message={confirm === "destructive" ? "Everyone on the team loses it.\n\nThis can't be undone." : "Teams are notified, and seeds lock."}
            confirmLabel={confirm === "destructive" ? "Delete" : "Publish"}
            destructive={confirm === "destructive"}
            onConfirm={() => {
              setResult(`Confirmed ${confirm}`);
              setConfirm(null);
            }}
            onCancel={() => {
              setResult("Cancelled");
              setConfirm(null);
            }}
          />
        ) : null}
      </section>
    </div>
  );
}
