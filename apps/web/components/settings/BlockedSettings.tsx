"use client";
import Link from "next/link";
import { useState } from "react";
import { problem } from "@/lib/client";
import { unblockPerson, useBlocks } from "@/lib/moderation";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { useConfirm } from "@/components/ui/ConfirmDialog";

/** Settings › Blocked accounts: who the member blocked, each with Unblock (the app's BlockedAccountsScreen). */
export function BlockedSettings() {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const blocks = useBlocks(user);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  if (!user) return null;
  const me = user;

  async function unblock(uid: string, name: string) {
    if (!(await askConfirm(`Unblock ${name}? You'll see each other's posts and can follow and message again.`))) return;
    setBusy(uid);
    setError(null);
    try {
      await unblockPerson(me, uid);
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="stack">
      <section className="card">
        <h2 className="card-title">Blocked accounts</h2>
        <p className="muted small">
          You and the people you block don&apos;t see each other&apos;s posts, comments or messages, and can&apos;t follow or message each
          other. Teams you share still work. They aren&apos;t told. See the <Link href="/guidelines">community guidelines</Link>.
        </p>
        {error && <p className="form-error">{error}</p>}
        {!blocks.loaded ? (
          <p className="muted">Loading…</p>
        ) : blocks.blocked.length === 0 ? (
          <p className="empty">You haven&apos;t blocked anyone.</p>
        ) : (
          <ul className="blocked-list">
            {blocks.blocked.map((b) => (
              <li key={b.uid}>
                <Avatar name={b.name} url={b.photoUrl ?? undefined} size={34} />
                <span className="blocked-who">
                  <b>{b.name}</b>
                  {b.username && <span className="muted small"> @{b.username}</span>}
                </span>
                <button type="button" className="btn btn-small" disabled={busy === b.uid} onClick={() => void unblock(b.uid, b.name)}>
                  Unblock
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
