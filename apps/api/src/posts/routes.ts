import type { FastifyInstance } from "fastify";
import { requireCaller } from "../auth.js";
import type { PostEditor } from "./editor.js";
import type { PostService } from "./service.js";

type Id = { Params: { id: string } };
type CommentId = { Params: { id: string; commentId: string } };

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

/** Writing posts and comments, as the signed-in caller. */
export function postEditorRoutes(app: FastifyInstance, editor: PostEditor) {
  app.post("/v1/posts", async (req, reply) => reply.code(201).send(await editor.create(requireCaller(req), req.body)));
  app.patch<Id>("/v1/posts/:id", async (req) => editor.edit(requireCaller(req), req.params.id, req.body));
  app.delete<Id>("/v1/posts/:id", async (req, reply) => {
    await editor.delete(requireCaller(req), req.params.id);
    return reply.code(204).send();
  });
  app.post<Id>("/v1/posts/:id/comments", async (req, reply) =>
    reply.code(201).send(await editor.addComment(requireCaller(req), req.params.id, req.body)),
  );
  app.patch<CommentId>("/v1/posts/:id/comments/:commentId", async (req, reply) => {
    await editor.editComment(requireCaller(req), req.params.id, req.params.commentId, req.body);
    return reply.code(204).send();
  });
  app.delete<CommentId>("/v1/posts/:id/comments/:commentId", async (req, reply) => {
    await editor.deleteComment(requireCaller(req), req.params.id, req.params.commentId);
    return reply.code(204).send();
  });
  app.put<CommentId>("/v1/posts/:id/comments/:commentId/like", async (req) =>
    editor.setCommentLiked(requireCaller(req), req.params.id, req.params.commentId, true),
  );
  app.delete<CommentId>("/v1/posts/:id/comments/:commentId/like", async (req) =>
    editor.setCommentLiked(requireCaller(req), req.params.id, req.params.commentId, false),
  );
}
