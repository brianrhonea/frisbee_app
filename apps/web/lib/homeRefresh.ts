"use client";
/**
 * Home clicked while already on it (as tapping the app's Home tab again):
 * the dashboard reloads its feed from the newest posts.
 */
const event = "stall10:home-refresh";

export function requestHomeRefresh() {
  window.dispatchEvent(new Event(event));
}

/** Home's new-post box (never a post being edited): what `n` and #compose focus. */
export const newPostBox = ".composer[data-compose=new] textarea";

export function onHomeRefresh(fn: () => void): () => void {
  window.addEventListener(event, fn);
  return () => window.removeEventListener(event, fn);
}
