import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { CalendarService } from "./service.js";

/** The caller's personal schedule and calendar sharing (CalendarService). */
export function calendarRoutes(app: FastifyInstance, calendar: CalendarService) {
  // Per person: never stored by a shared cache.
  const noStore = "private, no-store";

  app.get("/v1/me/calendar/viewers", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.viewers(requireCaller(req))),
  );
  app.put("/v1/me/calendar/viewers", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.setViewers(requireCaller(req), req.body)),
  );
  app.get<{ Querystring: { from?: string; to?: string } }>("/v1/me/calendar/shared", async (req, reply) =>
    reply.header("cache-control", noStore).send(await calendar.shared(requireCaller(req), req.query.from, req.query.to)),
  );

  app.post("/v1/me/events", async (req, reply) =>
    reply.status(201).send(await calendar.create(requireCaller(req), req.body)),
  );
  app.patch<{ Params: { id: string } }>("/v1/me/events/:id", async (req, reply) => {
    await calendar.update(requireCaller(req), req.params.id, req.body);
    return reply.status(204).send();
  });
  app.delete<{ Params: { id: string } }>("/v1/me/events/:id", async (req, reply) => {
    await calendar.remove(requireCaller(req), req.params.id);
    return reply.status(204).send();
  });
}
