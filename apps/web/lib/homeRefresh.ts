"use client";
/**
 * Home clicked while already on it (as tapping the app's Home tab again):
 * the dashboard reloads its feed from the newest posts.
 */
const event = "stall10:home-refresh";

export function requestHomeRefresh() {
  window.dispatchEvent(new Event(event));
}

export function onHomeRefresh(fn: () => void): () => void {
  window.addEventListener(event, fn);
  return () => window.removeEventListener(event, fn);
}
