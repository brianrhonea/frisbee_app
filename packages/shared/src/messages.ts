// Direct messages (ARCHITECTURE.md §10, item 10). Ports of MessagePolicy
// (apps/mobile/lib/domain/models/direct_message.dart) and the
// conversations rules in firestore.rules.
import { z } from "zod";

/**
 * Who may start a conversation with someone (users/{uid}.messagePolicy).
 * People they follow always may (except with "nobody"); others land in
 * Message requests where the policy allows them at all.
 */
export const messagePolicies = ["everyone", "followers", "following", "nobody"] as const;
export type MessagePolicy = (typeof messagePolicies)[number];

export const messagePolicyLabels: Record<MessagePolicy, { label: string; detail: string }> = {
  everyone: { label: "Everyone", detail: "People you don't follow go to Message requests." },
  followers: {
    label: "Followers and people you follow",
    detail: "Followers you don't follow back go to Message requests.",
  },
  following: { label: "Only people you follow", detail: "Nobody else can message you." },
  nobody: { label: "No one", detail: "Conversations you already have carry on." },
};

/** `PUT /v1/me/message-policy`. */
export const messagePolicyRequestSchema = z.strictObject({ messagePolicy: z.enum(messagePolicies) });

/** `GET /v1/me/message-policy`. */
export interface MessagePolicyResponse {
  messagePolicy: MessagePolicy;
}

// Conversations from the website (ARCHITECTURE.md §10 item 10): ports of
// the conversations rules. Reads stay Firestore listeners.

/** Most people in a group conversation (Conversation.maxGroupSize). */
export const groupSizeMax = 10;
/** Longest group name (validString(name, 60)). */
export const groupNameMax = 60;

/** A direct conversation's id: the two uids, sorted, joined by "_" (Conversation.idFor). */
export const directConversationId = (a: string, b: string) => (a < b ? `${a}_${b}` : `${b}_${a}`);

/** `POST /v1/conversations`: open (or start) a direct conversation with [with]. */
export const openConversationRequestSchema = z.strictObject({ with: z.string().min(1).max(128) });

/** After opening: "accepted" goes to their inbox; "request" waits in their Message requests. */
export interface OpenConversationResult {
  id: string;
  status: "accepted" | "request" | "declined";
}

/** `POST /v1/conversations/groups`. */
export const createGroupRequestSchema = z.strictObject({
  name: z.string().trim().min(1, "Name the group.").max(groupNameMax, `Keep the name under ${groupNameMax} characters.`),
  members: z.array(z.string().min(1).max(128)).max(groupSizeMax - 1).default([]),
});

/** `POST /v1/conversations/:id/members`. */
export const addGroupMembersRequestSchema = z.strictObject({
  members: z.array(z.string().min(1).max(128)).min(1).max(groupSizeMax - 1),
});

/** After creating a group or adding people: who couldn't be added (they don't follow you, or the group is full). */
export interface GroupAddedResult {
  id: string;
  notAdded: string[];
}

/** `PATCH /v1/conversations/:id`: rename a group. */
export const renameGroupRequestSchema = z.strictObject({
  name: z.string().trim().min(1, "Name the group.").max(groupNameMax, `Keep the name under ${groupNameMax} characters.`),
});

/** `PUT /v1/conversations/:id/request`: whoever a request waits on answers it. */
export const answerRequestSchema = z.strictObject({ accept: z.boolean() });

/** `PUT /v1/conversations/:id/archive`. */
export const archiveRequestSchema = z.strictObject({ archived: z.boolean() });

/** The inbox's one-line preview of a message (messagePreview in the app). */
export function messagePreview(text: string, attachments: number, kind: { image?: boolean; video?: boolean } = {}): string {
  const t = text.trim().replace(/\s+/g, " ");
  if (t) return t.length > 120 ? `${t.substring(0, 117)}…` : t;
  if (attachments === 0) return "";
  if (kind.image) return attachments === 1 ? "📷 Photo" : `📷 ${attachments} photos`;
  if (kind.video) return attachments === 1 ? "🎬 Video" : `🎬 ${attachments} videos`;
  return attachments === 1 ? "📎 File" : `📎 ${attachments} files`;
}
