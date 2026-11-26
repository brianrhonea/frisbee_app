// `POST /v1/client-errors`: the website's error reporter (browser errors,
// error pages). Open to anyone (`config.public`: no token, no App Check,
// never an account), answers 204 for every well-formed report, and writes
// one entry that Cloud Error Reporting groups. The Flutter app reports to
// Crashlytics instead.
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { visitorIp } from "../browse/admit.js";
import { parseBody } from "../errors.js";
import { MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import { redact, sanitizePath } from "./sanitize.js";

const minute = 60_000;
/** Per IP, in memory (per instance): a page stuck in an error loop mustn't flood the logs. */
export const clientErrorLimits: Limit[] = [
  { max: 30, windowMs: minute },
  { max: 300, windowMs: 24 * 60 * minute },
];

/** Larger bodies are refused by Fastify (413, shown as invalid_argument). */
export const clientErrorBodyLimit = 16 * 1024;

export const clientErrorSchema = z
  .object({
    message: z.string().max(1024),
    stack: z.string().max(8 * 1024),
    /** A path; a full URL is accepted and cut down to its path. */
    url: z.string().min(1).max(512),
    release: z.string().min(1).max(64),
    digest: z.string().max(128).optional(),
  })
  .strict();
export type ClientError = z.infer<typeof clientErrorSchema>;

export const reportedErrorType = "type.googleapis.com/google.devtools.clouderrorreporting.v1beta1.ReportedErrorEvent";

/**
 * The Cloud Logging entry for [e] (already validated). Error Reporting only
 * groups entries whose `message` looks like a stack trace, so the stack goes
 * there; a report without one falls back to the message, which Error
 * Reporting may then show ungrouped. No user id, no IP.
 */
export function reportedErrorEntry(e: ClientError): Record<string, unknown> {
  const message = redact(e.message);
  const stack = redact(e.stack);
  const hasStack = stack.trim() !== "";
  return {
    severity: "ERROR",
    "@type": reportedErrorType,
    serviceContext: { service: "web", version: redact(e.release).slice(0, 64) },
    message: hasStack ? stack : message,
    ...(hasStack && message !== stack ? { reportedMessage: message } : {}),
    context: { httpRequest: { url: sanitizePath(e.url) } },
    ...(e.digest ? { digest: redact(e.digest).slice(0, 128) } : {}),
  };
}

export interface ClientErrorOptions {
  /** Where entries go; stdout (one JSON line, which Cloud Run ships to Cloud Logging) by default. */
  sink?: (entry: Record<string, unknown>) => void;
  limiter?: MemoryRateLimiter;
  now?: () => number;
}

const stdout = (entry: Record<string, unknown>) => {
  process.stdout.write(`${JSON.stringify({ ...entry, time: new Date().toISOString() })}\n`);
};

export function clientErrorRoutes(app: FastifyInstance, opts: ClientErrorOptions = {}) {
  const sink = opts.sink ?? stdout;
  const now = opts.now ?? Date.now;
  const limiter = opts.limiter ?? new MemoryRateLimiter(now);
  let dropped = 0;
  let lastNotice = 0;

  app.post("/v1/client-errors", { config: { public: true }, bodyLimit: clientErrorBodyLimit }, async (req, reply) => {
    const ip = visitorIp(req);
    const ok = clientErrorLimits.every((limit, i) => limiter.admit(`client-errors#${i}:${ip}`, limit));
    if (!ok) {
      // Silent to the sender; counted, and noted at most once a minute (no IP).
      dropped++;
      const t = now();
      if (t - lastNotice >= minute) {
        lastNotice = t;
        req.log.warn({ dropped }, "client error reports rate limited");
      }
      return reply.status(204).send();
    }
    sink(reportedErrorEntry(parseBody(clientErrorSchema, req.body)));
    return reply.status(204).send();
  });
}
