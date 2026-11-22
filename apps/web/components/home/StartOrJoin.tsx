"use client";
// Starting a team, group or community, or joining one with a code, from
// Home's team strip, the "+" beside "Your spaces" and the new-member
// checklist (the app's _JoinCard: Join with code, Find a group, Create team).
import Link from "next/link";
import { usePathname } from "next/navigation";
import { type ReactNode, useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { JoinWithCode } from "../CreateTeam";
import { Dialog } from "../Dialog";

/** Create links and the join-with-code form; [join] opens straight on the form. */
export function StartOrJoinDialog({ onClose, join = false }: { onClose: () => void; join?: boolean }) {
  return (
    <Dialog label={join ? "Join with a code" : "Create or join"} onClose={onClose} className="card start-join" dismissOnBackdrop>
      <div className="card-head">
        <h2 className="card-title">{join ? "Join with a code" : "Create or join"}</h2>
        <button type="button" className="icon-btn" aria-label="Close" onClick={onClose}>
          ×
        </button>
      </div>
      {!join && (
        <ul className="start-join-list">
          <li>
            <Link href="/teams/new" onClick={onClose}>
              <b>Create a team</b>
              <small>A club, college or youth team: schedule, roster, playbook and stats.</small>
            </Link>
          </li>
          <li>
            <Link href="/teams/new?kind=community" onClick={onClose}>
              <b>Start a pickup community</b>
              <small>A pickup game or league anyone can find and join.</small>
            </Link>
          </li>
          <li>
            <Link href="/teams/new?kind=organization" onClick={onClose}>
              <b>Start a school or club</b>
              <small>A community that brings its teams together.</small>
            </Link>
          </li>
          <li>
            <Link href="/explore?only=groups" onClick={onClose}>
              <b>Find a community</b>
              <small>Pickup and leagues near you.</small>
            </Link>
          </li>
        </ul>
      )}
      <p className="muted small">Have an invite code? Ask a coach or organizer for one.</p>
      <JoinWithCode />
    </Dialog>
  );
}

/**
 * A button that opens [StartOrJoinDialog], on the page's body (so the
 * card it sits in doesn't style it). It closes when the page changes:
 * joining opens the team, and the sidebar's "+" stays mounted across pages.
 */
export function StartOrJoinButton({ className, join = false, label, children }: { className: string; join?: boolean; label?: string; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const path = usePathname();
  useEffect(() => setOpen(false), [path]);
  return (
    <>
      <button type="button" className={className} aria-label={label} aria-haspopup="dialog" onClick={() => setOpen(true)}>
        {children}
      </button>
      {open && createPortal(<StartOrJoinDialog join={join} onClose={() => setOpen(false)} />, document.body)}
    </>
  );
}
