import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { PostService } from "./service.js";

type Id = { Params: { id: string } };

/** Liking and reposting players' posts, as the signed-in caller. */
export function postRoutes(app: FastifyInstance, posts: PostService) {
  app.get<{ Querystring: { ids?: string } }>("/v1/posts/state", async (req, reply) => {
    const states = await posts.states(requireCaller(req), req.query.ids);
    return reply.header("cache-control", "private, no-store").send(states);
  });
  app.put<Id>("/v1/posts/:id/like", async (req) => posts.setLiked(requireCaller(req), req.params.id, true));
  app.delete<Id>("/v1/posts/:id/like", async (req) => posts.setLiked(requireCaller(req), req.params.id, false));
  app.put<Id>("/v1/posts/:id/repost", async (req) => posts.repost(requireCaller(req), req.params.id, req.body));
  app.delete<Id>("/v1/posts/:id/repost", async (req) => posts.undoRepost(requireCaller(req), req.params.id));
}
