import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { requireCaller } from "../auth.js";
import type { FollowService } from "./service.js";

type Key = { Params: { key: string } };
type Uid = { Params: { uid: string } };

/** 204 once [fn] has run. */
const done =
  <R extends FastifyRequest>(fn: (req: R) => Promise<void>) =>
  async (req: R, reply: FastifyReply) => {
    await fn(req);
    return reply.code(204).send();
  };

/** Follows, follow requests and notifications, as the signed-in caller. */
export function followRoutes(app: FastifyInstance, follows: FollowService) {
  app.put("/v1/follows", async (req) => follows.follow(requireCaller(req), req.body));
  app.delete<{ Params: { owner: string } }>(
    "/v1/follows/requests/:owner",
    done((req) => follows.cancelRequest(requireCaller(req), req.params.owner)),
  );
  app.delete<Key>(
    "/v1/follows/:key",
    done((req) => follows.unfollow(requireCaller(req), req.params.key)),
  );
  app.patch<Key>(
    "/v1/follows/:key",
    done((req) => follows.setNotify(requireCaller(req), req.params.key, req.body)),
  );
  app.post<Uid>(
    "/v1/me/follow-requests/:uid/accept",
    done((req) => follows.acceptRequest(requireCaller(req), req.params.uid)),
  );
  app.delete<Uid>(
    "/v1/me/follow-requests/:uid",
    done((req) => follows.declineRequest(requireCaller(req), req.params.uid)),
  );
  app.delete<Uid>(
    "/v1/me/followers/:uid",
    done((req) => follows.removeFollower(requireCaller(req), req.params.uid)),
  );
  app.post(
    "/v1/me/notifications/read",
    done((req) => follows.markRead(requireCaller(req), req.body)),
  );
  app.post(
    "/v1/me/notifications/delete",
    done((req) => follows.clear(requireCaller(req), req.body)),
  );
}
