// Reports and blocks (App Store guideline 1.2): anyone can report a post,
// comment, message, team post or person, and block a person. Reports go to
// Stall 10's staff queue (`reports/{id}`, server-only), and reports on a
// team's chat, posts and their comments also to that team's admins. A
// block is written to both people (`users/{uid}/blocks/{other}`, `mine`
// says who chose it) so firestore.rules check one document either way.
// The app's Report and Block in lib/domain/models/moderation.dart.
import { z } from "zod";

const id = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);

/** Why something is reported, in the order the sheet lists them. */
export const reportReasons = [
  "spam",
  "harassment",
  "hate",
  "sexual",
  "violence",
  "self_harm",
  "minor_safety",
  "impersonation",
  "other",
] as const;
export type ReportReason = (typeof reportReasons)[number];

export const reportReasonLabels: Record<ReportReason, string> = {
  spam: "Spam or scam",
  harassment: "Bullying or harassment",
  hate: "Hate speech or symbols",
  sexual: "Nudity or sexual content",
  violence: "Violence or threats",
  self_harm: "Self-harm or suicide",
  minor_safety: "Puts a young player at risk",
  impersonation: "Pretending to be someone else",
  other: "Something else",
};

/** What a report is about. Team kinds go to that team's admins too. */
export const reportTargetSchema = z.discriminatedUnion("kind", [
  z.strictObject({ kind: z.literal("post"), postId: id }),
  z.strictObject({ kind: z.literal("comment"), postId: id, commentId: id }),
  z.strictObject({ kind: z.literal("teamPost"), teamId: id, postId: id }),
  z.strictObject({ kind: z.literal("teamPostComment"), teamId: id, postId: id, commentId: id }),
  z.strictObject({ kind: z.literal("teamMessage"), teamId: id, roomId: id, messageId: id }),
  z.strictObject({ kind: z.literal("directMessage"), conversationId: id, messageId: id }),
  z.strictObject({ kind: z.literal("user"), uid: id }),
]);
export type ReportTarget = z.infer<typeof reportTargetSchema>;
export type ReportKind = ReportTarget["kind"];

export const reportDetailsMax = 1000;

/** `POST /v1/reports`. [block] also blocks the author. */
export const reportRequestSchema = z.strictObject({
  target: reportTargetSchema,
  reason: z.enum(reportReasons),
  details: z.string().trim().max(reportDetailsMax).optional(),
  block: z.boolean().optional(),
});
export type ReportRequest = z.infer<typeof reportRequestSchema>;

/** After `POST /v1/reports`: [blocked] when the author was blocked too. */
export interface ReportResult {
  id: string;
  blocked: boolean;
}

/** Most reports one person files a day. */
export const reportsPerDay = 30;

/** What the reported thing said when it was reported. */
export interface ReportSnapshot {
  text: string;
  images: string[];
}

export const reportStatuses = ["open", "removed", "dismissed"] as const;
export type ReportStatus = (typeof reportStatuses)[number];

/** A report as the staff queue and team admins see it (never the reported person). */
export interface ReportInfo {
  id: string;
  target: ReportTarget;
  reason: ReportReason;
  details: string | null;
  /** Who wrote the reported thing (the person, for a user report). */
  authorId: string;
  authorName: string;
  snapshot: ReportSnapshot;
  /** Set for team chat, team posts and their comments. */
  teamId: string | null;
  teamName: string | null;
  /** Staff see who reported; team admins don't. */
  reporterId: string | null;
  reporterName: string | null;
  status: ReportStatus;
  createdAt: string | null;
  resolvedAt: string | null;
  resolvedBy: string | null;
  note: string | null;
  /** The author is suspended (staff only). */
  authorSuspended?: boolean;
}

/**
 * What staff do with a report: remove the content (and close every open
 * report on it), dismiss it, warn the author (a notification), or suspend
 * the author's account (no sign-in, no posting) or lift that.
 */
export const staffActions = ["remove", "dismiss", "warn", "suspend", "unsuspend"] as const;
export type StaffAction = (typeof staffActions)[number];
export const staffActionSchema = z.strictObject({
  action: z.enum(staffActions),
  note: z.string().trim().max(500).optional(),
});

/** Team admins remove the reported content or dismiss the report. */
export const teamReportActions = ["remove", "dismiss"] as const;
export const teamReportActionSchema = z.strictObject({ action: z.enum(teamReportActions) });

/** Someone the caller blocked (`GET /v1/me/blocks`). */
export interface BlockInfo {
  uid: string;
  name: string;
  username: string | null;
  photoUrl: string | null;
  blockedAt: string | null;
}

/** `GET /v1/me/moderation`: whether the caller works in the staff queue. */
export interface ModerationAccess {
  staff: boolean;
}

/** The message a warned author gets. */
export const warningText =
  "Something you posted broke Stall 10's community guidelines and was reported. Please read the guidelines; repeated breaks can get an account suspended.";
