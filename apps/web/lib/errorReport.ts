import { apiBase } from "./client";

/**
 * Crash reporting (#7): sends an uncaught error to the API's
 * POST /v1/client-errors, which forwards it to Cloud Error Reporting.
 *
 * What is sent: message, stack (8 KB at most), the page's path (never the
 * query string or hash), the web version and Next's error digest. Nothing
 * else: no cookies or tokens, no user content. Emails, query strings and
 * long token-like strings inside the message or stack are blanked first.
 * Every failure here is swallowed: reporting must never break the page.
 */

export const MAX_STACK = 8 * 1024;
const MAX_MESSAGE = 1024;
/** At most this many reports from one page load. */
export const MAX_REPORTS = 5;

export interface ClientErrorPayload {
  message: string;
  stack: string;
  url: string;
  release: string;
  digest?: string;
}

const seen = new Set<string>();
let sent = 0;

/** Forgets what was sent (tests only; a page load starts empty anyway). */
export function resetErrorReports(): void {
  seen.clear();
  sent = 0;
}

/** Blanks anything that could identify a person or carry a credential. */
export function redact(text: string): string {
  return (
    text
      .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+/g, "[email]")
      .replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, "[token]")
      .replace(/\bBearer\s+\S+/gi, "Bearer [token]")
      // A query string or fragment on any URL or path in the text.
      .replace(/(https?:\/\/[^\s)"'?#]+|\/[\w./-]+)[?#][^\s)"']*/g, "$1")
      // Long unbroken id-like strings (tokens, keys).
      .replace(/\b[A-Za-z0-9_-]{32,}\b/g, "[id]")
  );
}

function currentPath(): string {
  try {
    return window.location.pathname || "/";
  } catch {
    return "/";
  }
}

export function buildPayload(error: unknown, digest?: string): ClientErrorPayload {
  const e = error instanceof Error ? error : undefined;
  const message = e ? e.message : typeof error === "string" ? error : "Non-error value thrown";
  const stack = e?.stack ?? "";
  const d = digest ?? (error as { digest?: unknown } | null | undefined)?.digest;
  return {
    message: redact(String(message)).slice(0, MAX_MESSAGE),
    stack: redact(stack).slice(0, MAX_STACK),
    url: currentPath(),
    release: process.env.NEXT_PUBLIC_APP_VERSION || "unknown",
    ...(typeof d === "string" && d ? { digest: d.slice(0, 64) } : {}),
  };
}

function signature(p: ClientErrorPayload): string {
  return `${p.message}|${p.stack.split("\n").slice(0, 2).join("|")}|${p.digest ?? ""}`;
}

/**
 * Reports [error] once per page load per signature, and at most
 * MAX_REPORTS times. Returns whether a report was sent.
 */
export function reportClientError(error: unknown, digest?: string): boolean {
  try {
    const payload = buildPayload(error, digest);
    const sig = signature(payload);
    if (seen.has(sig) || sent >= MAX_REPORTS) return false;
    seen.add(sig);
    sent++;
    const endpoint = `${apiBase}/v1/client-errors`;
    const body = JSON.stringify(payload);
    if (typeof fetch === "function") {
      void fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        keepalive: true,
        credentials: "omit",
      }).catch(() => {});
    } else if (typeof navigator !== "undefined" && typeof navigator.sendBeacon === "function") {
      navigator.sendBeacon(endpoint, new Blob([body], { type: "application/json" }));
    }
    return true;
  } catch {
    return false;
  }
}

/** Reports errors nothing caught. Returns the function that removes the listeners. */
export function installGlobalErrorReporting(): () => void {
  const onError = (ev: ErrorEvent) => reportClientError(ev.error ?? ev.message);
  const onRejection = (ev: PromiseRejectionEvent) => reportClientError(ev.reason);
  window.addEventListener("error", onError);
  window.addEventListener("unhandledrejection", onRejection);
  return () => {
    window.removeEventListener("error", onError);
    window.removeEventListener("unhandledrejection", onRejection);
  };
}
