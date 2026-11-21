import type { ReportTarget } from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError } from "../errors.js";
import type { HubService } from "../hub/service.js";
import type { TeamPostExtrasService } from "../hub/team_post_extras.js";
import type { ConversationService } from "../messages/service.js";
import type { PostEditor } from "../posts/editor.js";
import type { Data, DocStore } from "../store.js";
import { type ContentRemover, contentPath, ownerOf } from "./service.js";

/**
 * Removes reported content through each kind's own delete, so its photos,
 * pins and reposts go with it: a player's post, comment or message as its
 * author, team content as the team's owner. If that delete refuses (the
 * author left the conversation, the team has no owner), the document
 * itself is deleted.
 */
export class ServiceRemover implements ContentRemover {
  constructor(
    private readonly store: DocStore,
    private readonly editor: PostEditor,
    private readonly hub: HubService,
    private readonly teamPosts: TeamPostExtrasService,
    private readonly messages: ConversationService,
  ) {}

  async remove(t: ReportTarget, authorId: string, team: Data | null): Promise<void> {
    const author: Caller = { uid: authorId };
    const owner = team ? ownerOf(team) : null;
    const asOwner: Caller | null = owner ? { uid: owner } : null;
    try {
      switch (t.kind) {
        case "post":
          return await this.editor.delete(author, t.postId);
        case "comment":
          return await this.editor.deleteComment(author, t.postId, t.commentId);
        case "directMessage":
          return await this.messages.deleteMessage(author, t.conversationId, t.messageId);
        case "teamPost":
          if (asOwner) return await this.hub.deletePost(asOwner, t.teamId, t.postId);
          break;
        case "teamPostComment":
          if (asOwner) return await this.teamPosts.removeComment(asOwner, t.teamId, t.postId, t.commentId);
          break;
        case "teamMessage":
          if (asOwner) return await this.hub.deleteMessage(asOwner, t.teamId, t.roomId, t.messageId);
          break;
        case "user":
          return;
      }
    } catch (e) {
      if (!(e instanceof ApiError)) throw e;
    }
    await this.store.transact(async (tx) => tx.delete(contentPath(t)));
  }
}
