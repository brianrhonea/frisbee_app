"use client";
// Whether Stall 10 can be reached. The browser's online/offline events are
// a hint (offline means offline straight away); a send that couldn't reach
// the API also marks it offline. While offline it asks the API
// (`GET /health`) every 15 seconds until it answers. The app's
// ConnectivityService does the same.
import { useSyncExternalStore } from "react";
import { apiBase } from "./client";

const probeEveryMs = 15_000;

let online = true;
let timer: ReturnType<typeof setInterval> | null = null;
const listeners = new Set<() => void>();
let started = false;

function set(next: boolean) {
  if (online === next) return;
  online = next;
  if (next) {
    if (timer) clearInterval(timer);
    timer = null;
  } else if (!timer) {
    timer = setInterval(() => void checkOnline(), probeEveryMs);
  }
  for (const l of listeners) l();
}

function start() {
  if (started || typeof window === "undefined") return;
  started = true;
  if (!navigator.onLine) set(false);
  window.addEventListener("offline", () => set(false));
  window.addEventListener("online", () => void checkOnline());
}

/** Asks the API now; true when it answered. */
export async function checkOnline(): Promise<boolean> {
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    set(false);
    return false;
  }
  let ok = false;
  try {
    const res = await fetch(new URL("/health", apiBase), { cache: "no-store", signal: AbortSignal.timeout(5000) });
    ok = res.ok;
  } catch {
    ok = false;
  }
  set(ok);
  return ok;
}

/** A send couldn't reach the API. */
export function reportOffline() {
  set(false);
}

/** Something reached the API. */
export function reportOnline() {
  if (typeof navigator === "undefined" || navigator.onLine) set(true);
}

export function isOnline(): boolean {
  start();
  return online;
}

export function onOnlineChange(listener: () => void): () => void {
  start();
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** Whether Stall 10 can be reached, kept up to date. */
export function useOnline(): boolean {
  return useSyncExternalStore(onOnlineChange, isOnline, () => true);
}
