import type { FastifyInstance, FastifyRequest } from "fastify";
import { requireCaller } from "../auth.js";
import { noRevalidate, type Revalidate, webTags } from "../web/revalidate.js";
import type { PostEditor } from "./editor.js";
import type { PostService } from "./service.js";

type Id = { Params: { id: string } };
type CommentId = { Params: { id: string; commentId: string } };

/** Liking and reposting players' posts, as the signed-in caller. */
export function postRoutes(app: FastifyInstance, posts: PostService, revalidate: Revalidate = noRevalidate) {
  app.get<{ Querystring: { ids?: string } }>("/v1/posts/state", async (req, reply) => {
    const states = await posts.states(requireCaller(req), req.query.ids);
    return reply.header("cache-control", "private, no-store").send(states);
  });
  app.put<Id>("/v1/posts/:id/like", async (req) => posts.setLiked(requireCaller(req), req.params.id, true));
  app.delete<Id>("/v1/posts/:id/like", async (req) => posts.setLiked(requireCaller(req), req.params.id, false));
  // A repost is a post of the reposter's: their page and the feed change.
  app.put<Id>("/v1/posts/:id/repost", async (req) => {
    const caller = requireCaller(req);
    const result = await posts.repost(caller, req.params.id, req.body);
    await revalidate([webTags.player(caller.uid), webTags.feed], req.log);
    return result;
  });
  app.delete<Id>("/v1/posts/:id/repost", async (req) => {
    const caller = requireCaller(req);
    const result = await posts.undoRepost(caller, req.params.id);
    await revalidate([webTags.player(caller.uid), webTags.feed, webTags.posts], req.log);
    return result;
  });

}

/** Writing posts and comments, as the signed-in caller. */
export function postEditorRoutes(app: FastifyInstance, editor: PostEditor, revalidate: Revalidate = noRevalidate) {
  // Only a post's author writes it, so the caller's page is the one that changed.
  const changed = (req: FastifyRequest, uid: string, postId?: string) =>
    revalidate([webTags.player(uid), webTags.feed, ...(postId ? [webTags.post(postId)] : [])], req.log);

  app.post("/v1/posts", async (req, reply) => {
    const caller = requireCaller(req);
    const result = await editor.create(caller, req.body);
    await changed(req, caller.uid);
    return reply.code(201).send(result);
  });
  app.patch<Id>("/v1/posts/:id", async (req) => {
    const caller = requireCaller(req);
    const result = await editor.edit(caller, req.params.id, req.body);
    await changed(req, caller.uid, req.params.id);
    return result;
  });
  app.delete<Id>("/v1/posts/:id", async (req, reply) => {
    const caller = requireCaller(req);
    await editor.delete(caller, req.params.id);
    await changed(req, caller.uid, req.params.id);
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
