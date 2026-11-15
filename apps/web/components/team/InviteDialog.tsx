"use client";
import type { InviteCodeResponse, InviteTtl } from "@stall10/shared";
import { createContext, type ReactNode, useCallback, useContext, useEffect, useRef, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { formatDateTime } from "@/lib/dates";
import { type Live, useLiveQuery } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Dialog } from "../Dialog";
import { ErrorNote, Loading } from "../StatusViews";
import { InvitePeople } from "./InvitePeople";
import { type JoinRequestDoc, JoinRequests } from "./JoinRequests";
import { useTeamHub } from "./TeamContext";

const site = process.env.NEXT_PUBLIC_SITE_URL || "";

/** How long a team's invite link works (InviteLinkExpiry in the app); a week unless picked. */
const linkTtls: Array<[InviteTtl, string]> = [
  [3600, "1 hour"],
  [86400, "1 day"],
  [604800, "7 days"],
  [2592000, "30 days"],
];
export const defaultLinkTtl: InviteTtl = 604800;

/** A short code to read out: a new one every 30 s, each working 45 s (InviteCode in the app). */
const codeTtl: InviteTtl = 45;
const rotateSeconds = 30;

type Pane = "link" | "people" | "requests";

interface InviteHub {
  /** Whether the viewer may invite (manageMembers). */
  canInvite: boolean;
  /** Join requests are shown (a group that approves members, to its member managers). */
  hasRequests: boolean;
  requests: Live<JoinRequestDoc[]>;
  /** How many are waiting, for the Invite badge. */
  requestCount: number;
  open: (pane?: Pane) => void;
}

const InviteContext = createContext<InviteHub | null>(null);

export function useInvite(): InviteHub {
  const hub = useContext(InviteContext);
  if (!hub) throw new Error("useInvite outside InviteProvider");
  return hub;
}

/**
 * The hub's one invite dialog, opened from the banner, the roster, the
 * feed's member card and Settings. It also listens to the join requests
 * (for the badge) and keeps the team's invite link between openings, so
 * reopening doesn't mint another.
 */
export function InviteProvider({ children }: { children: ReactNode }) {
  const { teamId, kind, viewer } = useTeamHub();
  const canInvite = viewer.state === "member" && viewer.can("manageMembers");
  // As Settings had it: a group that approves who joins.
  const hasRequests = canInvite && kind !== "team" && viewer.state === "member" && viewer.team.requiresApproval === true;
  const requests = useLiveQuery<{ name?: string }>(hasRequests ? `teams/${teamId}/joinRequests` : null, [], teamId);
  const [pane, setPane] = useState<Pane | null>(null);
  const link = useTeamLink(teamId, kind === "team" && canInvite);

  const open = useCallback((p: Pane = "link") => setPane(p), []);
  const value: InviteHub = { canInvite, hasRequests, requests, requestCount: hasRequests ? (requests.data?.length ?? 0) : 0, open };
  return (
    <InviteContext.Provider value={value}>
      {children}
      {pane && canInvite && <InviteDialog pane={pane} setPane={setPane} link={link} onClose={() => setPane(null)} />}
    </InviteContext.Provider>
  );
}

type TeamLink = ReturnType<typeof useTeamLink>;

/**
 * A team's invite link (`POST /v1/invite-codes`), made when the dialog
 * first opens and kept until it expires or another duration is picked.
 */
function useTeamLink(teamId: string, enabled: boolean) {
  const { user } = useAuth();
  const [ttl, setTtl] = useState<InviteTtl>(defaultLinkTtl);
  const [invite, setInvite] = useState<(InviteCodeResponse & { ttl: InviteTtl }) | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const minting = useRef(false);

  const ensure = useCallback(
    async (want: InviteTtl) => {
      if (!enabled || !user || minting.current) return;
      if (invite && invite.ttl === want && Date.parse(invite.expiresAt) > Date.now() + 60_000) return;
      minting.current = true;
      setBusy(true);
      setError(null);
      try {
        const r = await callApi<InviteCodeResponse>(user, "/v1/invite-codes", { method: "POST", body: { teamId, ttl: want } });
        setInvite({ ...r, ttl: want });
      } catch (e) {
        setError(problem(e, "Couldn't make a link. Try again."));
      } finally {
        minting.current = false;
        setBusy(false);
      }
    },
    [enabled, user, invite, teamId],
  );
  const pick = useCallback((t: InviteTtl) => setTtl(t), []);
  const url = invite ? `${site || window.location.origin}/join/${encodeURIComponent(invite.code)}` : null;
  return { ttl, pick, invite, url, busy, error, ensure };
}

function InviteDialog({ pane, setPane, link, onClose }: { pane: Pane; setPane: (p: Pane) => void; link: TeamLink; onClose: () => void }) {
  const { teamId, name } = useTeamHub();
  const { hasRequests, requests, requestCount } = useInvite();
  const panes: Array<[Pane, string]> = [
    ["link", "Share a link"],
    ["people", "Search people"],
    ...(hasRequests ? [["requests", `Requests${requestCount ? ` (${requestCount})` : ""}`] as [Pane, string]] : []),
  ];
  return (
    <Dialog label={`Invite to ${name}`} onClose={onClose} className="card invite-dialog" dismissOnBackdrop>
      <div className="invite-head">
        <h2 className="card-title">Invite to {name}</h2>
        <button type="button" className="icon-btn" aria-label="Close" onClick={onClose}>
          ×
        </button>
      </div>
      <div className="segmented" role="tablist" aria-label="How to invite">
        {panes.map(([p, label]) => (
          <button
            key={p}
            type="button"
            role="tab"
            id={`invite-tab-${p}`}
            aria-controls={`invite-pane-${p}`}
            aria-selected={pane === p}
            className={pane === p ? "on" : ""}
            onClick={() => setPane(p)}
          >
            {label}
          </button>
        ))}
      </div>
      {/* Every pane stays mounted, so switching keeps a search and who was invited. */}
      <div role="tabpanel" id="invite-pane-link" aria-labelledby="invite-tab-link" hidden={pane !== "link"}>
        <ShareLink link={link} />
      </div>
      <div role="tabpanel" id="invite-pane-people" aria-labelledby="invite-tab-people" hidden={pane !== "people"}>
        <InvitePeople teamId={teamId} teamName={name} embedded />
      </div>
      {hasRequests && (
        <div role="tabpanel" id="invite-pane-requests" aria-labelledby="invite-tab-requests" hidden={pane !== "requests"}>
          <JoinRequests teamId={teamId} requests={requests} card={false} />
        </div>
      )}
      <div className="form-actions">
        <button type="button" className="btn" onClick={onClose}>
          Done
        </button>
      </div>
    </Dialog>
  );
}

/**
 * Share a link: a team's join link (made on opening, Copy and Share right
 * there) or a group's page, which anyone can find and join; and, for teams
 * and schools or clubs, a rotating code to read out (as in the app).
 */
function ShareLink({ link }: { link: TeamLink }) {
  const { teamId, kind, privateGroup } = useTeamHub();
  const team = kind === "team";
  const { ensure, ttl } = link;
  useEffect(() => {
    if (team) void ensure(ttl);
  }, [team, ensure, ttl]);
  const url = team ? link.url : `${site || window.location.origin}/teams/${encodeURIComponent(teamId)}`;

  return (
    <div className="stack invite-share">
      <p className="muted small">
        {team
          ? "Anyone with the link joins as a player until it expires."
          : privateGroup
            ? "Anyone with the link can find the group and ask to join."
            : "Anyone with the link can find and join the group."}
      </p>
      {url ? (
        <div className="invite-link-row">
          <input readOnly value={url} aria-label="Invite link" onFocus={(e) => e.currentTarget.select()} />
          <CopyButton text={url} />
          <ShareSheetButton url={url} title={`Join on Stall 10`} />
        </div>
      ) : link.error ? (
        <ErrorNote onRetry={() => void ensure(ttl)}>{link.error}</ErrorNote>
      ) : (
        <Loading label="Making a link…" />
      )}
      {team && (
        <div className="invite-ttl">
          <label>
            Works for{" "}
            <select value={ttl} disabled={link.busy} onChange={(e) => link.pick(Number(e.target.value) as InviteTtl)}>
              {linkTtls.map(([t, label]) => (
                <option key={t} value={t}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          {link.invite && link.invite.ttl === ttl && (
            <small className="muted">Until {formatDateTime(link.invite.expiresAt, { dateStyle: "medium", timeStyle: "short" })}</small>
          )}
        </div>
      )}
      {kind !== "community" && <ReadOutCode />}
    </div>
  );
}

/** Copies [text]; says "Copied" once the clipboard has it. */
export function CopyButton({ text, className = "btn btn-small" }: { text: string; className?: string }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 2000);
    } catch {
      window.prompt("Copy this link:", text);
    }
  }
  return (
    <button type="button" className={className} onClick={() => void copy()} aria-live="polite">
      {copied ? "Copied" : "Copy"}
    </button>
  );
}

/** The device's share sheet, where there is one (phones, some desktops). */
function ShareSheetButton({ url, title }: { url: string; title: string }) {
  const [can, setCan] = useState(false);
  useEffect(() => setCan(typeof navigator.share === "function"), []);
  if (!can) return null;
  return (
    <button
      type="button"
      className="btn btn-small btn-primary"
      onClick={() =>
        void navigator.share({ title, url }).catch(() => {
          // Closing the share sheet isn't an error worth showing.
        })
      }
    >
      Share
    </button>
  );
}

/**
 * A short code to read out to someone in person: shown when asked, then a
 * fresh one every 30 seconds (each works for 45), until hidden or closed.
 */
function ReadOutCode() {
  const { teamId } = useTeamHub();
  const { user } = useAuth();
  const [showing, setShowing] = useState(false);
  const [code, setCode] = useState<string | null>(null);
  const [left, setLeft] = useState(rotateSeconds);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!showing || !user) return;
    let live = true;
    let minting = false;
    // When the code on screen is replaced.
    let next = 0;
    const mint = async () => {
      minting = true;
      try {
        const r = await callApi<InviteCodeResponse>(user, "/v1/invite-codes", { method: "POST", body: { teamId, ttl: codeTtl } });
        if (!live) return;
        next = Date.now() + rotateSeconds * 1000;
        setCode(r.code);
        setLeft(rotateSeconds);
      } catch (e) {
        if (!live) return;
        setError(problem(e, "Couldn't make a code. Try again."));
        setShowing(false);
      } finally {
        minting = false;
      }
    };
    void mint();
    const timer = setInterval(() => {
      if (minting) return;
      const s = Math.ceil((next - Date.now()) / 1000);
      if (s <= 0) void mint();
      else setLeft(s);
    }, 1000);
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [showing, user, teamId]);

  if (!showing) {
    return (
      <div className="invite-code-card">
        <div>
          <b>Invite code</b>
          <p className="muted small">A code that changes every {rotateSeconds} seconds, to read out to someone ready to type it in.</p>
          {error && <ErrorNote>{error}</ErrorNote>}
        </div>
        <button
          type="button"
          className="btn btn-small"
          onClick={() => {
            setError(null);
            setCode(null);
            setShowing(true);
          }}
        >
          Show code
        </button>
      </div>
    );
  }
  return (
    <div className="invite-code-card">
      <div>
        <b>Invite code</b>
        {code ? (
          <>
            <p className="invite-code-big" aria-live="polite">
              {code}
            </p>
            <p className="muted small">New code in {left}s</p>
          </>
        ) : (
          <Loading label="Making a code…" />
        )}
      </div>
      <span className="post-admin">
        {code && <CopyButton text={code} />}
        <button type="button" className="btn btn-small" onClick={() => setShowing(false)}>
          Hide
        </button>
      </span>
    </div>
  );
}

/** The banner's Invite button, with how many are asking to join. */
export function InviteButton({ className = "btn btn-primary btn-small" }: { className?: string }) {
  const { canInvite, requestCount, open } = useInvite();
  if (!canInvite) return null;
  return (
    <button
      type="button"
      className={`${className} invite-btn`}
      onClick={() => open()}
      aria-label={requestCount ? `Invite (${requestCount} asking to join)` : undefined}
    >
      Invite
      {requestCount > 0 && <span className="count-badge">{requestCount > 99 ? "99+" : requestCount}</span>}
    </button>
  );
}
