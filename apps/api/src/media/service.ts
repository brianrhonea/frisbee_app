import {
  type AcceptedImageType,
  type CompleteUploadResponse,
  type CreateUploadResponse,
  createUploadRequestSchema,
  isImageType,
  isVideoType,
  type UploadPurpose,
  type UploadStatus,
  uploadLimits,
} from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { docIdParam } from "../ids.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, isMember, mapOf, roleIn, strings } from "../teams/access.js";
import { compressImage, type HeicDecoder, UnreadableImage } from "./image.js";
import { sniffBytes, sniffMediaType } from "./sniff.js";
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
 * for transcoding.
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

  /** inConversation() in storage.rules. */
  private async checkConversation(uid: string, convId: string) {
    if (/^g-[A-Za-z0-9]+$/.test(convId)) {
      const conv = await this.store.get(`conversations/${convId}`);
      if (!conv || !strings(conv.participants).includes(uid)) throw denied("You're not in this conversation.");
    } else if (!convId.split("_").includes(uid)) {
      throw denied("You're not in this conversation.");
    }
  }

  /** `POST /v1/uploads`. */
  async create(caller: Caller, body: unknown): Promise<CreateUploadResponse> {
    const parsed = createUploadRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw fromZod(parsed.error);
    const { purpose, contentType, size, targetId, itemId } = parsed.data;
    await this.checkTarget(caller.uid, purpose, targetId);
    const limits = uploadLimits[purpose];
    // The URL takes up to the purpose's largest limit for the declared kind.
    const maxBytes = (isImageType(contentType) ? limits.image : limits.video) ?? limits.image;
    const id = this.store.newId("uploads");
    const folder = mediaFolder(caller.uid, purpose, targetId, itemId, id);
    const rawPath = `uploads/raw/${caller.uid}/${id}`;
    const expiresAt = new Date(this.now() + urlLifetimeMs);
    const signed = await this.storage.signedUploadUrl(rawPath, contentType, maxBytes, expiresAt);
    await this.store.transact(async (tx) => {
      tx.create(`uploads/${id}`, {
        uid: caller.uid,
        purpose,
        contentType,
        size,
        targetId: targetId ?? null,
        itemId: itemId ?? null,
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

    const size = await this.storage.size(rawPath);
    if (size == null) throw new ApiError("failed_precondition", "The file hasn't finished uploading.");
    const type = sniffMediaType(await this.storage.read(rawPath, sniffBytes));
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
      compressed = await compressImage(await this.storage.read(rawPath), type as AcceptedImageType, { heic: this.opts.heic });
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

  private async reject(id: string, rawPath: string, error: string) {
    await this.store.transact(async (tx) =>
      tx.update(`uploads/${id}`, { status: nextStatus("pending", "rejected"), error, updatedAt: serverTime }),
    );
    await this.storage.delete(rawPath).catch(() => undefined);
  }
}

function answer(id: string, u: Data): CompleteUploadResponse {
  const out: CompleteUploadResponse = { id, status: u.status as UploadStatus };
  for (const k of ["path", "thumbPath", "contentType"] as const) if (typeof u[k] === "string") out[k] = u[k] as string;
  for (const k of ["width", "height"] as const) if (typeof u[k] === "number") out[k] = u[k] as number;
  return out;
}
