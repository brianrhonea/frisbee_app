"use client";
import { type KeyboardEvent, type ReactNode, useRef } from "react";
import { nextInGroup, useEdgeFade } from "./roving";
import "./ui.css";

/**
 * Chips that filter a list, the website's FilterChips (the app's FilterChip):
 * a filled indigo chip is on. They scroll sideways when they don't fit.
 *
 * One choice (`value` a string) is a radio group: one Tab stop, arrows move
 * and choose. Several (`multiple`, `value` a list) are toggle buttons with
 * `aria-pressed`, each its own Tab stop. Chips filter; to switch between
 * views use SegmentedTabs.
 */
export interface ChipItem {
  id: string;
  label: ReactNode;
  disabled?: boolean;
}

type Common = {
  items: readonly ChipItem[];
  /** What the chips filter, announced with the group ("Show", "Type"). */
  label: string;
  className?: string;
};
export type FilterChipsProps =
  | (Common & { multiple?: false; value: string; onChange: (id: string) => void })
  | (Common & { multiple: true; value: readonly string[]; onChange: (ids: string[]) => void });

export function FilterChips(props: FilterChipsProps) {
  const { items, label, className } = props;
  const bar = useRef<HTMLDivElement>(null);
  useEdgeFade(bar);
  const cls = `ui-tabs ui-chips${className ? ` ${className}` : ""}`;

  if (props.multiple) {
    const { value, onChange } = props;
    return (
      <div ref={bar} role="group" aria-label={label} className={cls}>
        {items.map((c) => {
          const on = value.includes(c.id);
          return (
            <button key={c.id} type="button" aria-pressed={on} disabled={c.disabled} onClick={() => onChange(on ? value.filter((v) => v !== c.id) : [...value, c.id])}>
              <span className="ui-face">{c.label}</span>
            </button>
          );
        })}
      </div>
    );
  }

  const { value, onChange } = props;
  const hasValue = items.some((c) => c.id === value);
  function onKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    const to = nextInGroup(e, '[role="radio"]', true);
    if (!to) return;
    e.preventDefault();
    to.focus();
    const id = to.getAttribute("data-chip");
    if (id !== null && id !== value) onChange(id);
  }
  return (
    <div ref={bar} role="radiogroup" aria-label={label} className={cls} onKeyDown={onKeyDown}>
      {items.map((c) => {
        const on = c.id === value;
        const stop = on || (!hasValue && c === items.find((x) => !x.disabled));
        return (
          <button key={c.id} type="button" role="radio" data-chip={c.id} aria-checked={on} tabIndex={stop ? 0 : -1} disabled={c.disabled} onClick={() => onChange(c.id)}>
            <span className="ui-face">{c.label}</span>
          </button>
        );
      })}
    </div>
  );
}
