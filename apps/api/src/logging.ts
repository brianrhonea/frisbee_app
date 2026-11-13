// Request logs as Cloud Logging reads them from stdout: one JSON object per
// line with `severity`, `message` and an RFC 3339 `time`, and each request's
// lines grouped under its trace.
import type { FastifyServerOptions } from "fastify";

/** pino options, as Fastify's `logger` takes them. */
export type LoggerOptions = Exclude<NonNullable<FastifyServerOptions["logger"]>, boolean>;
type ChildLoggerFactory = NonNullable<FastifyServerOptions["childLoggerFactory"]>;

const severities: Record<string, string> = {
  trace: "DEBUG",
  debug: "DEBUG",
  info: "INFO",
  warn: "WARNING",
  error: "ERROR",
  fatal: "CRITICAL",
};

/** Fastify (pino) logger options for Cloud Run. */
export function cloudLoggingOptions(level = process.env.LOG_LEVEL ?? "info"): LoggerOptions {
  return {
    level,
    messageKey: "message",
    timestamp: () => `,"time":"${new Date().toISOString()}"`,
    formatters: {
      level: (label: string) => ({ severity: severities[label] ?? "DEFAULT" }),
    },
  };
}

/**
 * The Cloud Logging trace field for an `X-Cloud-Trace-Context` header
 * (`TRACE_ID/SPAN_ID;o=1`), or null without one.
 */
export function traceField(header: unknown, projectId: string): Record<string, string> | null {
  if (typeof header !== "string") return null;
  const traceId = header.split("/")[0];
  if (!/^[0-9a-f]{32}$/i.test(traceId)) return null;
  return { "logging.googleapis.com/trace": `projects/${projectId}/traces/${traceId}` };
}

/** Tags every log line of a request, Fastify's own included, with its trace. */
export function traceLoggerFactory(projectId: string): ChildLoggerFactory {
  return (logger, bindings, opts, rawReq) => {
    const field = traceField(rawReq.headers["x-cloud-trace-context"], projectId);
    return logger.child(field ? { ...bindings, ...field } : bindings, opts);
  };
}
