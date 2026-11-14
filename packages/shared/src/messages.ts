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
