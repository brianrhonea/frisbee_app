import { randomBytes } from "node:crypto";
import {
  addGroupMembersRequestSchema,
  answerRequestSchema,
  archiveRequestSchema,
  typingRequestSchema,
  chatReactionChoices,
  chatReactionRequestSchema,
  createGroupRequestSchema,
  directConversationId,
  type GroupAddedResult,
  groupSizeMax,
  messagePreview,
  type OpenConversationResult,
  openConversationRequestSchema,
  renameGroupRequestSchema,
  type SendChatMessageResult,
  sendChatMessageRequestSchema,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { deleteFilesUnder, filesOf, uploadedFiles } from "../hub/uploads.js";
import { docIdParam } from "../ids.js";
import type { MediaStorage } from "../media/storage.js";
import { authorOf, checkNotMuted } from "../posts/author.js";
import { type Data, type DocStore, deleteField, serverTime } from "../store.js";
import { clip, mapOf, strings } from "../teams/access.js";

const p = {
  conv: (id: string) => `conversations/${id}`,
  message: (id: string, m: string) => `conversations/${id}/messages/${m}`,
  reads: (uid: string, id: string) => `users/${uid}/dmReads/${id}`,
  user: (uid: string) => `users/${uid}`,
  profile: (uid: string) => `profiles/${uid}`,
  follow: (follower: string, followed: string) => `users/${follower}/follows/user_${followed}`,
};

const groupId = /^g-[A-Za-z0-9]+$/;
const isGroupId = (id: string) => groupId.test(id);
const noConversation = () => new ApiError("not_found", "This conversation doesn't exist.");
const noMessage = () => new ApiError("not_found", "This message was deleted.");

/** A conversation id from the URL: a group's `g-…`, or two different uids joined by "_", sorted. */
function convIdParam(v: unknown): string {
  const id = docIdParam(v);
  if (isGroupId(id)) return id;
  const parts = id.split("_");
  if (parts.length !== 2 || !parts[0] || !parts[1] || parts[0] >= parts[1]) throw noConversation();
  return id;
}

/** inConversation(): in a group's participants, or one of a direct conversation's two uids. */
function inConversation(id: string, conv: Data | null, uid: string): boolean {
  if (isGroupId(id)) return !!conv && strings(conv.participants).includes(uid);
  return id.split("_").includes(uid);
}

/** awaitingMe(): a request still waiting on [uid]. */
const awaiting = (conv: Data, uid: string) => (conv.status ?? "accepted") === "request" && conv.requestedOf === uid;

const without = (m: unknown, key: string): Data => {
  const out = { ...mapOf(m) };
  delete out[key];
  return out;
};

const policyOf = (user: Data | null) => {
  const v = user?.messagePolicy;
  return v === "followers" || v === "following" || v === "nobody" ? v : "everyone";
};

/**
 * Direct and group conversations from the website. The Admin SDK skips
 * firestore.rules, so each method checks what the conversations rules
 * check: who may start a conversation (their message policy and who
 * follows whom), who's in it, who may add or remove people, and that
 * whoever a request waits on neither posts nor sends read receipts until
 * they accept it.
 */
export class ConversationService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly media: MediaStorage | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  private async name(caller: Caller) {
    return (await authorOf(this.store, this.users, caller)).name;
  }

  /** A conversation the caller is in, or a 404 (outsiders learn nothing). */
  private async mine(caller: Caller, rawId: unknown): Promise<{ id: string; conv: Data }> {
    const id = convIdParam(rawId);
    const conv = await this.store.get(p.conv(id));
    if (!conv || !inConversation(id, conv, caller.uid)) throw noConversation();
    return { id, conv };
  }

  /** `POST /v1/conversations`: allowedStart() decides between their inbox, a request, or not at all. */
  async open(caller: Caller, body: unknown): Promise<OpenConversationResult> {
    const other = docIdParam(parseBody(openConversationRequestSchema, body).with);
    if (other === caller.uid) throw new ApiError("invalid_argument", "You can't message yourself.");
    const id = directConversationId(caller.uid, other);
    const existing = await this.store.get(p.conv(id));
    if (existing) return { id, status: (existing.status as OpenConversationResult["status"]) ?? "accepted" };
    const [profile, user, theyFollowMe, iFollowThem] = await Promise.all([
      this.store.get(p.profile(other)),
      this.store.get(p.user(other)),
      this.store.get(p.follow(other, caller.uid)),
      this.store.get(p.follow(caller.uid, other)),
    ]);
    if (!profile) throw new ApiError("not_found", "That player doesn't exist.");
    const policy = policyOf(user);
    const status: "accepted" | "request" | null =
      policy !== "nobody" && theyFollowMe
        ? "accepted"
        : policy === "everyone" || (policy === "followers" && iFollowThem)
          ? "request"
          : null;
    const theirName = clip(typeof profile.name === "string" && profile.name ? profile.name : "Player", 80);
    if (!status) throw new ApiError("permission_denied", `${theirName} doesn't take messages from you.`);
    await checkNotMuted(this.store, caller.uid, this.now());
    const me = await this.name(caller);
    return this.store.transact(async (tx) => {
      const now = await tx.get(p.conv(id));
      if (now) return { id, status: (now.status as OpenConversationResult["status"]) ?? "accepted" };
      tx.create(p.conv(id), {
        participants: id.split("_"),
        names: { [caller.uid]: me, [other]: theirName },
        lastMessage: "",
        lastMessageAt: null,
        lastSenderId: "",
        readAt: {},
        createdAt: serverTime,
        status,
        ...(status === "request" && { requestedOf: other }),
      });
      return { id, status };
    });
  }

  /** `POST /v1/conversations/groups`: a group that starts with just its creator, then each member in turn. */
  async createGroup(caller: Caller, body: unknown): Promise<GroupAddedResult> {
    const req = parseBody(createGroupRequestSchema, body);
    await checkNotMuted(this.store, caller.uid, this.now());
    const id = `g-${randomBytes(15).toString("base64").replace(/[^A-Za-z0-9]/g, "").slice(0, 20) || "x"}`;
    const me = await this.name(caller);
    await this.store.transact(async (tx) => {
      tx.create(p.conv(id), {
        kind: "group",
        name: req.name,
        createdBy: caller.uid,
        participants: [caller.uid],
        names: { [caller.uid]: me },
        lastMessage: "",
        lastMessageAt: null,
        lastSenderId: "",
        readAt: {},
        createdAt: serverTime,
      });
    });
    return { id, notAdded: await this.addEach(caller, id, req.members) };
  }

  /** `POST /v1/conversations/:id/members`. */
  async addMembers(caller: Caller, rawId: unknown, body: unknown): Promise<GroupAddedResult> {
    const { id, conv } = await this.mine(caller, rawId);
    if (conv.kind !== "group") throw new ApiError("failed_precondition", "Only group conversations take more people.");
    return { id, notAdded: await this.addEach(caller, id, parseBody(addGroupMembersRequestSchema, body).members) };
  }

  /** addsMember(): one at a time, at the end, each following the adder and taking messages. */
  private async addEach(caller: Caller, id: string, members: string[]): Promise<string[]> {
    const notAdded: string[] = [];
    for (const raw of [...new Set(members)]) {
      const uid = docIdParam(raw);
      const [profile, user, follows] = await Promise.all([
        this.store.get(p.profile(uid)),
        this.store.get(p.user(uid)),
        this.store.get(p.follow(uid, caller.uid)),
      ]);
      const name = clip(typeof profile?.name === "string" && profile.name ? profile.name : "Player", 80);
      if (!profile || !follows || policyOf(user) === "nobody") {
        notAdded.push(name);
        continue;
      }
      const added = await this.store.transact(async (tx) => {
        const conv = await tx.get(p.conv(id));
        const now = strings(conv?.participants);
        if (!conv || !now.includes(caller.uid)) throw noConversation();
        if (now.includes(uid)) return true;
        if (now.length >= groupSizeMax) return false;
        tx.update(p.conv(id), { participants: [...now, uid], names: { ...mapOf(conv.names), [uid]: name } });
        return true;
      });
      if (!added) notAdded.push(name);
    }
    return notAdded;
  }

  /** `DELETE /v1/conversations/:id/members/:uid`: leave, or (its creator) take someone out. */
  async removeMember(caller: Caller, rawId: unknown, rawUid: unknown): Promise<void> {
    const target = docIdParam(rawUid);
    const { id } = await this.mine(caller, rawId);
    await this.store.transact(async (tx) => {
      const conv = await tx.get(p.conv(id));
      if (!conv || !inConversation(id, conv, caller.uid)) throw noConversation();
      if (conv.kind !== "group") throw new ApiError("failed_precondition", "Only group conversations have members to remove.");
      if (target !== caller.uid && conv.createdBy !== caller.uid) {
        throw new ApiError("permission_denied", "Only whoever started the group takes people out.");
      }
      const now = strings(conv.participants);
      if (!now.includes(target)) return;
      tx.update(p.conv(id), { participants: now.filter((u) => u !== target) });
    });
  }

  /** `PATCH /v1/conversations/:id`: anyone in a group renames it. */
  async rename(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const { name } = parseBody(renameGroupRequestSchema, body);
    const { id, conv } = await this.mine(caller, rawId);
    if (conv.kind !== "group") throw new ApiError("failed_precondition", "Only group conversations have a name.");
    await this.store.transact(async (tx) => {
      const now = await tx.get(p.conv(id));
      if (!now || !inConversation(id, now, caller.uid)) throw noConversation();
      tx.update(p.conv(id), { name });
    });
  }

  /** `POST /v1/conversations/:id/messages`: the message and the inbox preview, together. */
  async send(caller: Caller, rawId: unknown, body: unknown): Promise<SendChatMessageResult> {
    const req = parseBody(sendChatMessageRequestSchema, body);
    const { id, conv } = await this.mine(caller, rawId);
    if (awaiting(conv, caller.uid)) throw new ApiError("failed_precondition", "Accept the request to reply.");
    await checkNotMuted(this.store, caller.uid, this.now());
    const messageId = req.id ?? this.store.newId(`conversations/${id}/messages`);
    const attachments = await uploadedFiles(this.store, caller, req.uploadIds, {
      purpose: "chat",
      targetId: `conversations/${id}`,
      itemId: messageId,
    });
    const text = req.text.trim();
    if (!text && attachments.length === 0) throw new ApiError("invalid_argument", "Write a message or attach a file.");
    let replyTo: Data | null = null;
    if (req.replyTo) {
      const quoted = await this.store.get(p.message(id, docIdParam(req.replyTo)));
      if (!quoted) throw new ApiError("not_found", "The message you're answering was deleted.");
      replyTo = {
        id: req.replyTo,
        authorId: clip(String(quoted.authorId ?? ""), 128),
        authorName: clip(String(quoted.authorName ?? ""), 80),
        text: clip(String(quoted.text ?? ""), 200),
      };
    }
    const me = await this.name(caller);
    const preview = clip(
      messagePreview(text, attachments.length, {
        image: attachments.length > 0 && attachments.every((a) => a.contentType.startsWith("image/")),
        video: attachments.length > 0 && attachments.every((a) => a.contentType.startsWith("video/")),
      }),
      200,
    );
    await this.store.transact(async (tx) => {
      const [now, existing] = await Promise.all([tx.get(p.conv(id)), tx.get(p.message(id, messageId))]);
      if (!now || !inConversation(id, now, caller.uid)) throw noConversation();
      if (awaiting(now, caller.uid)) throw new ApiError("failed_precondition", "Accept the request to reply.");
      if (existing) throw new ApiError("already_exists", "That message was already sent.");
      tx.create(p.message(id, messageId), {
        authorId: caller.uid,
        authorName: me,
        text,
        attachments,
        createdAt: serverTime,
        ...(replyTo && { replyTo }),
      });
      tx.update(p.conv(id), {
        lastMessage: preview,
        lastMessageAt: serverTime,
        lastSenderId: caller.uid,
        readAt: { ...mapOf(now.readAt), [caller.uid]: serverTime },
        names: { ...mapOf(now.names), [caller.uid]: me },
      });
    });
    return { id: messageId };
  }

  /** reactsOnlyAsMe(): anyone in the conversation sets or clears their own emoji. */
  async react(caller: Caller, rawId: unknown, rawMessage: unknown, body: unknown): Promise<void> {
    const { emoji } = parseBody(chatReactionRequestSchema, body);
    if (emoji !== null && !(chatReactionChoices as readonly string[]).includes(emoji)) {
      throw new ApiError("invalid_argument", "Pick one of the reactions.");
    }
    const messageId = docIdParam(rawMessage);
    const { id } = await this.mine(caller, rawId);
    await this.store.transact(async (tx) => {
      const [conv, message] = await Promise.all([tx.get(p.conv(id)), tx.get(p.message(id, messageId))]);
      if (!conv || !inConversation(id, conv, caller.uid)) throw noConversation();
      if (!message) throw noMessage();
      const reactions = emoji ? { ...mapOf(message.reactions), [caller.uid]: emoji } : without(message.reactions, caller.uid);
      tx.update(p.message(id, messageId), { reactions });
    });
  }

  /** Authors delete their own messages. */
  async deleteMessage(caller: Caller, rawId: unknown, rawMessage: unknown): Promise<void> {
    const messageId = docIdParam(rawMessage);
    const { id } = await this.mine(caller, rawId);
    const message = await this.store.transact(async (tx) => {
      const message = await tx.get(p.message(id, messageId));
      if (!message) return null;
      if (message.authorId !== caller.uid) throw new ApiError("permission_denied", "You can only delete your own messages.");
      tx.delete(p.message(id, messageId));
      return message;
    });
    if (message) await deleteFilesUnder(this.media, `conversations/${id}/${caller.uid}/${messageId}`, filesOf(message.attachments));
  }

  /** `POST /v1/conversations/:id/read`: their own read time, and the shared receipt unless they turned receipts off. */
  async markRead(caller: Caller, rawId: unknown): Promise<void> {
    const { id } = await this.mine(caller, rawId);
    const receipts = (await this.store.get(p.user(caller.uid)))?.readReceipts !== false;
    await this.store.transact(async (tx) => {
      const conv = await tx.get(p.conv(id));
      if (!conv || !inConversation(id, conv, caller.uid)) throw noConversation();
      tx.merge(p.reads(caller.uid, id), { readAt: serverTime });
      if (receipts && !awaiting(conv, caller.uid)) {
        tx.update(p.conv(id), { readAt: { ...mapOf(conv.readAt), [caller.uid]: serverTime } });
      }
    });
  }

  /** `PUT /v1/conversations/:id/request`: whoever a request waits on accepts or declines it. */
  async answer(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const { accept } = parseBody(answerRequestSchema, body);
    const { id } = await this.mine(caller, rawId);
    await this.store.transact(async (tx) => {
      const conv = await tx.get(p.conv(id));
      if (!conv || !inConversation(id, conv, caller.uid)) throw noConversation();
      if (!awaiting(conv, caller.uid)) throw new ApiError("failed_precondition", "There's no request waiting on you here.");
      tx.update(p.conv(id), { status: accept ? "accepted" : "declined" });
      // Declining also clears it for them, so nothing lingers.
      if (!accept) tx.merge(p.reads(caller.uid, id), { clearedAt: serverTime });
    });
  }

  /** `PUT /v1/conversations/:id/typing`: marks or clears the caller's typing (the typing rule). */
  async setTyping(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const { typing } = parseBody(typingRequestSchema, body);
    const { id } = await this.mine(caller, rawId);
    await this.store.transact(async (tx) => {
      if (typing) tx.set(`conversations/${id}/typing/${caller.uid}`, { at: serverTime });
      else tx.delete(`conversations/${id}/typing/${caller.uid}`);
    });
  }

  /** `PUT /v1/conversations/:id/archive`. */
  async archive(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const { archived } = parseBody(archiveRequestSchema, body);
    const { id } = await this.mine(caller, rawId);
    await this.store.transact(async (tx) => {
      tx.merge(p.reads(caller.uid, id), { archivedAt: archived ? serverTime : deleteField });
    });
  }

  /** `POST /v1/conversations/:id/clear`: hides what's there so far, for them only. */
  async clear(caller: Caller, rawId: unknown): Promise<void> {
    const { id } = await this.mine(caller, rawId);
    await this.store.transact(async (tx) => {
      tx.merge(p.reads(caller.uid, id), { clearedAt: serverTime, archivedAt: deleteField });
    });
  }
}
