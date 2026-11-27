"use client";
import { type KeyboardEvent, type ReactNode, useEffect, useRef } from "react";
import { nextInGroup, useEdgeFade } from "./roving";
import "./ui.css";

/**
 * Tabs for switching a view or a panel, the website's SegmentedTabs (the
 * app's SegmentedTabs): the selected tab is filled indigo, the bar scrolls
 * sideways when the tabs don't fit (it never wraps or clips, so it holds up
 * at large text) and the keyboard works as the ARIA tabs pattern says: one
 * Tab stop on the selected tab, Left and Right move along and wrap, Home and
 * End jump, and the tab you land on is selected.
 *
 * `variant="underline"` is the same control drawn as a line under the page
 * header (the feed's tabs). To filter a list rather than switch a view, use
 * FilterChips. Tabs that navigate are links, not tabs: they are not this.
 */
export interface TabItem {
  id: string;
  label: ReactNode;
  disabled?: boolean;
}

export interface SegmentedTabsProps {
  items: readonly TabItem[];
  value: string;
  onChange: (id: string) => void;
  /** What the tabs switch, announced with the group ("View", "Division"). */
  label: string;
  variant?: "segmented" | "underline";
  /** Layout hooks from the caller (margin, alignment), not colours. */
  className?: string;
  /** A stable id for a tab, so a panel can name it (`aria-labelledby`). */
  tabId?: (id: string) => string;
  /** The id of the panel the selected tab controls, when the panel exists. */
  panelId?: (id: string) => string;
}

export function SegmentedTabs({ items, value, onChange, label, variant = "segmented", className, tabId, panelId }: SegmentedTabsProps) {
  const first = useRef(true);
  const bar = useRef<HTMLDivElement>(null);
  useEdgeFade(bar);
  const hasValue = items.some((t) => t.id === value);

  // A long bar scrolls the selected tab into view (not on the first paint).
  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    // The bar scrolls the tab into view, but the page stays where it is: scrollIntoView also moves the page
    // when the bar sits near the screen's edge (the feed tabs on a phone's Home scrolled it by itself after load).
    const el = bar.current?.querySelector<HTMLElement>('[aria-selected="true"]');
    if (!el?.scrollIntoView) return;
    const { scrollX, scrollY } = window;
    el.scrollIntoView({ block: "nearest", inline: "nearest" });
    window.scrollTo({ left: scrollX, top: scrollY, behavior: "instant" });
  }, [value]);

  function onKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    const to = nextInGroup(e, '[role="tab"]');
    if (!to) return;
    e.preventDefault();
    to.focus();
    const id = to.getAttribute("data-tab");
    if (id !== null && id !== value) onChange(id);
  }

  return (
    <div ref={bar} role="tablist" aria-label={label} className={`ui-tabs ui-tabs-${variant}${className ? ` ${className}` : ""}`} onKeyDown={onKeyDown}>
      {items.map((t) => {
        const on = t.id === value;
        // With no tab selected (a value that matches none) the first one stays reachable.
        const stop = on || (!hasValue && t === items.find((x) => !x.disabled));
        return (
          <button
            key={t.id}
            type="button"
            role="tab"
            id={tabId?.(t.id)}
            data-tab={t.id}
            aria-selected={on}
            aria-controls={on && panelId ? panelId(t.id) : undefined}
            tabIndex={stop ? 0 : -1}
            disabled={t.disabled}
            onClick={() => onChange(t.id)}
          >
            <span className="ui-face">{t.label}</span>
          </button>
        );
      })}
    </div>
  );
}
