// CORS for the website (apps/web on Vercel) and local development. The API
// authenticates with a Bearer token, never cookies, so CORS only decides
// which sites' scripts may read its answers; credentials stay off.
import { appCheckHeader } from "@stall10/shared";
import type { FastifyInstance } from "fastify";

/** Used when CORS_ORIGINS isn't set: the Next.js dev server. */
export const defaultCorsOrigins = ["http://localhost:3000"];

const allowMethods = "GET, POST, PUT, PATCH, DELETE";
const allowHeaders = ["authorization", "content-type", appCheckHeader].join(", ");

/**
 * Parses CORS_ORIGINS: comma-separated origins such as
 * `https://stall10.app,https://stall10-*.vercel.app`. A `*` matches one or
 * more letters, digits or hyphens within a host label or port, so a
 * pattern can't reach into another domain.
 */
export function parseCorsOrigins(spec: string | undefined): string[] {
  if (spec === undefined) return defaultCorsOrigins;
  return spec
    .split(",")
    .map((o) => o.trim().replace(/\/+$/, ""))
    .filter(Boolean);
}

/** A predicate for the allow-list from [parseCorsOrigins]. */
export function originMatcher(origins: string[]): (origin: string) => boolean {
  const exact = new Set(origins.filter((o) => !o.includes("*")).map((o) => o.toLowerCase()));
  const patterns = origins
    .filter((o) => o.includes("*"))
    .map((o) => new RegExp(`^${o.toLowerCase().split("*").map(escape).join("[a-z0-9-]+")}$`));
  return (origin) => {
    const o = origin.toLowerCase();
    return exact.has(o) || patterns.some((p) => p.test(o));
  };
}

function escape(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Adds CORS headers for allowed origins and answers preflights. Register it
 * before the auth hook: a preflight carries no token or App Check header,
 * and answering it here ends the request before auth runs.
 */
export function registerCors(app: FastifyInstance, origins: string[]) {
  const allowed = originMatcher(origins);
  app.addHook("onRequest", async (req, reply) => {
    const origin = req.headers.origin;
    const ok = typeof origin === "string" && allowed(origin);
    reply.header("vary", "Origin");
    if (ok) {
      reply.header("access-control-allow-origin", origin);
      // Lets the website read which API version answered.
      reply.header("access-control-expose-headers", "x-stall10-api-version");
    }

    const preflight = req.method === "OPTIONS" && req.headers["access-control-request-method"] !== undefined;
    if (!preflight) return;
    if (ok) {
      reply.header("access-control-allow-methods", allowMethods);
      reply.header("access-control-allow-headers", allowHeaders);
      reply.header("access-control-max-age", "600");
    }
    // A disallowed origin gets no CORS headers, so the browser blocks it.
    return reply.status(204).send();
  });
}
