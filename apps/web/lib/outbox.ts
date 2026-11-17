"use client";
// The offline queue: messages, team chat, posts, team posts and comments
// sent while Stall 10 can't be reached wait in this browser (IndexedDB)
// and go out by themselves, in order, once it can. Each keeps the id it
// was given when the member sent it, and the API turns down a second
// copy (already_exists), so nothing is posted twice. Photos and files are
// already uploaded when the member sends (uploads wait on the server), so
// a queued item is just its API request. The rules are the shared ones
// (packages/shared/src/outbox.ts), as in the app's OutboxRepository.
import { afterTry, dueJobs, type OutboxFailure, type OutboxJob, type OutboxKind, outboxBackoffMs, outboxFailureOfHttp, outboxLimits } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useSyncExternalStore } from "react";
import { ApiError, callApi } from "./client";
import { firebaseAuth } from "./firebase";
import { checkOnline, isOnline, onOnlineChange, reportOffline, reportOnline } from "./online";

/** A queued item: the shared fields, and the API request that sends it. */
export interface WebOutboxJob extends OutboxJob {
  path: string;
  body: Record<string, unknown>;
  /** Its words, for the "waiting to send" list and the thread. */
  preview: string;
  /** How many files it carries. */
  files: number;
  /** A message's reply, shown on its pending bubble. */
  replyTo?: { authorName?: string; text?: string } | null;
}

const dbName = "stall10-outbox";
const storeName = "jobs";
const channelName = "stall10-outbox";

let jobs: WebOutboxJob[] = [];
let snapshot: WebOutboxJob[] = [];
const listeners = new Set<() => void>();
let loaded: Promise<void> | null = null;
let channel: BroadcastChannel | null = null;
let timer: ReturnType<typeof setTimeout> | null = null;
let draining: Promise<void> | null = null;
let again = false;
const queuedListeners = new Set<(job: WebOutboxJob) => void>();

function uid(): string {
  return firebaseAuth()?.currentUser?.uid ?? "";
}

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(dbName, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(storeName, { keyPath: "id" });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function readAll(): Promise<WebOutboxJob[]> {
  try {
    const db = await open();
    return await new Promise((resolve, reject) => {
      const req = db.transaction(storeName).objectStore(storeName).getAll();
      req.onsuccess = () => resolve((req.result as WebOutboxJob[]).map((j) => (j.state === "sending" ? { ...j, state: "waiting" } : j)));
      req.onerror = () => reject(req.error);
    });
  } catch {
    // Private windows and blocked storage: the queue lives only in this tab.
    return jobs;
  }
}

async function write(job: WebOutboxJob | null, removeId?: string): Promise<void> {
  try {
    const db = await open();
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(storeName, "readwrite");
      if (job) tx.objectStore(storeName).put(job);
      if (removeId) tx.objectStore(storeName).delete(removeId);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // Kept in memory only.
  }
  channel?.postMessage("changed");
}

function emit() {
  const me = uid();
  snapshot = jobs.filter((j) => j.uid === me).sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
  for (const l of listeners) l();
}

function set(job: WebOutboxJob) {
  jobs = [...jobs.filter((j) => j.id !== job.id), job];
  emit();
}

function drop(id: string) {
  jobs = jobs.filter((j) => j.id !== id);
  emit();
}

function start(): Promise<void> {
  if (loaded) return loaded;
  if (typeof window === "undefined") return Promise.resolve();
  loaded = (async () => {
    jobs = await readAll();
    emit();
    if ("BroadcastChannel" in window) {
      channel = new BroadcastChannel(channelName);
      // Another tab changed the queue: read it again.
      channel.onmessage = () =>
        void readAll().then((all) => {
          jobs = all;
          emit();
        });
    }
    onOnlineChange(() => {
      emit();
      if (isOnline()) void drainOutbox();
    });
    firebaseAuth()?.onAuthStateChanged(() => {
      emit();
      void drainOutbox();
    });
    void drainOutbox();
  })();
  return loaded;
}

async function enqueue(job: WebOutboxJob): Promise<void> {
  const mine = jobs.filter((j) => j.uid === job.uid);
  if (mine.length >= outboxLimits.maxItems) {
    throw new ApiError("You're offline and too much is already waiting to send. Try again once you have a connection.", 400);
  }
  set(job);
  await write(job);
  for (const l of queuedListeners) l(job);
  schedule();
}

function failureOf(e: unknown): OutboxFailure {
  if (e instanceof ApiError) return outboxFailureOfHttp(e.status, e.code);
  if (e instanceof DOMException && (e.name === "TimeoutError" || e.name === "AbortError")) return "network";
  return "permanent";
}

function timeout<T>(p: Promise<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new DOMException("Timed out", "TimeoutError")), outboxLimits.sendTimeoutMs);
    p.then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e) => {
        clearTimeout(t);
        reject(e);
      },
    );
  });
}

/**
 * Sends [req] now when Stall 10 can be reached, else (or when the send
 * can't get through) queues it to go out later under the same id. Resolves
 * "sent" or "queued"; throws when the server turned it down.
 */
export async function submitOutbox(
  user: User,
  req: { kind: OutboxKind; id: string; target: string; label: string; path: string; body: Record<string, unknown>; preview: string; files?: number; replyTo?: WebOutboxJob["replyTo"] },
): Promise<"sent" | "queued"> {
  await start();
  const body = { ...req.body, id: req.id };
  const queue = (failure: OutboxFailure) =>
    enqueue({
      id: req.id,
      uid: user.uid,
      kind: req.kind,
      createdAt: new Date().toISOString(),
      target: req.target,
      label: req.label,
      state: "waiting",
      // A server error waits before trying again.
      attempts: failure === "retry" ? 1 : 0,
      nextTryAt: failure === "retry" ? new Date(Date.now() + outboxBackoffMs(0)).toISOString() : null,
      error: null,
      path: req.path,
      body,
      preview: req.preview,
      files: req.files ?? 0,
      replyTo: req.replyTo ?? null,
    }).then(() => "queued" as const);
  if (!isOnline()) return queue("network");
  try {
    await timeout(callApi(user, req.path, { method: "POST", body }));
    reportOnline();
    return "sent";
  } catch (e) {
    const failure = failureOf(e);
    if (failure === "sent") return "sent";
    if (failure === "permanent") throw e;
    if (failure === "network") reportOffline();
    return queue(failure);
  }
}

async function tryOne(job: WebOutboxJob, user: User): Promise<boolean> {
  set({ ...job, state: "sending" });
  let failure: OutboxFailure | null = null;
  let message: string | undefined;
  try {
    await timeout(callApi(user, job.path, { method: "POST", body: job.body }));
  } catch (e) {
    failure = failureOf(e);
    message = e instanceof ApiError ? e.message : undefined;
  }
  const next = afterTry(job, failure, new Date(), message);
  if (next) {
    set(next);
    await write(next);
  } else {
    drop(job.id);
    await write(null, job.id);
  }
  if (failure === "network") {
    reportOffline();
    return false;
  }
  if (failure === null || failure === "sent") reportOnline();
  return true;
}

async function drainLoop(): Promise<void> {
  do {
    again = false;
    while (isOnline()) {
      const user = firebaseAuth()?.currentUser;
      if (!user) break;
      const due = dueJobs(jobs, user.uid, new Date());
      if (due.length === 0) break;
      if (!(await tryOne(due[0], user))) break;
    }
  } while (again);
}

/**
 * Sends what's due, one at a time. One tab at a time does it (a Web Lock),
 * so two tabs never send the same item at once.
 */
export function drainOutbox(): Promise<void> {
  if (typeof window === "undefined") return Promise.resolve();
  if (draining) {
    again = true;
    return draining;
  }
  const run = async () => {
    await start();
    if (navigator.locks) {
      await navigator.locks.request("stall10-outbox", async () => {
        // What another tab sent while this one waited for the lock.
        jobs = await readAll();
        emit();
        await drainLoop();
      });
    } else {
      await drainLoop();
    }
  };
  draining = run().finally(() => {
    draining = null;
    schedule();
  });
  return draining;
}

/** Wakes up for the next item waiting out its backoff. */
function schedule() {
  if (timer) clearTimeout(timer);
  timer = null;
  const me = uid();
  const next = jobs
    .filter((j) => j.uid === me && j.state === "waiting" && j.nextTryAt)
    .map((j) => Date.parse(j.nextTryAt!))
    .sort((a, b) => a - b)[0];
  if (next === undefined) return;
  timer = setTimeout(() => void drainOutbox(), Math.max(0, next - Date.now()));
}

/** Tries the failed item [id] again. */
export async function retryOutbox(id: string): Promise<void> {
  const job = jobs.find((j) => j.id === id && j.uid === uid());
  if (!job) return;
  const next: WebOutboxJob = { ...job, state: "waiting", nextTryAt: null, error: null };
  set(next);
  await write(next);
  if (!isOnline()) await checkOnline();
  await drainOutbox();
}

/** Drops the item [id] without sending it. */
export async function discardOutbox(id: string): Promise<void> {
  const job = jobs.find((j) => j.id === id && j.uid === uid());
  if (!job || job.state === "sending") return;
  drop(id);
  await write(null, id);
}

function subscribe(listener: () => void): () => void {
  void start();
  listeners.add(listener);
  return () => listeners.delete(listener);
}

const empty: WebOutboxJob[] = [];

/** The signed-in member's queued items, oldest first. */
export function useOutbox(): WebOutboxJob[] {
  return useSyncExternalStore(subscribe, () => snapshot, () => empty);
}

/** The member's queued items of [kind] for [target]. */
export function useOutboxFor(kind: OutboxKind, target: string): WebOutboxJob[] {
  const all = useOutbox();
  return all.filter((j) => j.kind === kind && j.target === target);
}

/** Each item as it's queued (for the "will send by itself" notice). */
export function onQueued(listener: (job: WebOutboxJob) => void): () => void {
  queuedListeners.add(listener);
  return () => queuedListeners.delete(listener);
}

/** The line under a queued item: waiting, sending, or why it failed. */
export function outboxStateText(job: WebOutboxJob): string {
  switch (job.state) {
    case "waiting":
      return "Waiting to send";
    case "sending":
      return "Sending…";
    case "failed":
      return job.error ?? "Couldn't be sent.";
  }
}

/** What a composer shows when its item was queued instead of sent. */
export function queuedNotice(label: string): string {
  return `Couldn't reach Stall 10. Your ${label.toLowerCase()} will send by itself once it can.`;
}
