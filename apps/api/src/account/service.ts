import {
  type IdentityResult,
  identityRequestSchema,
  mutedConversationKey,
  mutedRoomKey,
  notificationCategoryRequestSchema,
  notificationMuteRequestSchema,
  readReceiptsRequestSchema,
  profileKeywords,
} from "@stall10/shared";
import type { z } from "zod";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { MediaStorage } from "../media/storage.js";
import { type Data, type DocStore, deleteField, serverTime } from "../store.js";

const p = {
  profile: (uid: string) => `profiles/${uid}`,
  user: (uid: string) => `users/${uid}`,
  prefs: (uid: string) => `users/${uid}/settings/notifications`,
  upload: (id: string) => `uploads/${id}`,
};

function parse<S extends z.ZodType>(schema: S, body: unknown): z.output<S> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) throw fromZod(r.error);
  return r.data;
}

const str = (v: unknown) => (typeof v === "string" ? v : null);
const mapOf = (v: unknown): Data => (v && typeof v === "object" && !Array.isArray(v) && !(v instanceof Date) ? (v as Data) : {});

/**
 * The caller's own account: their name and pictures (the Auth record, as
 * the app's AuthService sets them, plus the copies on users/{uid} and the
 * profiles/{uid} directory fields), and notification settings
 * (users/{uid}/settings/notifications, owner-only in firestore.rules).
 */
export class AccountService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly media: MediaStorage | undefined,
  ) {}

  /** A finished profile-picture upload of the caller's, as its stored path. */
  private async avatarPath(caller: Caller, id: string): Promise<string> {
    const u = await this.store.get(p.upload(docIdParam(id)));
    const folder = `users/${caller.uid}/profile/`;
    if (!u || u.uid !== caller.uid || u.purpose !== "avatar" || !str(u.path)?.startsWith(folder)) {
      throw new ApiError("invalid_argument", "That picture wasn't uploaded for your profile.");
    }
    if (u.status !== "ready") throw new ApiError("failed_precondition", "That picture is still being processed. Try again in a moment.");
    if (!str(u.contentType)?.startsWith("image/")) throw new ApiError("invalid_argument", "Only photos can be used here.");
    return u.path as string;
  }

  /** The stored path of one of the caller's own profile pictures, from its URL; null for anything else. */
  private ownPicturePath(caller: Caller, url: string | null): string | null {
    const m = url?.match(/\/o\/([^?]+)/);
    if (!m) return null;
    const path = decodeURIComponent(m[1]!);
    return path.startsWith(`users/${caller.uid}/profile/`) && !path.includes("..") ? path : null;
  }

  /** Deletes pictures that are no longer shown, best effort. */
  private async forget(caller: Caller, ...urls: Array<string | null>) {
    if (!this.media) return;
    const paths = urls.map((u) => this.ownPicturePath(caller, u)).filter((x): x is string => x != null);
    const all = paths.flatMap((x) => [x, x.replace(/\.(\w+)$/, "_thumb.jpg")]);
    await Promise.all(all.map((x) => this.media!.delete(x).catch(() => undefined)));
  }

  /**
   * Changes the caller's name, profile picture or header photo. The name
   * and picture go on the Auth record (what the app reads as the user's
   * name and photo) and on the profile's directory fields; the header only
   * on the profile. Pictures replaced or removed are deleted.
   */
  async saveIdentity(caller: Caller, body: unknown): Promise<IdentityResult> {
    const req = parse(identityRequestSchema, body);
    if (!this.users.update) throw new ApiError("failed_precondition", "Accounts can't be changed here.");
    if ((req.photoUploadId || req.headerUploadId) && !this.media) {
      throw new ApiError("failed_precondition", "Pictures can't be uploaded here yet.");
    }
    const [photoPath, headerPath] = await Promise.all([
      req.photoUploadId ? this.avatarPath(caller, req.photoUploadId) : null,
      req.headerUploadId ? this.avatarPath(caller, req.headerUploadId) : null,
    ]);
    const [photoUrl, headerUrl] = await Promise.all([
      photoPath ? this.media!.downloadUrl(photoPath) : null,
      headerPath ? this.media!.downloadUrl(headerPath) : null,
    ]);
    const user = await this.users.lookup(caller.uid);
    const before = await this.store.get(p.profile(caller.uid));
    const name = req.name ?? (user?.name?.trim() || str(before?.name) || str(before?.username) || "Player");
    const photo = req.photoUploadId === undefined ? (user?.photoUrl ?? null) : photoUrl;
    const header = req.headerUploadId === undefined ? str(before?.headerUrl) : headerUrl;

    await this.users.update(caller.uid, {
      ...(req.name !== undefined && { name }),
      ...(req.photoUploadId !== undefined && { photoUrl: photo }),
    });
    await this.store.transact(async (tx) => {
      const profile = await tx.get(p.profile(caller.uid));
      tx.merge(p.user(caller.uid), { displayName: name, photoUrl: photo, updatedAt: serverTime });
      tx.merge(p.profile(caller.uid), {
        name,
        keywords: profileKeywords(name, str(profile?.username)),
        photoUrl: photo,
        ...(req.headerUploadId !== undefined && { headerUrl: header ?? deleteField }),
        updatedAt: serverTime,
      });
    });
    await this.forget(
      caller,
      req.photoUploadId !== undefined && user?.photoUrl !== photo ? (user?.photoUrl ?? null) : null,
      req.headerUploadId !== undefined && str(before?.headerUrl) !== header ? str(before?.headerUrl) : null,
    );
    return { name, photoUrl: photo, headerUrl: header };
  }

  /** users/{uid}.readReceipts (owner-only in the rules); off hides when they've read messages. */
  async setReadReceipts(caller: Caller, body: unknown): Promise<void> {
    const { on } = parse(readReceiptsRequestSchema, body);
    await this.store.transact(async (tx) => {
      tx.merge(p.user(caller.uid), { readReceipts: on });
    });
  }

  /** Turns a notification kind on or off, for every team or for one. */
  async setCategory(caller: Caller, body: unknown): Promise<void> {
    const { category, on, teamId } = parse(notificationCategoryRequestSchema, body);
    await this.store.transact(async (tx) => {
      const prefs = (await tx.get(p.prefs(caller.uid))) ?? {};
      if (teamId) {
        const teams = mapOf(prefs.teams);
        tx.merge(p.prefs(caller.uid), {
          teams: { ...teams, [teamId]: { ...mapOf(teams[teamId]), [category]: on } },
          updatedAt: serverTime,
        });
      } else {
        tx.merge(p.prefs(caller.uid), { categories: { ...mapOf(prefs.categories), [category]: on }, updatedAt: serverTime });
      }
    });
  }

  /** Drops one team's overrides, so it follows the defaults again. */
  async resetTeam(caller: Caller, rawTeam: unknown): Promise<void> {
    const teamId = docIdParam(rawTeam);
    await this.store.transact(async (tx) => {
      const prefs = await tx.get(p.prefs(caller.uid));
      const teams = { ...mapOf(prefs?.teams) };
      if (!(teamId in teams)) return;
      delete teams[teamId];
      tx.merge(p.prefs(caller.uid), { teams, updatedAt: serverTime });
    });
  }

  /** Silences or unsilences one team chat room or conversation. */
  async setMuted(caller: Caller, body: unknown): Promise<void> {
    const req = parse(notificationMuteRequestSchema, body);
    const key = req.conversationId ? mutedConversationKey(req.conversationId) : mutedRoomKey(req.teamId!, req.roomId!);
    await this.store.transact(async (tx) => {
      const prefs = await tx.get(p.prefs(caller.uid));
      const muted = Array.isArray(prefs?.mutedRooms) ? (prefs.mutedRooms as unknown[]).filter((k) => typeof k === "string" && k !== key) : [];
      if (req.muted) {
        if (muted.length >= 500) throw new ApiError("failed_precondition", "You've muted too many chats. Unmute some first.");
        muted.push(key);
      }
      tx.merge(p.prefs(caller.uid), { mutedRooms: muted, updatedAt: serverTime });
    });
  }
}
