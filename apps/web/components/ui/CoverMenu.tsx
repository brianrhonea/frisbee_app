"use client";
import { type KeyboardEvent, useEffect, useId, useRef, useState } from "react";
import "./ui.css";

/**
 * The round "…" button over a cover photo that opens a short menu (the app's CoverMenuButton): a profile's
 * Report, Block and Share. A button with `aria-haspopup="menu"` and `aria-expanded`; the list is a
 * `role="menu"` of `menuitem`s. Enter, Space or Down opens it on the first item; Up and Down, Home and End
 * move; Escape closes and returns to the button; Tab or a click outside closes it. [status] is a short
 * confirmation ("Link copied") announced politely beside the button.
 */
export interface CoverMenuItem {
  id: string;
  label: string;
  /** Drawn in the danger colour (Block). */
  danger?: boolean;
  onSelect: () => void;
}

export function CoverMenu({ items, label = "More options", status }: { items: readonly CoverMenuItem[]; label?: string; status?: string }) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const menuId = useId();

  const rows = () => Array.from(list.current?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]') ?? []);
  const focusRow = (i: number) => {
    const r = rows();
    if (r.length) r[(i + r.length) % r.length]?.focus();
  };
  const close = (back: boolean) => {
    setOpen(false);
    if (back) button.current?.focus();
  };

  // Focus the first item once the list is on screen.
  useEffect(() => {
    if (open) focusRow(0);
  }, [open]);

  // A click or focus outside closes it.
  useEffect(() => {
    if (!open) return;
    const away = (e: Event) => {
      if (root.current && !root.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", away);
    document.addEventListener("focusin", away);
    return () => {
      document.removeEventListener("pointerdown", away);
      document.removeEventListener("focusin", away);
    };
  }, [open]);

  function onButtonKey(e: KeyboardEvent) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setOpen(true);
    }
  }

  function onListKey(e: KeyboardEvent) {
    const i = rows().indexOf(document.activeElement as HTMLButtonElement);
    if (e.key === "ArrowDown") focusRow(i + 1);
    else if (e.key === "ArrowUp") focusRow(i - 1);
    else if (e.key === "Home") focusRow(0);
    else if (e.key === "End") focusRow(-1);
    else if (e.key === "Escape") close(true);
    else if (e.key === "Tab") close(false);
    else return;
    if (e.key !== "Tab") e.preventDefault();
  }

  return (
    <div className="ui-cover-menu" ref={root}>
      {status ? (
        <span className="ui-cover-menu-status" role="status">
          {status}
        </span>
      ) : (
        <span className="sr-only" role="status" />
      )}
      <button
        ref={button}
        type="button"
        className="ui-cover-menu-btn"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        onClick={() => setOpen((o) => !o)}
        onKeyDown={onButtonKey}
      >
        <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="currentColor">
          <circle cx="5" cy="12" r="2" />
          <circle cx="12" cy="12" r="2" />
          <circle cx="19" cy="12" r="2" />
        </svg>
      </button>
      {open && (
        <div id={menuId} ref={list} role="menu" aria-label={label} className="ui-cover-menu-list" onKeyDown={onListKey}>
          {items.map((it) => (
            <button
              key={it.id}
              type="button"
              role="menuitem"
              tabIndex={-1}
              className={it.danger ? "danger" : undefined}
              onClick={() => {
                close(true);
                it.onSelect();
              }}
            >
              {it.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
