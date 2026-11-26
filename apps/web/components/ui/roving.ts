import { type RefObject, useEffect, type KeyboardEvent } from "react";

/** Marks a scrolling bar with which end has more (`data-edges`), for the fade; none when it fits. */
export function useEdgeFade(ref: RefObject<HTMLElement | null>) {
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const update = () => {
      const more = el.scrollWidth - el.clientWidth > 1;
      const start = more && el.scrollLeft > 1;
      const end = more && el.scrollLeft + el.clientWidth < el.scrollWidth - 1;
      if (start && end) el.dataset.edges = "both";
      else if (end) el.dataset.edges = "end";
      else if (start) el.dataset.edges = "start";
      else delete el.dataset.edges;
    };
    update();
    el.addEventListener("scroll", update, { passive: true });
    const ro = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(update);
    ro?.observe(el);
    return () => {
      el.removeEventListener("scroll", update);
      ro?.disconnect();
    };
  });
}

/**
 * The keyboard half of the ARIA tabs and radio-group patterns: Left and Right
 * (Up and Down in a radio group) move to the next enabled item and wrap,
 * Home and End go to the first and last. Returns the item to move to, or
 * null when the key is not one of those. [selector] picks the group's items
 * inside the event's container; the focused one is where the move starts.
 */
export function nextInGroup(e: KeyboardEvent<HTMLElement>, selector: string, vertical = false): HTMLElement | null {
  const keys = vertical ? ["ArrowRight", "ArrowDown"] : ["ArrowRight"];
  const back = vertical ? ["ArrowLeft", "ArrowUp"] : ["ArrowLeft"];
  const isNext = keys.includes(e.key);
  const isPrev = back.includes(e.key);
  if (!isNext && !isPrev && e.key !== "Home" && e.key !== "End") return null;
  if (e.altKey || e.ctrlKey || e.metaKey) return null;
  const items = [...e.currentTarget.querySelectorAll<HTMLElement>(selector)].filter((el) => !el.hasAttribute("disabled") && el.getAttribute("aria-disabled") !== "true");
  if (items.length === 0) return null;
  const from = items.findIndex((el) => el === document.activeElement || el.contains(document.activeElement));
  let to: number;
  if (e.key === "Home") to = 0;
  else if (e.key === "End") to = items.length - 1;
  else if (from < 0) to = isNext ? 0 : items.length - 1;
  else to = (from + (isNext ? 1 : -1) + items.length) % items.length;
  return items[to] ?? null;
}
