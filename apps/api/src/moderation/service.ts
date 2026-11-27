import { createHash } from "node:crypto";
import {
  type BlockInfo,
  followKey,
  type ModerationAccess,
  type ReportInfo,
  type ReportResult,
  type ReportSnapshot,
  type ReportTarget,
  reportReasons,
  reportRequestSchema,
  staffActionSchema,
  teamReportActionSchema,
  warningText,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { canReadRoom } from "../hub/access.js";
import { docIdParam } from "../ids.js";
import type { DocQueries } from "../queries.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, clip, isMember, roleIn, strings } from "../teams/access.js";
import { trustedProfilePhoto } from "../media/photo_url.js";

const p = {
  report: (id: string) => `reports/${id}`,
  block: (owner: string, other: string) => `users/${owner}/blocks/${other}`,
  blocks: (owner: string) => `users/${owner}/blocks`,
  follow: (uid: string, other: string) => `users/${uid}/follows/${followKey("user", other)}`,
  followRequest: (owner: string, uid: string) => `profiles/${owner}/followRequests/${uid}`,
  profile: (uid: string) => `profiles/${uid}`,
  limits: (uid: string) => `limits/${uid}`,
  notification: (uid: string, id: string) => `users/${uid}/notifications/${id}`,
  team: (id: string) => `teams/${id}`,
  post: (id: string) => `posts/${id}`,
  comment: (postId: string, id: string) => `posts/${postId}/comments/${id}`,
  teamPost: (t: string, id: string) => `teams/${t}/posts/${id}`,
  teamPostComment: (t: string, post: string, id: string) => `teams/${t}/posts/${post}/comments/${id}`,
  room: (t: string, room: string) => `teams/${t}/chats/${room}`,
  teamMessage: (t: string, room: string, id: string) => `teams/${t}/chats/${room}/messages/${id}`,
  conversation: (id: string) => `conversations/${id}`,
  directMessage: (c: string, id: string) => `conversations/${c}/messages/${id}`,
};

const str = (v: unknown) => (typeof v === "string" ? v : "");
const iso = (v: unknown) => (v instanceof Date ? v.toISOString() : typeof v === "string" ? v : null);
const gone = () => new ApiError("not_found", "That isn't there any more.");
const denied = (m: string) => new ApiError("permission_denied", m);

/** The longest text kept from the reported thing. */
const snapshotMax = 2000;

/** Where [t] lives, for the report's evidence and for removing it. */
export function contentPath(t: ReportTarget): string {
  switch (t.kind) {
    case "post":
      return p.post(t.postId);
    case "comment":
      return p.comment(t.postId, t.commentId);
    case "teamPost":
      return p.teamPost(t.teamId, t.postId);
    case "teamPostComment":
      return p.teamPostComment(t.teamId, t.postId, t.commentId);
    case "teamMessage":
      return p.teamMessage(t.teamId, t.roomId, t.messageId);
    case "directMessage":
      return p.directMessage(t.conversationId, t.messageId);
    case "user":
      return p.profile(t.uid);
  }
}

/** One report per person per thing: a second report of it is the same document. */
export function reportId(reporter: string, t: ReportTarget): string {
  return createHash("sha256").update(`${reporter}|${contentPath(t)}`).digest("hex").substring(0, 24);
}

/** Image addresses on a post, message or comment (images, attachments). */
function imagesOf(d: Data): string[] {
  const list = [...(Array.isArray(d.images) ? d.images : []), ...(Array.isArray(d.attachments) ? d.attachments : [])];
  return list
    .map((i) => (typeof i === "string" ? i : i && typeof i === "object" ? str((i as Data).url) : ""))
    .filter((u) => u.startsWith("https://"))
    .slice(0, 10);
}

function snapshotOf(t: ReportTarget, d: Data): ReportSnapshot {
  if (t.kind === "user") {
    const bits = [str(d.name), d.username ? `@${str(d.username)}` : "", str(d.bio)].filter(Boolean);
    return { text: clip(bits.join("\n"), snapshotMax), images: [str(d.photoUrl)].filter((u) => u.startsWith("https://")) };
  }
  const text = [str(d.title), str(d.body), str(d.text)].filter(Boolean).join("\n");
  return { text: clip(text, snapshotMax), images: imagesOf(d) };
}

/** Takes reported content down: each kind's own delete, run with the right to do it. */
export interface ContentRemover {
  remove(target: ReportTarget, authorId: string, team: Data | null): Promise<void>;
}

/** A team's owner, whose rights team content is removed with. */
export function ownerOf(team: Data): string | null {
  const members = team.members;
  if (!members || typeof members !== "object") return null;
  return Object.keys(members).find((uid) => roleIn(team, uid) === "owner") ?? null;
}

/** Who sees a team's reports: its owner, and members who may moderate. */
export const reviewsTeamReports = (team: Data, uid: string) =>
  isMember(team, uid) && (roleIn(team, uid) === "owner" || can(team, uid, "moderate") || can(team, uid, "manageTeam"));

/** Account switches staff use; absent where accounts can't be changed (tests without it). */
export interface AccountSwitch {
  setDisabled(uid: string, disabled: boolean): Promise<void>;
}

/**
 * Reports and blocks (App Store guideline 1.2). The Admin SDK skips
 * firestore.rules, which keep every client out of `reports` and
 * `users/{uid}/blocks`: only this writes them.
 *
 * A report snapshots what was reported, so an edit or delete later doesn't
 * erase the evidence, and is never shown to the reported person; team
 * admins see reports on their team's chat, posts and comments without the
 * reporter's name. Staff are callers whose ID token has the `staff` claim
 * (firebase/scripts/set-staff.mjs).
 *
 * A block is written to both people (`mine` on the blocker's copy), and
 * takes away the follows and follow requests between them; the rules then
 * refuse new follows, direct messages, comments and likes between them.
 */
export class ModerationService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly queries: DocQueries,
    private readonly remover: ContentRemover,
    private readonly accounts: AccountSwitch | undefined,
    /** Whether an under-13 refusal disabled the account: lifting a suspension then leaves it disabled (N4). */
    private readonly disabledForAge: (uid: string) => Promise<boolean>,
  ) {}

  // Reports -----------------------------------------------------------------

  /** What [t] is, as [uid] may see it: its document, author and team. Not found otherwise. */
  private async visible(uid: string, t: ReportTarget): Promise<{ doc: Data; authorId: string; team: Data | null }> {
    const doc = await this.store.get(contentPath(t));
    if (!doc) throw gone();
    if (t.kind === "user") {
      if (t.uid === uid) throw new ApiError("invalid_argument", "You can't report yourself.");
      return { doc, authorId: t.uid, team: null };
    }
    const authorId = str(doc.authorId);
    if (t.kind === "post" || t.kind === "comment") {
      const post = t.kind === "post" ? doc : await this.store.get(p.post(t.postId));
      if (!post) throw gone();
      const author = str(post.authorId);
      if (post.private === true && author !== uid && !(await this.store.get(p.follow(uid, author)))) throw gone();
      return { doc, authorId, team: null };
    }
    if (t.kind === "directMessage") {
      const conv = await this.store.get(p.conversation(t.conversationId));
      const inIt = t.conversationId.startsWith("g-")
        ? strings(conv?.participants).includes(uid)
        : t.conversationId.split("_").includes(uid);
      if (!conv || !inIt) throw gone();
      return { doc, authorId, team: null };
    }
    const team = await this.store.get(p.team(t.teamId));
    if (!team) throw gone();
    if (t.kind === "teamMessage") {
      const room = await this.store.get(p.room(t.teamId, t.roomId));
      if (!room || !isMember(team, uid) || !canReadRoom(team, uid, room)) throw gone();
    } else {
      const post = t.kind === "teamPost" ? doc : await this.store.get(p.teamPost(t.teamId, t.postId));
      if (!post || (!isMember(team, uid) && post.public !== true)) throw gone();
    }
    return { doc, authorId, team };
  }

  /** `POST /v1/reports`: reports something, and with `block`, blocks its author too. */
  async report(caller: Caller, body: unknown): Promise<ReportResult> {
    const parsed = reportRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const { target, reason, details, block } = parsed.data;
    const { doc, authorId, team } = await this.visible(caller.uid, target);
    if (authorId === caller.uid) throw new ApiError("invalid_argument", "You can't report your own post or message.");
    const [reporter, author] = await Promise.all([this.nameOf(caller.uid), this.nameOf(authorId, doc)]);
    const id = reportId(caller.uid, target);
    await this.store.transact(async (tx) => {
      const before = await tx.get(p.report(id));
      // A second report of the same thing updates the first, and reopens it.
      tx.set(p.report(id), {
        target,
        reason,
        details: details ? details : null,
        reporterId: caller.uid,
        reporterName: reporter.name,
        authorId,
        authorName: author.name,
        snapshot: snapshotOf(target, doc),
        teamId: team ? (target as { teamId: string }).teamId : null,
        teamName: team ? clip(str(team.name), 100) : null,
        status: "open",
        createdAt: before?.createdAt ?? serverTime,
        updatedAt: serverTime,
        resolvedAt: null,
        resolvedBy: null,
        note: null,
      });
    });
    let blocked = false;
    if (block && authorId) {
      await this.block(caller, authorId);
      blocked = true;
    }
    return { id, blocked };
  }

  private async nameOf(uid: string, doc?: Data): Promise<{ name: string }> {
    const [profile, user] = await Promise.all([this.store.get(p.profile(uid)), this.users.lookup(uid)]);
    const username = str(profile?.username);
    const name = str(profile?.name) || str(user?.name) || str(doc?.authorName) || (username ? `@${username}` : "Player");
    return { name: clip(name, 80) };
  }

  private info(id: string, d: Data, staff: boolean, suspended?: boolean): ReportInfo {
    const reason = reportReasons.includes(d.reason as never) ? (d.reason as ReportInfo["reason"]) : "other";
    const snap = (d.snapshot ?? {}) as Data;
    return {
      id,
      target: d.target as ReportTarget,
      reason,
      details: str(d.details) || null,
      authorId: str(d.authorId),
      authorName: str(d.authorName),
      snapshot: { text: str(snap.text), images: strings(snap.images) },
      teamId: str(d.teamId) || null,
      teamName: str(d.teamName) || null,
      reporterId: staff ? str(d.reporterId) || null : null,
      reporterName: staff ? str(d.reporterName) || null : null,
      status: d.status === "removed" || d.status === "dismissed" ? d.status : "open",
      createdAt: iso(d.createdAt),
      resolvedAt: iso(d.resolvedAt),
      resolvedBy: str(d.resolvedBy) || null,
      note: str(d.note) || null,
      ...(suspended !== undefined && { authorSuspended: suspended }),
    };
  }

  private static newestFirst(a: ReportInfo, b: ReportInfo) {
    return (b.createdAt ?? "").localeCompare(a.createdAt ?? "");
  }

  private async openReports(where: Record<string, string>): Promise<Array<{ id: string; data: Data }>> {
    return this.queries.fields(
      "reports",
      ["target", "reason", "details", "reporterId", "reporterName", "authorId", "authorName", "snapshot", "teamId", "teamName", "status", "createdAt", "resolvedAt", "resolvedBy", "note"],
      300,
      { ...where, status: "open" },
    );
  }

  /**
   * Closes every open report on the same content as [report] (several
   * people may have reported it) as [status].
   */
  private async close(report: Data, status: "removed" | "dismissed", by: string, note: string | null, onlyThis?: string) {
    const target = report.target as ReportTarget;
    const others = onlyThis
      ? [{ id: onlyThis }]
      : (await this.openReports({ authorId: str(report.authorId) })).filter(
          (r) => contentPath(r.data.target as ReportTarget) === contentPath(target),
        );
    await this.store.transact(async (tx) => {
      for (const r of others) {
        tx.merge(p.report(r.id), { status, resolvedAt: serverTime, resolvedBy: by, note });
      }
    });
  }

  private async teamFor(caller: Caller, rawTeam: unknown): Promise<{ teamId: string; team: Data }> {
    const teamId = docIdParam(rawTeam);
    const team = await this.store.get(p.team(teamId));
    if (!team || !isMember(team, caller.uid)) throw new ApiError("not_found", "That team doesn't exist.");
    if (!reviewsTeamReports(team, caller.uid)) throw denied("Only the team's admins see its reports.");
    return { teamId, team };
  }

  /** `GET /v1/teams/:id/reports`: open reports on the team's chat, posts and comments. */
  async teamReports(caller: Caller, rawTeam: unknown): Promise<ReportInfo[]> {
    const { teamId } = await this.teamFor(caller, rawTeam);
    const rows = await this.openReports({ teamId });
    return rows.map((r) => this.info(r.id, r.data, false)).sort(ModerationService.newestFirst);
  }

  /** `POST /v1/teams/:id/reports/:reportId`: an admin removes the content or dismisses the report. */
  async resolveTeamReport(caller: Caller, rawTeam: unknown, rawReport: unknown, body: unknown): Promise<void> {
    const { teamId, team } = await this.teamFor(caller, rawTeam);
    const parsed = teamReportActionSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const id = docIdParam(rawReport);
    const report = await this.store.get(p.report(id));
    if (!report || report.teamId !== teamId) throw new ApiError("not_found", "That report was already handled.");
    if (parsed.data.action === "remove") {
      await this.remover.remove(report.target as ReportTarget, str(report.authorId), team);
      await this.close(report, "removed", caller.uid, null);
    } else {
      await this.close(report, "dismissed", caller.uid, null, id);
    }
  }

  // Staff ------------------------------------------------------------------

  private static requireStaff(caller: Caller) {
    if (caller.staff !== true) throw denied("Only Stall 10 staff review reports.");
  }

  /** `GET /v1/me/moderation`. */
  access(caller: Caller): ModerationAccess {
    return { staff: caller.staff === true };
  }

  /** `GET /v1/staff/reports`: every open report, newest first. */
  async staffReports(caller: Caller): Promise<ReportInfo[]> {
    ModerationService.requireStaff(caller);
    const rows = await this.openReports({});
    const authors = [...new Set(rows.map((r) => str(r.data.authorId)).filter(Boolean))];
    const limits = await this.store.getAll(authors.map((a) => p.limits(a)));
    const suspended = new Map(authors.map((a, i) => [a, limits[i]?.suspended === true]));
    return rows.map((r) => this.info(r.id, r.data, true, suspended.get(str(r.data.authorId)) ?? false)).sort(ModerationService.newestFirst);
  }

  /** `POST /v1/staff/reports/:id`: remove, dismiss, warn, suspend or lift a suspension. */
  async staffAction(caller: Caller, rawReport: unknown, body: unknown): Promise<void> {
    ModerationService.requireStaff(caller);
    const parsed = staffActionSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const { action } = parsed.data;
    const note = parsed.data.note ? parsed.data.note : null;
    const id = docIdParam(rawReport);
    const report = await this.store.get(p.report(id));
    if (!report) throw new ApiError("not_found", "No such report.");
    const target = report.target as ReportTarget;
    const authorId = str(report.authorId);
    switch (action) {
      case "remove": {
        if (target.kind === "user") throw new ApiError("invalid_argument", "A person can't be removed; suspend them instead.");
        const team = report.teamId ? await this.store.get(p.team(str(report.teamId))) : null;
        await this.remover.remove(target, authorId, team);
        await this.close(report, "removed", caller.uid, note);
        return;
      }
      case "dismiss":
        await this.close(report, "dismissed", caller.uid, note, id);
        return;
      case "warn":
        await this.warn(authorId, id);
        await this.store.transact(async (tx) => tx.merge(p.report(id), { note: note ?? "Warned", warnedAt: serverTime }));
        return;
      case "suspend":
      case "unsuspend":
        await this.suspend(authorId, action === "suspend", caller.uid);
        await this.store.transact(async (tx) =>
          tx.merge(p.report(id), { note: note ?? (action === "suspend" ? "Suspended" : "Suspension lifted") }),
        );
        return;
    }
  }

  private async warn(uid: string, reportId: string) {
    if (!uid) return;
    await this.store.transact(async (tx) =>
      tx.set(p.notification(uid, `warning_${reportId}`), {
        category: "social",
        title: "A warning from Stall 10",
        body: warningText,
        route: "/guidelines",
        createdAt: serverTime,
        read: false,
        count: 1,
      }),
    );
  }

  /**
   * Suspends [uid] (or lifts it): `limits/{uid}.suspended` stops their
   * posts, comments and messages (the rules' notMuted() and the API's
   * checkNotMuted), and the Auth account is disabled so they can't sign in.
   */
  private async suspend(uid: string, on: boolean, by: string) {
    if (!uid) return;
    // Lifting must not re-enable an account an under-13 refusal disabled (no staff override).
    // Checked first: if it throws, nothing has changed and the lift can be retried (review 4.1a).
    const keepDisabled = !on && (await this.disabledForAge(uid));
    await this.store.transact(async (tx) =>
      tx.merge(p.limits(uid), on ? { suspended: true, suspendedAt: serverTime, suspendedBy: by } : { suspended: false }),
    );
    if (keepDisabled) return;
    await this.accounts?.setDisabled(uid, on);
    // The race (review 4.1b): an under-13 refusal may have landed between the check above and the re-enable. Check again and disable it again.
    if (on) return;
    let again: boolean;
    try {
      again = await this.disabledForAge(uid);
    } catch (e) {
      // Couldn't tell: fail closed. Disable again, and let the lift be retried.
      await this.accounts?.setDisabled(uid, true);
      throw e;
    }
    if (again) await this.accounts?.setDisabled(uid, true);
  }

  // Blocks -----------------------------------------------------------------

  /** `PUT /v1/me/blocks/:uid`. Again is a no-op. */
  async block(caller: Caller, rawUid: unknown): Promise<void> {
    const other = docIdParam(rawUid);
    const me = caller.uid;
    if (other === me) throw new ApiError("invalid_argument", "You can't block yourself.");
    const [profile, user] = await Promise.all([this.store.get(p.profile(other)), this.users.lookup(other)]);
    if (!profile && !user) throw new ApiError("not_found", "That player doesn't exist.");
    const username = str(profile?.username);
    const name = clip(str(profile?.name) || str(user?.name) || (username ? `@${username}` : "Player"), 80);
    const photo = trustedProfilePhoto(profile?.photoUrl, other) || str(user?.photoUrl);
    await this.store.transact(async (tx) => {
      const theirs = await tx.get(p.block(other, me));
      tx.set(p.block(me, other), {
        mine: true,
        name,
        username: username || null,
        photoUrl: photo && photo.length <= 2000 ? photo : null,
        blockedAt: serverTime,
      });
      if (!theirs) tx.set(p.block(other, me), { mine: false, blockedAt: serverTime });
      // No follows or follow requests between them either way.
      tx.delete(p.follow(me, other));
      tx.delete(p.follow(other, me));
      tx.delete(p.followRequest(me, other));
      tx.delete(p.followRequest(other, me));
    });
  }

  /** `DELETE /v1/me/blocks/:uid`. Still blocked if they blocked the caller too. */
  async unblock(caller: Caller, rawUid: unknown): Promise<void> {
    const other = docIdParam(rawUid);
    const me = caller.uid;
    await this.store.transact(async (tx) => {
      const [mine, theirs] = await Promise.all([tx.get(p.block(me, other)), tx.get(p.block(other, me))]);
      if (!mine || mine.mine !== true) return;
      if (theirs?.mine === true) {
        tx.set(p.block(me, other), { mine: false, blockedAt: theirs.blockedAt ?? serverTime });
      } else {
        tx.delete(p.block(me, other));
        if (theirs) tx.delete(p.block(other, me));
      }
    });
  }

  /** `GET /v1/me/blocks`: who the caller blocked, and every uid hidden either way. */
  async blocks(caller: Caller): Promise<{ blocked: BlockInfo[]; hidden: string[] }> {
    const rows = await this.store.list(p.blocks(caller.uid), 1000);
    const blocked = rows
      .filter((r) => r.data.mine === true)
      .map((r) => ({
        uid: r.id,
        name: str(r.data.name) || "Player",
        username: str(r.data.username) || null,
        photoUrl: str(r.data.photoUrl) || null,
        blockedAt: iso(r.data.blockedAt),
      }))
      .sort((a, b) => a.name.localeCompare(b.name));
    return { blocked, hidden: rows.map((r) => r.id) };
  }
}

/** The block record [a] holds about [b]; one exists for each when either blocked the other. */
export const blockPath = (a: string, b: string) => p.block(a, b);

/** Whether [a] and [b] blocked each other, either way (the rules' blockedWith). */
export async function blockedBetween(store: DocStore, a: string, b: string): Promise<boolean> {
  if (!a || !b || a === b) return false;
  return (await store.get(p.block(a, b))) !== null;
}

export const blockedMessage = "You can't do that: one of you blocked the other.";

/** Throws when [a] and [b] blocked each other. */
export async function checkNotBlocked(store: DocStore, a: string, b: string): Promise<void> {
  if (await blockedBetween(store, a, b)) throw new ApiError("permission_denied", blockedMessage);
}

