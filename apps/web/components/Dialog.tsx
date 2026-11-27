"use client";
import { type ReactNode, useLayoutEffect, useRef } from "react";

/**
 * A modal dialog: the browser's <dialog> opened with showModal(), so the
 * page behind is inert (focus stays inside), it's announced as modal, and
 * Esc asks [onClose]. Focus goes back where it was on closing. The box
 * itself is the child with [className] (a card, in the site's design).
 * [dismissOnBackdrop] closes it on a click outside the box too.
 */
export function Dialog({
  label,
  onClose,
  className,
  dismissOnBackdrop = false,
  children,
}: {
  label: string;
  onClose: () => void;
  className?: string;
  dismissOnBackdrop?: boolean;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  // A layout effect, so it's open before the children's effects run (one
  // may focus a button of its own).
  useLayoutEffect(() => {
    const d = ref.current;
    if (!d) return;
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    if (!d.open) d.showModal();
    // Esc: the owner decides (it unmounts this to close it).
    const onCancel = (e: Event) => {
      e.preventDefault();
      close.current();
    };
    // Closed by the browser anyway (some close a dialog on a second Esc).
    // Not a close queued before it was opened again (React's dev double
    // effects close and reopen it at once).
    const onClosed = () => {
      if (!d.open) close.current();
    };
    d.addEventListener("cancel", onCancel);
    d.addEventListener("close", onClosed);
    return () => {
      d.removeEventListener("cancel", onCancel);
      d.removeEventListener("close", onClosed);
      if (d.open) d.close();
      if (opener?.isConnected) opener.focus();
    };
  }, []);
  return (
    <dialog
      ref={ref}
      className="dialog"
      aria-label={label}
      aria-modal="true"
      // A click on the dialog element itself is on the backdrop around the box.
      onClick={dismissOnBackdrop ? (e) => e.target === e.currentTarget && close.current() : undefined}
      // Tab wraps inside the dialog: the browser would otherwise move on to its own controls.
      onKeyDown={(e) => {
        if (e.key !== "Tab") return;
        const items = Array.from(e.currentTarget.querySelectorAll<HTMLElement>('a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')).filter((el) => el.offsetParent !== null || el === document.activeElement);
        if (items.length === 0) return;
        const first = items[0]!;
        const last = items[items.length - 1]!;
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }}
    >
      <div className={className}>{children}</div>
    </dialog>
  );
}
