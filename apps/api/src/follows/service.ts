import {
  type FollowResult,
  followKey,
  followNotifySchema,
  followRequestSchema,
  notificationIdsSchema,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import { authorOf, checkNotMuted, clip, photoMax, text } from "../posts/author.js";
import { type Data, type DocStore, serverTime } from "../store.js";

const p = {
  follow: (uid: string, key: string) => `users/${uid}/follows/${key}`,
  request: (owner: string, uid: string) => `profiles/${owner}/followRequests/${uid}`,
  profile: (uid: string) => `profiles/${uid}`,
  team: (id: string) => `teams/${id}`,
  tournament: (id: string) => `tournaments/${id}`,
  groupTournament: (groupId: string, id: string) => `teams/${groupId}/groupTournaments/${id}`,
  notification: (uid: string, id: string) => `users/${uid}/notifications/${id}`,
};

/** Longest name on a follow (validString(d.name, 100)). */
const followNameMax = 100;
/** Longest name and username on a follow request (80 and 20). */
const requestNameMax = 80;
const usernameMax = 20;

const notFound = (what: string) => new ApiError("not_found", `That ${what} doesn't exist any more.`);
const photo = (v: unknown) => (typeof v === "string" && v && v.length <= photoMax ? v : null);

/** What a follow points at, with the name and photo the list shows. */
interface Target {
  type: "user" | "team" | "tournament";
  targetId: string;
  groupId?: string;
  name: string;
  photoUrl: string | null;
  /** A private player profile: following needs their OK. */
  isPrivate: boolean;
}

/**
 * Follows, follow requests and the notification feed. The Admin SDK skips
 * firestore.rules, so this checks what the follows, followRequests and
 * notifications rules check: a member follows only as themselves, never
 * themselves, and not while muted; a private profile needs a request the
 * owner accepts (the owner writes the follow and removes the request
 * together); the person followed may remove a follower; only the owner
 * marks or clears their notifications.
 */
export class FollowService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly now: () => number = Date.now,
  ) {}

  private async target(caller: Caller, type: Target["type"], id: string, groupId?: string): Promise<Target> {
    if (type === "user") {
      if (id === caller.uid) throw new ApiError("invalid_argument", "You can't follow yourself.");
      const [profile, user] = await Promise.all([this.store.get(p.profile(id)), this.users.lookup(id)]);
      if (!profile && !user) throw notFound("player");
      const username = text(profile?.username);
      const name = text(profile?.name) || text(user?.name) || (username ? `@${username}` : "Player");
      return {
        type,
        targetId: id,
        name: clip(name, followNameMax),
        photoUrl: photo(profile?.photoUrl) ?? photo(user?.photoUrl),
        isPrivate: profile?.private === true,
      };
    }
    if (type === "team") {
      const team = await this.store.get(p.team(id));
      if (!team) throw notFound("team");
      return {
        type,
        targetId: id,
        name: clip(text(team.name) || "Team", followNameMax),
        photoUrl: photo(team.photoUrl),
        isPrivate: false,
      };
    }
    if (!groupId) throw new ApiError("invalid_argument", "Say which group hosts the tournament.");
    const hosted = await this.store.get(p.tournament(id));
    const t = hosted?.hostId === groupId ? hosted : await this.store.get(p.groupTournament(groupId, id));
    if (!t) throw notFound("tournament");
    return {
      type,
      targetId: `${groupId}_${id}`,
      groupId,
      name: clip(text(t.name) || "Tournament", followNameMax),
      photoUrl: null,
      isPrivate: false,
    };
  }

  private followDoc(t: Target, notify: boolean, approved = false): Data {
    return {
      key: followKey(t.type, t.targetId),
      type: t.type,
      targetId: t.targetId,
      ...(t.groupId && { groupId: t.groupId }),
      name: t.name,
      ...(t.photoUrl && { photoUrl: t.photoUrl }),
      notify,
      ...(approved && { approved: true }),
      createdAt: serverTime,
    };
  }

  /** `PUT /v1/follows`: follows, or asks to follow a private profile. Again is a no-op. */
  async follow(caller: Caller, body: unknown): Promise<FollowResult> {
    const parsed = followRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const { type, targetId, groupId, notify } = parsed.data;
    await checkNotMuted(this.store, caller.uid, this.now());
    const t = await this.target(caller, type, targetId, groupId);
    const key = followKey(t.type, t.targetId);
    if (await this.store.get(p.follow(caller.uid, key))) return { key, status: "following" };
    if (t.isPrivate) {
      const me = await authorOf(this.store, this.users, caller);
      await this.store.transact(async (tx) => {
        if (await tx.get(p.request(t.targetId, caller.uid))) return;
        tx.create(p.request(t.targetId, caller.uid), {
          name: clip(me.name, requestNameMax),
          username: me.username ? clip(me.username, usernameMax) : null,
          photoUrl: me.photoUrl,
          createdAt: serverTime,
        });
      });
      return { key, status: "requested" };
    }
    await this.store.transact(async (tx) => {
      if (await tx.get(p.follow(caller.uid, key))) return;
      tx.create(p.follow(caller.uid, key), this.followDoc(t, notify));
    });
    return { key, status: "following" };
  }

  /** `DELETE /v1/follows/:key`: stops following. */
  async unfollow(caller: Caller, rawKey: unknown): Promise<void> {
    const key = docIdParam(rawKey);
    await this.store.transact(async (tx) => tx.delete(p.follow(caller.uid, key)));
  }

  /** `PATCH /v1/follows/:key`: post notifications on or off. */
  async setNotify(caller: Caller, rawKey: unknown, body: unknown): Promise<void> {
    const key = docIdParam(rawKey);
    const parsed = followNotifySchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    await this.store.transact(async (tx) => {
      if (!(await tx.get(p.follow(caller.uid, key)))) throw new ApiError("not_found", "You don't follow that.");
      tx.update(p.follow(caller.uid, key), { notify: parsed.data.notify });
    });
  }

  /** `DELETE /v1/follows/requests/:owner`: takes back a request to follow [owner]. */
  async cancelRequest(caller: Caller, rawOwner: unknown): Promise<void> {
    const owner = docIdParam(rawOwner);
    await this.store.transact(async (tx) => tx.delete(p.request(owner, caller.uid)));
  }

  /**
   * `POST /v1/me/follow-requests/:uid/accept`: lets [uid] follow the caller.
   * Writes their follow (approved) and removes the request together.
   */
  async acceptRequest(caller: Caller, rawUid: unknown): Promise<void> {
    const requester = docIdParam(rawUid);
    const [me, profile] = await Promise.all([
      authorOf(this.store, this.users, caller),
      this.store.get(p.profile(caller.uid)),
    ]);
    const t: Target = {
      type: "user",
      targetId: caller.uid,
      name: clip(text(profile?.name) || me.name, followNameMax),
      photoUrl: photo(profile?.photoUrl) ?? me.photoUrl,
      isPrivate: true,
    };
    const key = followKey("user", caller.uid);
    await this.store.transact(async (tx) => {
      if (!(await tx.get(p.request(caller.uid, requester)))) {
        throw new ApiError("not_found", "That request was taken back.");
      }
      if (!(await tx.get(p.follow(requester, key)))) tx.create(p.follow(requester, key), this.followDoc(t, false, true));
      tx.delete(p.request(caller.uid, requester));
    });
  }

  /** `DELETE /v1/me/follow-requests/:uid`: declines it. */
  async declineRequest(caller: Caller, rawUid: unknown): Promise<void> {
    const requester = docIdParam(rawUid);
    await this.store.transact(async (tx) => tx.delete(p.request(caller.uid, requester)));
  }

  /** `DELETE /v1/me/followers/:uid`: removes someone who follows the caller. */
  async removeFollower(caller: Caller, rawUid: unknown): Promise<void> {
    const follower = docIdParam(rawUid);
    await this.store.transact(async (tx) => tx.delete(p.follow(follower, followKey("user", caller.uid))));
  }

  /** `POST /v1/me/notifications/read`: marks the caller's notifications read. */
  async markRead(caller: Caller, body: unknown): Promise<void> {
    const ids = this.ids(body);
    await this.store.transact(async (tx) => {
      const found = await Promise.all(ids.map((id) => tx.get(p.notification(caller.uid, id))));
      ids.forEach((id, i) => {
        const n = found[i];
        if (n && n.read !== true) tx.update(p.notification(caller.uid, id), { read: true });
      });
    });
  }

  /** `POST /v1/me/notifications/delete`: clears them. */
  async clear(caller: Caller, body: unknown): Promise<void> {
    const ids = this.ids(body);
    await this.store.transact(async (tx) => {
      for (const id of ids) tx.delete(p.notification(caller.uid, id));
    });
  }

  private ids(body: unknown): string[] {
    const parsed = notificationIdsSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    return [...new Set(parsed.data.ids)];
  }
}
