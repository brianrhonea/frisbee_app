"use client";
import {
  type ReportReason,
  type ReportResult,
  type ReportTarget,
  reportDetailsMax,
  reportReasonLabels,
  reportReasons,
} from "@stall10/shared";
import Link from "next/link";
import { type FormEvent, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { blockPerson, loadBlocks } from "@/lib/moderation";
import { useAuth } from "./AuthProvider";
import { Dialog } from "./Dialog";
import { useConfirm } from "@/components/ui/ConfirmDialog";
import { ErrorNote } from "@/components/StatusViews";

/** What the report is about, as the dialog names it. */
const noun: Record<ReportTarget["kind"], string> = {
  post: "post",
  comment: "comment",
  teamPost: "post",
  teamPostComment: "comment",
  teamMessage: "message",
  directMessage: "message",
  user: "profile",
};

/**
 * Report a post, comment, message or person (App Store guideline 1.2; the
 * app's ReportSheet): a reason, optional details, and "also block" so
 * their content disappears at once. Team chat and team posts also go to
 * the team's admins. [onDone] says whether the author was blocked.
 */
export function ReportDialog({
  target,
  authorName,
  onClose,
  onDone,
}: {
  target: ReportTarget;
  authorName: string;
  onClose: () => void;
  onDone?: (blocked: boolean) => void;
}) {
  const { user } = useAuth();
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState("");
  const [block, setBlock] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState<ReportResult | null>(null);
  const what = noun[target.kind];
  const team = target.kind.startsWith("team");

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!user || !reason) return;
    setBusy(true);
    setError(null);
    try {
      const r = await callApi<ReportResult>(user, "/v1/reports", {
        method: "POST",
        body: { target, reason, ...(details.trim() && { details: details.trim() }), ...(block && { block: true }) },
      });
      if (r.blocked) await loadBlocks(user).catch(() => undefined);
      setSent(r);
    } catch (err) {
      setError(problem(err));
    } finally {
      setBusy(false);
    }
  }

  if (sent) {
    return (
      <Dialog label="Report sent" onClose={() => { onDone?.(sent.blocked); onClose(); }} className="card report-dialog" dismissOnBackdrop>
        <h2>Thanks for telling us</h2>
        <p>
          Stall 10&apos;s team will review it{team ? ", and so will the team's admins" : ""}. We don&apos;t tell {authorName} who
          reported them.
        </p>
        {sent.blocked && <p>You blocked {authorName}. You won&apos;t see each other&apos;s posts or messages.</p>}
        <p className="muted small">
          Read the <Link href="/guidelines">community guidelines</Link>. If someone is in danger, call 911 or your local emergency
          number first.
        </p>
        <div className="form-actions">
          <button type="button" className="btn btn-primary btn-small" onClick={() => { onDone?.(sent.blocked); onClose(); }}>
            Done
          </button>
        </div>
      </Dialog>
    );
  }

  return (
    <Dialog label={`Report this ${what}`} onClose={onClose} className="card report-dialog" dismissOnBackdrop>
      <form onSubmit={(e) => void submit(e)}>
        <h2>Report this {what}</h2>
        <p className="muted small">Why are you reporting it?</p>
        <fieldset className="report-reasons">
          <legend className="sr-only">Reason</legend>
          {reportReasons.map((r) => (
            <label key={r} className="report-reason">
              <input type="radio" name="reason" value={r} checked={reason === r} onChange={() => setReason(r)} />
              {reportReasonLabels[r]}
            </label>
          ))}
        </fieldset>
        <label>
          More details <small className="muted">(optional)</small>
          <textarea value={details} maxLength={reportDetailsMax} rows={3} onChange={(e) => setDetails(e.target.value)} />
        </label>
        <label className="switch-row">
          <input type="checkbox" checked={block} onChange={(e) => setBlock(e.target.checked)} /> Also block {authorName}
        </label>
        {error && <ErrorNote>{error}</ErrorNote>}
        <div className="form-actions">
          <button type="button" className="btn btn-small" onClick={onClose}>
            Cancel
          </button>
          <button type="submit" className="btn btn-primary btn-small" disabled={busy || !reason}>
            {busy ? "Sending…" : "Report"}
          </button>
        </div>
      </form>
    </Dialog>
  );
}

/** A Report button that opens [ReportDialog]. */
export function ReportButton({
  target,
  authorName,
  className = "text-btn",
  label = "Report",
  onDone,
}: {
  target: ReportTarget;
  authorName: string;
  className?: string;
  label?: string;
  onDone?: (blocked: boolean) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={className} onClick={() => setOpen(true)}>
        {label}
      </button>
      {open && <ReportDialog target={target} authorName={authorName} onClose={() => setOpen(false)} onDone={onDone} />}
    </>
  );
}

/** Block [uid] after asking; [onDone] once they're blocked. */
export function BlockButton({
  uid,
  name,
  className = "text-btn danger",
  label,
  onDone,
}: {
  uid: string;
  name: string;
  className?: string;
  /** The button's text; "Block {name}" when not given. */
  label?: string;
  onDone?: () => void;
}) {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  async function block() {
    if (!user) return;
    if (
      !(await askConfirm({ title: `Block ${name}?`, message: "You won't see each other's posts, comments or messages, and neither of you can follow or message the other. Teams you share still work. They aren't told.", confirmLabel: "Block", destructive: true }))
    )
      return;
    setBusy(true);
    try {
      await blockPerson(user, uid);
      onDone?.();
    } catch (e) {
      alert(problem(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <button type="button" className={className} disabled={busy} onClick={() => void block()}>
      {label ?? `Block ${name}`}
    </button>
  );
}
