import {
  type AcceptedImageType,
  chatDocumentTypes,
  chatFileMax,
  chatUploadQuota,
  type CompleteUploadResponse,
  type CreateUploadResponse,
  createUploadRequestSchema,
  isImageType,
  isVideoType,
  safeFileName,
  type UploadPurpose,
  type UploadStatus,
  uploadLimits,
  uploadMax,
  videoFileName,
} from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { filesOf } from "../hub/uploads.js";
import { can, isMember, mapOf, roleIn, strings } from "../teams/access.js";
import { compressImage, type HeicDecoder, UnreadableImage } from "./image.js";
import { sniffBytes, sniffChatMediaType, sniffMediaType } from "./sniff.js";
import type { MediaStorage } from "./storage.js";
import { nextStatus, videoOutputs } from "./transcode.js";

/**
 * The Storage folder for an upload's processed files: the app's own layout
 * (mediaFolders in packages/shared), so storage.rules decide who reads them
 * and documents keep referencing them by `path`. Every id is one path
 * segment. [targetId] was checked by checkTarget.
 */
export function mediaFolder(uid: string, purpose: UploadPurpose, targetId: string | undefined, itemId: string | undefined, uploadId: string): string {
  const item = () => docIdParam(itemId);
  switch (purpose) {
    case "avatar":
      return `users/${uid}/profile`;
    case "post":
      return `users/${uid}/posts/${item()}/${uploadId}`;
    case "teamImage":
      return `teams/${docIdParam(targetId)}/posts/${item()}/${uploadId}`;
    case "teamVideo":
      return `teams/${docIdParam(targetId)}/videos/${item()}`;
    case "chat": {
      const room = targetId?.match(/^teams\/([^/]+)\/chats\/([^/]+)$/);
      if (room) return `teams/${docIdParam(room[1])}/chats/${docIdParam(room[2])}/${uid}/${item()}`;
      const conv = targetId?.match(/^conversations\/([^/]+)$/);
      if (conv) return `conversations/${docIdParam(conv[1])}/${uid}/${item()}`;
      throw new ApiError("invalid_argument", "Say which chat this is for.");
    }
  }
}

/** Signed upload URLs last this long. */
const urlLifetimeMs = 15 * 60_000;

const MB = 1024 * 1024;

/** Picks up queued transcodes (a Cloud Run job execution, wired at deploy). */
export interface TranscodeQueue {
  enqueue(uploadId: string): Promise<void>;
}

const denied = (m: string) => new ApiError("permission_denied", m);

/**
 * Media uploads (ARCHITECTURE.md §6). The client asks for an upload; the
 * API checks the purpose's permission (storage.rules) and size limit,
 * records uploads/{id} and returns a signed URL to uploads/raw/{uid}/{id}.
 * On complete, the API checks the file it got (owner, real size, real type
 * by its bytes), then compresses an image in the request or queues a video
 * for transcoding. Chat videos and files are stored as sent instead, as the
 * app stores them, so they play and open in every client.
 */
export class UploadService {
  constructor(
    private readonly store: DocStore,
    private readonly storage: MediaStorage,
    private readonly opts: { heic?: HeicDecoder; queue?: TranscodeQueue; now?: () => number } = {},
  ) {}

  private now() {
    return (this.opts.now ?? Date.now)();
  }

  /**
   * Who may upload for each purpose, as storage.rules decides it: your own
   * avatar and posts; team photos and film with manageTeam; chat files as
   * someone in the conversation, or who may write in the team room.
   */
  private async checkTarget(uid: string, purpose: UploadPurpose, targetId: string | undefined) {
    switch (purpose) {
      case "avatar":
      case "post":
        return;
      case "teamImage":
      case "teamVideo": {
        const team = targetId ? await this.store.get(`teams/${docIdParam(targetId)}`) : null;
        if (!team) throw new ApiError("not_found", "That team doesn't exist anymore.");
        if (!can(team, uid, "manageTeam")) throw denied("You can't add photos or film to this team.");
        return;
      }
      case "chat": {
        const room = targetId?.match(/^teams\/([^/]+)\/chats\/([^/]+)$/);
        const conv = targetId?.match(/^conversations\/([^/]+)$/);
        if (room) return this.checkRoom(uid, room[1], room[2]);
        if (conv) return this.checkConversation(uid, conv[1]);
        throw new ApiError("invalid_argument", "Say which chat this is for.");
      }
    }
  }

  /** canWrite(teamId, roomId) in storage.rules. */
  private async checkRoom(uid: string, teamId: string, roomId: string) {
    const [team, room] = await Promise.all([
      this.store.get(`teams/${teamId}`),
      this.store.get(`teams/${teamId}/chats/${roomId}`),
    ]);
    if (!team || !room) throw new ApiError("not_found", "That chat doesn't exist anymore.");
    const role = roleIn(team, uid) === "stats" ? "player" : roleIn(team, uid);
    const ids = strings(room.writeRoles);
    const mine = strings(mapOf(team.memberRoles)[uid]);
    const ok =
      isMember(team, uid) &&
      (role === "owner" ||
        ids.includes("everyone") ||
        ids.includes(role) ||
        mine.slice(0, 10).some((r) => ids.includes(r)) ||
        strings(room.writeUsers).includes(uid));
    if (!ok) throw denied("You can't post in this chat.");
  }

  /**
   * inConversation() in storage.rules, and more: the conversation must
   * exist and list the caller, direct ones too (the rules go by the id
   * alone), so nobody stores files against a conversation never started.
   */
  private async checkConversation(uid: string, convId: string) {
    const direct = !/^g-[A-Za-z0-9]+$/.test(convId);
    if (direct && !convId.split("_").includes(uid)) throw denied("You're not in this conversation.");
    const conv = await this.store.get(`conversations/${docIdParam(convId)}`);
    if (!conv || !strings(conv.participants).includes(uid)) throw denied("You're not in this conversation.");
  }

  /** Today (UTC), the day uploadQuotas/{uid} counts. */
  private quotaDay() {
    return new Date(this.now()).toISOString().slice(0, 10);
  }

  /**
   * Adds upload [id]'s [bytes] received to today's chat quota, once (a
   * retried complete isn't charged again); false (nothing added) if it
   * would pass it.
   */
  private async chargeBytes(uid: string, id: string, bytes: number): Promise<boolean> {
    const day = this.quotaDay();
    return this.store.transact(async (tx) => {
      const [upload, quota] = await Promise.all([tx.get(`uploads/${id}`), tx.get(quotaPath(uid))]);
      if (upload?.chargedBytes === bytes) return true;
      const used = usage(quota, day);
      if (used.bytes + bytes > chatUploadQuota.bytes) return false;
      tx.set(quotaPath(uid), { day, files: used.files, bytes: used.bytes + bytes, updatedAt: serverTime });
      tx.update(`uploads/${id}`, { chargedBytes: bytes });
      return true;
    });
  }

  /** `POST /v1/uploads`. */
  async create(caller: Caller, body: unknown): Promise<CreateUploadResponse> {
    const parsed = createUploadRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const { purpose, contentType, size, targetId, itemId, name } = parsed.data;
    await this.checkTarget(caller.uid, purpose, targetId);
    // The URL takes up to the limit for the declared kind (and, in chat, name).
    const maxBytes = uploadMax(purpose, contentType, name) ?? uploadLimits[purpose].image;
    const id = this.store.newId("uploads");
    const folder = mediaFolder(caller.uid, purpose, targetId, itemId, id);
    const rawPath = `uploads/raw/${caller.uid}/${id}`;
    const expiresAt = new Date(this.now() + urlLifetimeMs);
    const signed = await this.storage.signedUploadUrl(rawPath, contentType, maxBytes, expiresAt);
    const day = this.quotaDay();
    await this.store.transact(async (tx) => {
      // Chat files are stored as soon as they're complete, sent or not: a daily quota bounds them.
      if (purpose === "chat") {
        const used = usage(await tx.get(quotaPath(caller.uid)), day);
        if (used.files >= chatUploadQuota.files || used.bytes + size > chatUploadQuota.bytes) throw overQuota();
        tx.set(quotaPath(caller.uid), { day, files: used.files + 1, bytes: used.bytes, updatedAt: serverTime });
      }
      tx.create(`uploads/${id}`, {
        uid: caller.uid,
        purpose,
        contentType,
        size,
        targetId: targetId ?? null,
        itemId: itemId ?? null,
        ...(name && { name }),
        folder,
        status: "pending" satisfies UploadStatus,
        rawPath,
        createdAt: serverTime,
        expiresAt,
      });
    });
    return { id, uploadUrl: signed.url, headers: signed.headers, expiresAt: expiresAt.toISOString() };
  }

  /** `POST /v1/uploads/{id}/complete`. */
  async complete(caller: Caller, id: string): Promise<CompleteUploadResponse> {
    const upload = await this.store.get(`uploads/${id}`);
    if (!upload || upload.uid !== caller.uid) throw new ApiError("not_found", "No such upload.");
    const status = upload.status as UploadStatus;
    if (status !== "pending") return answer(id, upload);
    const rawPath = String(upload.rawPath);
    const purpose = upload.purpose as UploadPurpose;
    const folder = String(upload.folder);

    // Everything from here reads and copies this generation of the raw
    // file: a second PUT to the signed URL makes a new one, which fails.
    const stat = await this.storage.stat(rawPath);
    if (stat == null) throw new ApiError("failed_precondition", "The file hasn't finished uploading.");
    const { size, generation } = stat;
    if (purpose === "chat" && !(await this.chargeBytes(caller.uid, id, size))) {
      const e = overQuota();
      await this.reject(id, rawPath, e.message);
      throw e;
    }
    const head = await this.storage.read(rawPath, sniffBytes, generation);
    const type =
      purpose === "chat"
        ? sniffChatMediaType(head, String(upload.contentType ?? ""), typeof upload.name === "string" ? upload.name : undefined)
        : sniffMediaType(head);
    if (purpose === "chat" && (type == null || isVideoType(type))) return this.keepAsSent(id, upload, type, size, generation);
    const limits = uploadLimits[purpose];
    const max = type == null ? null : isImageType(type) ? limits.image : limits.video;
    let problem: string | null = null;
    if (type == null) problem = "That file isn't a photo or video we can use.";
    else if (max == null) problem = "Videos can't be uploaded here.";
    else if (size > max) problem = `That file is too big. The most is ${Math.round(max / MB)} MB.`;
    if (problem) {
      await this.reject(id, rawPath, problem);
      throw new ApiError("invalid_argument", problem);
    }

    if (type != null && isVideoType(type)) {
      const out = videoOutputs(folder, id);
      await this.store.transact(async (tx) => {
        tx.update(`uploads/${id}`, {
          status: nextStatus(status, "video_queued"),
          sniffedType: type,
          actualSize: size,
          updatedAt: serverTime,
        });
        tx.set(`transcodeJobs/${id}`, {
          uploadId: id,
          uid: caller.uid,
          input: rawPath,
          ...out,
          status: "queued",
          createdAt: serverTime,
        });
      });
      await this.opts.queue?.enqueue(id);
      return { id, status: "processing" };
    }

    let compressed: Awaited<ReturnType<typeof compressImage>>;
    try {
      compressed = await compressImage(await this.storage.read(rawPath, undefined, generation), type as AcceptedImageType, { heic: this.opts.heic });
    } catch (e) {
      if (!(e instanceof UnreadableImage)) throw e;
      const message = "That photo couldn't be read. Try a JPEG or PNG.";
      await this.reject(id, rawPath, message);
      throw new ApiError("invalid_argument", message);
    }
    const { image, thumb } = compressed;
    const path = `${folder}/${id}.${image.contentType === "image/png" ? "png" : "jpg"}`;
    const thumbPath = `${folder}/${id}_thumb.jpg`;
    await this.storage.write(path, image.data, image.contentType);
    await this.storage.write(thumbPath, thumb.data, thumb.contentType);
    const done: Data = {
      status: nextStatus(status, "image_saved"),
      sniffedType: type,
      actualSize: size,
      path,
      thumbPath,
      contentType: image.contentType,
      width: image.width,
      height: image.height,
      updatedAt: serverTime,
    };
    await this.store.transact(async (tx) => tx.update(`uploads/${id}`, done));
    await this.storage.delete(rawPath).catch(() => undefined);
    return answer(id, done);
  }

  /**
   * A chat video or file, stored as sent beside the message's other files
   * ({folder}/{id}-{name}), as the app's AttachmentStorage stores them. A
   * video's type is the one its bytes show; any other file keeps a
   * declared document type, else application/octet-stream, so nothing is
   * stored as a photo, video or page it isn't. The limit is storage.rules'
   * attachmentSizeOk: 10 MB, or 100 MB for a video named like one.
   */
  private async keepAsSent(
    id: string,
    upload: Data,
    type: ReturnType<typeof sniffMediaType>,
    size: number,
    generation: string,
  ): Promise<CompleteUploadResponse> {
    const rawPath = String(upload.rawPath);
    const declared = String(upload.contentType ?? "");
    const video = type != null && isVideoType(type);
    const contentType = video ? type : chatDocumentTypes.includes(declared) ? declared : "application/octet-stream";
    const name = typeof upload.name === "string" && upload.name ? upload.name : video ? videoFileName(type, id) : id;
    const max = video ? (uploadMax("chat", type, name) ?? chatFileMax) : chatFileMax;
    if (size > max) {
      const problem = `That file is too big. The most is ${Math.round(max / MB)} MB.`;
      await this.reject(id, rawPath, problem);
      throw new ApiError("invalid_argument", problem);
    }
    const path = `${String(upload.folder)}/${id}-${safeFileName(name)}`;
    // Only the generation checked above is copied, and the copy must be the size checked.
    const problem = "The file changed while it was being saved. Try sending it again.";
    try {
      await this.storage.copy(rawPath, path, contentType, generation);
    } catch (e) {
      // 404: that generation is gone; 412: it no longer matches.
      if (![404, 412].includes(Number((e as { code?: unknown }).code))) throw e;
      await this.reject(id, rawPath, problem);
      throw new ApiError("failed_precondition", problem);
    }
    if ((await this.storage.stat(path))?.size !== size) {
      await this.storage.delete(path).catch(() => undefined);
      await this.reject(id, rawPath, problem);
      throw new ApiError("failed_precondition", problem);
    }
    const done: Data = {
      status: nextStatus("pending", "file_saved"),
      sniffedType: type,
      actualSize: size,
      path,
      contentType,
      updatedAt: serverTime,
    };
    await this.store.transact(async (tx) => tx.update(`uploads/${id}`, done));
    await this.storage.delete(rawPath).catch(() => undefined);
    return answer(id, done);
  }

  /**
   * `DELETE /v1/uploads/{id}`: a chat file taken out of the composer before
   * sending. Only its owner may, and only while the message it was
   * uploaded for doesn't hold it (that message isn't sent, or was sent
   * without it); its raw and stored files are deleted. A file already sent
   * goes with its message.
   */
  async remove(caller: Caller, id: string): Promise<void> {
    const upload = await this.store.get(`uploads/${id}`);
    if (!upload || upload.uid !== caller.uid) throw new ApiError("not_found", "No such upload.");
    if (upload.purpose !== "chat") throw new ApiError("failed_precondition", "Only a file in an unsent message can be removed.");
    // targetId and itemId were checked when the upload was made (checkTarget, the schema).
    const message = `${String(upload.targetId)}/messages/${docIdParam(upload.itemId)}`;
    const removed = await this.store.transact(async (tx) => {
      const [now, sent] = await Promise.all([tx.get(`uploads/${id}`), tx.get(message)]);
      if (!now || now.status === "removed") return null;
      // The message may have gone without it (removed while still uploading).
      const held = typeof now.path === "string" && filesOf(sent?.attachments).some((f) => f.path === now.path);
      if (held) throw new ApiError("failed_precondition", "That file was sent. Delete the message to remove it.");
      tx.update(`uploads/${id}`, { status: nextStatus(now.status as UploadStatus, "removed"), updatedAt: serverTime });
      return now;
    });
    if (!removed) return;
    const paths = [removed.rawPath, removed.path, removed.thumbPath].filter((p): p is string => typeof p === "string");
    await Promise.all(paths.map((p) => this.storage.delete(p).catch(() => undefined)));
  }

  private async reject(id: string, rawPath: string, error: string) {
    await this.store.transact(async (tx) =>
      tx.update(`uploads/${id}`, { status: nextStatus("pending", "rejected"), error, updatedAt: serverTime }),
    );
    await this.storage.delete(rawPath).catch(() => undefined);
  }
}

const quotaPath = (uid: string) => `uploadQuotas/${uid}`;

/** What uploadQuotas/{uid} says was used on [day] (nothing if it's another day's). */
function usage(q: Data | null, day: string): { files: number; bytes: number } {
  if (!q || q.day !== day) return { files: 0, bytes: 0 };
  return { files: typeof q.files === "number" ? q.files : 0, bytes: typeof q.bytes === "number" ? q.bytes : 0 };
}

const overQuota = () =>
  new ApiError(
    "resource_exhausted",
    `You've sent a lot of files today (the most is ${chatUploadQuota.files} files or ${chatUploadQuota.bytes / (1024 * MB)} GB a day). Try again tomorrow.`,
  );

function answer(id: string, u: Data): CompleteUploadResponse {
  const out: CompleteUploadResponse = { id, status: u.status as UploadStatus };
  for (const k of ["path", "thumbPath", "contentType"] as const) if (typeof u[k] === "string") out[k] = u[k] as string;
  for (const k of ["width", "height"] as const) if (typeof u[k] === "number") out[k] = u[k] as number;
  return out;
}
