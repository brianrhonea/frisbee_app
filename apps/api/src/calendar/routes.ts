import type { FastifyInstance, FastifyRequest } from "fastify";
import { requireCaller } from "../auth.js";
import { ApiError } from "../errors.js";
import type { RateLimiter } from "../limits/limiter.js";
import type { Limit } from "../limits/model.js";
import { feedHash, type CalendarService } from "./service.js";

export interface CalendarOptions {
  /** Counts subscription-feed fetches per link; the feed is off without one. */
  limiter?: RateLimiter;
  /** The API's public address for feed links (PUBLIC_API_URL); else the request's own. */
  publicUrl?: string;
}

/**
 * Per link, not per IP: Google Calendar fetches every subscription from the
 * same few addresses. Calendar apps refresh every hour or so.
 */
const feedLimit: Limit = { max: 30, windowMs: 10 * 60_000 };

/** Calendars, invites, events and the subscription feed (CalendarService). */
export function calendarRoutes(app: FastifyInstance, calendar: CalendarService, opts: CalendarOptions = {}) {
  // Per person: never stored by a shared cache.
  const noStore = "private, no-store";
  const base = (req: FastifyRequest) => opts.publicUrl || `${req.protocol}://${req.host}`;
  type Id = { Params: { id: string } };
  type IdUid = { Params: { id: string; uid: string } };
  type IdEvent = { Params: { id: string; eventId: string } };

  app.get("/v1/me/calendars", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.list(requireCaller(req))),
  );
  app.post("/v1/me/calendars", async (req, reply) =>
    reply.status(201).send(await calendar.create(requireCaller(req), req.body)),
  );
  app.patch<Id>("/v1/calendars/:id", async (req, reply) => {
    await calendar.rename(requireCaller(req), req.params.id, req.body);
    return reply.status(204).send();
  });
  app.delete<Id>("/v1/calendars/:id", async (req, reply) => {
    await calendar.remove(requireCaller(req), req.params.id);
    return reply.status(204).send();
  });

  app.post<Id>("/v1/calendars/:id/invites", async (req, reply) => {
    await calendar.invite(requireCaller(req), req.params.id, req.body);
    return reply.status(204).send();
  });
  app.delete<IdUid>("/v1/calendars/:id/invites/:uid", async (req, reply) => {
    await calendar.cancelInvite(requireCaller(req), req.params.id, req.params.uid);
    return reply.status(204).send();
  });
  app.patch<IdUid>("/v1/calendars/:id/members/:uid", async (req, reply) => {
    await calendar.setRole(requireCaller(req), req.params.id, req.params.uid, req.body);
    return reply.status(204).send();
  });
  app.delete<IdUid>("/v1/calendars/:id/members/:uid", async (req, reply) => {
    await calendar.removeMember(requireCaller(req), req.params.id, req.params.uid);
    return reply.status(204).send();
  });

  app.get("/v1/me/calendar-invites", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.invites(requireCaller(req))),
  );
  app.post<Id>("/v1/me/calendar-invites/:id/accept", async (req, reply) => {
    await calendar.accept(requireCaller(req), req.params.id);
    return reply.status(204).send();
  });
  app.post<Id>("/v1/me/calendar-invites/:id/decline", async (req, reply) => {
    await calendar.decline(requireCaller(req), req.params.id);
    return reply.status(204).send();
  });

  app.get<{ Querystring: { from?: string; to?: string } }>("/v1/me/calendar-events", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.events(requireCaller(req), req.query.from, req.query.to)),
  );
  app.post<Id>("/v1/calendars/:id/events", async (req, reply) =>
    reply.status(201).send(await calendar.addEvent(requireCaller(req), req.params.id, req.body)),
  );
  app.get<IdEvent>("/v1/calendars/:id/events/:eventId", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.event(requireCaller(req), req.params.id, req.params.eventId)),
  );
  app.patch<IdEvent>("/v1/calendars/:id/events/:eventId", async (req, reply) => {
    await calendar.updateEvent(requireCaller(req), req.params.id, req.params.eventId, req.body);
    return reply.status(204).send();
  });
  app.delete<IdEvent>("/v1/calendars/:id/events/:eventId", async (req, reply) => {
    await calendar.removeEvent(requireCaller(req), req.params.id, req.params.eventId);
    return reply.status(204).send();
  });

  app.get("/v1/me/calendar-feed", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.feed(requireCaller(req), base(req))),
  );
  app.post("/v1/me/calendar-feed", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.resetFeed(requireCaller(req), base(req))),
  );
  app.delete("/v1/me/calendar-feed", async (req, reply) => {
    await calendar.stopFeed(requireCaller(req));
    return reply.status(204).send();
  });

  const limiter = opts.limiter;
  if (!limiter) return;
  // Calendar apps send no ID token: the link is the key. Its path holds
  // the token, so this route logs only warnings (Fastify logs every URL).
  app.get<{ Params: { file: string } }>(
    "/v1/ical/:file",
    { config: { public: true }, logLevel: "warn" },
    async (req, reply) => {
      const token = req.params.file.replace(/\.ics$/, "");
      const gone = () => new ApiError("not_found", "This calendar link was reset or turned off.");
      if (!/^[A-Za-z0-9_-]{24,64}$/.test(token)) throw gone();
      if (!(await limiter.admit(`ical_${feedHash(token).slice(0, 32)}`, feedLimit))) {
        throw new ApiError("resource_exhausted", "Too many requests. Try again in a few minutes.");
      }
      const ics = await calendar.ical(token);
      if (ics === null) throw gone();
      return reply
        .header("cache-control", "private, no-store")
        .header("content-type", "text/calendar; charset=utf-8")
        .header("content-disposition", 'inline; filename="stall10.ics"')
        .send(ics);
    },
  );
}
