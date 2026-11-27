"use client";
import type { TeamRoster } from "@stall10/shared";
import { useEffect, useRef, useState } from "react";
import { Dialog } from "../Dialog";
import { useAuth } from "../AuthProvider";
import { Button } from "../ui/Button";
import { draftOf, RosterPlayerForm, saveRosterPlayer, type PlayerDraft } from "./RosterPlayerForm";
import { useInvite } from "./InviteDialog";
import { useTeamHub } from "./TeamContext";
import "./roster_actions.css";

/**
 * "Add member" on the roster: for people who manage members, a menu with Invite people (the hub's invite
 * dialog) and, on a team with a roster and for those who manage the team, "Add player to roster" (the roster
 * spot form, with the link-to-a-member picker). Nobody who can do neither sees it.
 */
export function AddMember({ roster, onAdded }: { roster: TeamRoster; onAdded: () => void }) {
  const { teamId, kind, viewer } = useTeamHub();
  const { user } = useAuth();
  const invite = useInvite();
  const [menu, setMenu] = useState(false);
  const [adding, setAdding] = useState<PlayerDraft | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const wrap = useRef<HTMLSpanElement>(null);

  // Esc and a click elsewhere close the menu.
  useEffect(() => {
    if (!menu) return;
    const away = (e: Event) => {
      if (!wrap.current?.contains(e.target as Node)) setMenu(false);
    };
    const esc = (e: KeyboardEvent) => e.key === "Escape" && setMenu(false);
    document.addEventListener("pointerdown", away);
    document.addEventListener("keydown", esc);
    return () => {
      document.removeEventListener("pointerdown", away);
      document.removeEventListener("keydown", esc);
    };
  }, [menu]);

  const canInvite = invite.canInvite;
  const canAddPlayer = viewer.state === "member" && kind === "team" && viewer.can("manageTeam");
  if (!canInvite && !canAddPlayer) return null;

  const linked = new Set(roster.players.flatMap((p) => (p.person ? [p.person.uid] : [])));
  const members = roster.members.map((m) => ({ uid: m.uid, name: m.name }));

  async function save(d: PlayerDraft) {
    if (!user) return;
    setBusy(true);
    setError("");
    const r = await saveRosterPlayer(user, teamId, d);
    setBusy(false);
    if (r.error) return setError(r.error);
    onAdded();
    setAdding(null);
  }

  return (
    <>
      <span className="add-member" ref={wrap}>
        <Button
          variant="primary"
          size="small"
          aria-haspopup={canInvite && canAddPlayer ? "menu" : undefined}
          aria-expanded={canInvite && canAddPlayer ? menu : undefined}
          onClick={() => {
            // One way to add: no menu to open first.
            if (canInvite && canAddPlayer) setMenu((o) => !o);
            else if (canInvite) invite.open("people");
            else setAdding(draftOf());
          }}
        >
          Add member
          {invite.requestCount > 0 && (
            <span className="count-badge" aria-label={`${invite.requestCount} asking to join`}>
              {invite.requestCount > 99 ? "99+" : invite.requestCount}
            </span>
          )}
        </Button>
        {menu && (
          <div className="add-member-menu" role="menu" aria-label="Add member">
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                setMenu(false);
                invite.open("people");
              }}
            >
              Invite people
            </button>
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                setMenu(false);
                setError("");
                setAdding(draftOf());
              }}
            >
              Add player to roster
            </button>
          </div>
        )}
      </span>
      {adding && (
        <Dialog label="Add player to roster" onClose={() => setAdding(null)} className="card" dismissOnBackdrop>
          <RosterPlayerForm
            key={adding.id || "new"}
            draft={adding}
            members={members}
            linkedElsewhere={linked}
            busy={busy}
            error={error}
            onCancel={() => setAdding(null)}
            onSave={(d) => void save(d)}
          />
        </Dialog>
      )}
    </>
  );
}
