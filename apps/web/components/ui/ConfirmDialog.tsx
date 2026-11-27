"use client";
import { createContext, type ReactNode, useCallback, useContext, useEffect, useId, useRef, useState } from "react";
import { Dialog } from "../Dialog";
import { Button } from "./Button";
import "./ui.css";

/**
 * "Are you sure?" (the app's ConfirmDialog): a modal built on Dialog, so the
 * page behind is inert, focus stays inside (the browser's own trap for
 * showModal), Esc cancels and focus returns to what opened it. The
 * destructive variant paints the confirm button red and puts the first focus
 * on Cancel, so an Enter never deletes by accident. Messages keep their line
 * breaks.
 */
export interface ConfirmDialogProps {
  title: string;
  message?: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
  /** Saving: the confirm button shows its spinner and ignores clicks. */
  busy?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export function ConfirmDialog({ title, message, confirmLabel = "Confirm", cancelLabel = "Cancel", destructive = false, busy = false, onConfirm, onCancel }: ConfirmDialogProps) {
  const titleId = useId();
  const first = useRef<HTMLButtonElement>(null);
  const confirm = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    (destructive ? first : confirm).current?.focus();
  }, [destructive]);
  return (
    <Dialog label={title} onClose={onCancel} className="card confirm-dialog" dismissOnBackdrop>
      <h2 id={titleId} className="card-title">
        {title}
      </h2>
      {message ? <div className="confirm-message">{message}</div> : null}
      <div className="confirm-actions">
        <button ref={first} type="button" className="btn" onClick={onCancel}>
          {cancelLabel}
        </button>
        <Button ref={confirm} variant={destructive ? "destructive" : "primary"} loading={busy} onClick={onConfirm}>
          {confirmLabel}
        </Button>
      </div>
    </Dialog>
  );
}

/** What [useConfirm] takes: a message, or the full set. */
export type ConfirmOptions = string | { title?: string; message?: ReactNode; confirmLabel?: string; cancelLabel?: string; destructive?: boolean };

type Ask = (options: ConfirmOptions) => Promise<boolean>;
const Ctx = createContext<Ask | null>(null);

/**
 * Mounted once in the layout. `const confirm = useConfirm()` then
 * `if (!(await confirm("Delete this?"))) return;` replaces window.confirm.
 */
export function ConfirmProvider({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState<{ options: Exclude<ConfirmOptions, string>; resolve: (ok: boolean) => void } | null>(null);
  const ask = useCallback<Ask>(
    (options) =>
      new Promise<boolean>((resolve) => {
        // A second question while one is open answers the first with "no".
        setOpen((prev) => {
          prev?.resolve(false);
          return { options: typeof options === "string" ? { message: options } : options, resolve };
        });
      }),
    [],
  );
  function done(ok: boolean) {
    open?.resolve(ok);
    setOpen(null);
  }
  const o = open?.options;
  return (
    <Ctx.Provider value={ask}>
      {children}
      {open && o ? (
        <ConfirmDialog
          title={o.title ?? "Are you sure?"}
          message={o.message || undefined}
          confirmLabel={o.confirmLabel}
          cancelLabel={o.cancelLabel}
          destructive={o.destructive}
          onConfirm={() => done(true)}
          onCancel={() => done(false)}
        />
      ) : null}
    </Ctx.Provider>
  );
}

/** Where there is no provider (an isolated test), the browser's own confirm. */
const fallback: Ask = async (options) => window.confirm(typeof options === "string" ? options : String(options.message ?? options.title ?? ""));

export function useConfirm(): Ask {
  return useContext(Ctx) ?? fallback;
}
