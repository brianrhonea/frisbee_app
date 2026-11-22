// Things the user sent while offline (or while the server couldn't be
// reached), kept on the device until they go out: messages, team chat,
// posts, team posts and comments. The website's queue
// (apps/web/lib/outbox.ts) and the app's (lib/domain/models/outbox.dart)
// follow these same rules, checked against fixtures/outbox, which the
// app's tests write.

export const outboxKinds = ["directMessage", "teamChat", "userPost", "teamPost", "comment"] as const;
export type OutboxKind = (typeof outboxKinds)[number];

export const outboxStates = ["waiting", "sending", "failed"] as const;
export type OutboxState = (typeof outboxStates)[number];

/** network: wait for a connection; retry: later, with backoff; permanent: the user decides; sent: already there. */
export type OutboxFailure = "network" | "retry" | "permanent" | "sent";

export const outboxLimits = {
  maxItems: 50,
  maxBytes: 200 * 1024 * 1024,
  backoffSeconds: [5, 15, 30, 60, 120, 300],
  /** How long a send may hang before it's queued instead. */
  sendTimeoutMs: 15_000,
} as const;

/** The wait before try [attempts] + 1 after a server error. */
export function outboxBackoffMs(attempts: number): number {
  const s = outboxLimits.backoffSeconds;
  return s[Math.min(Math.max(attempts, 0), s.length - 1)] * 1000;
}

/**
 * How an error code (ApiErrorCode, or a Firebase one) is treated. A sign-in
 * token that can't refresh offline comes as `unavailable`; a real
 * `unauthenticated` (a revoked session) is the user's to sort out.
 */
export function outboxFailureOf(code: string): OutboxFailure {
  switch (code) {
    case "unavailable":
    case "network":
    case "network-request-failed":
    case "deadline-exceeded":
    case "retry-limit-exceeded":
      return "network";
    case "internal":
    case "unknown":
    case "aborted":
    case "resource-exhausted":
    case "resource_exhausted":
      return "retry";
    case "already_exists":
    case "already-exists":
      return "sent";
    default:
      return "permanent";
  }
}

/**
 * How an API answer is treated: [status] 0 is no connection, 429 and 5xx
 * are worth another try later, else [code] decides.
 */
export function outboxFailureOfHttp(status: number, code?: string): OutboxFailure {
  if (status === 0) return "network";
  if (code === "already_exists") return "sent";
  if (status === 429 || status >= 500) return code === "unavailable" ? "network" : "retry";
  return code ? outboxFailureOf(code) : "permanent";
}

/** One queued item; [id] is the id the message, post or comment gets, the same on every try. */
export interface OutboxJob {
  id: string;
  uid: string;
  kind: OutboxKind;
  /** ISO time it was queued. */
  createdAt: string;
  /** Where it goes; items for one place go out in order. */
  target: string;
  label: string;
  state: OutboxState;
  attempts: number;
  nextTryAt: string | null;
  error: string | null;
}

/** [job] after a try that ended in [failure] (null: it went through), or null once it's done. */
export function afterTry<J extends OutboxJob>(job: J, failure: OutboxFailure | null, now: Date, message?: string): J | null {
  switch (failure) {
    case null:
    case "sent":
      return null;
    case "network":
      return { ...job, state: "waiting", nextTryAt: null };
    case "retry":
      return { ...job, state: "waiting", attempts: job.attempts + 1, nextTryAt: new Date(now.getTime() + outboxBackoffMs(job.attempts)).toISOString() };
    case "permanent":
      return { ...job, state: "failed", attempts: job.attempts + 1, nextTryAt: null, error: message ?? "Couldn't be sent." };
  }
}

/** The items to send now for [uid], oldest first; one waiting for its next try holds back the rest of its place. */
export function dueJobs<J extends OutboxJob>(jobs: J[], uid: string, now: Date): J[] {
  const held = new Set<string>();
  const due: J[] = [];
  const mine = jobs.filter((j) => j.uid === uid).sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
  for (const j of mine) {
    if (j.state !== "waiting" || held.has(j.target)) continue;
    if (j.nextTryAt && Date.parse(j.nextTryAt) > now.getTime()) {
      held.add(j.target);
      continue;
    }
    due.push(j);
  }
  return due;
}
