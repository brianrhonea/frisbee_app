// The media standard (ARCHITECTURE.md §6): what people may upload, and the
// one format everything is compressed to before it's saved, so every file
// plays and shows natively on iOS, Android and the web.
import { z } from "zod";

/**
 * Accepted uploads: every photo and video format the supported devices
 * make natively — iOS (HEIC, MOV), Android (JPEG, WebP, HEIC, MP4, 3GP,
 * WebM) and Windows/macOS through the website (PNG, JPEG, GIF, WebP, HEIC,
 * MP4, MOV, MKV, WebM). Everything is converted to [mediaStandard].
 */
export const acceptedImageTypes = [
  "image/jpeg",
  "image/png",
  "image/heic",
  "image/heif",
  "image/webp",
  "image/gif",
] as const;
export const acceptedVideoTypes = [
  "video/mp4",
  "video/quicktime",
  "video/x-m4v",
  "video/x-matroska",
  "video/webm",
  "video/3gpp",
] as const;
export type AcceptedImageType = (typeof acceptedImageTypes)[number];
export type AcceptedVideoType = (typeof acceptedVideoTypes)[number];
export type AcceptedMediaType = AcceptedImageType | AcceptedVideoType;

/** File extensions for each accepted type (pickers and sniffing). */
export const mediaExtensions: Record<AcceptedMediaType, readonly string[]> = {
  "image/jpeg": ["jpg", "jpeg", "jfif"],
  "image/png": ["png"],
  "image/heic": ["heic"],
  "image/heif": ["heif"],
  "image/webp": ["webp"],
  "image/gif": ["gif"],
  "video/mp4": ["mp4"],
  "video/quicktime": ["mov"],
  "video/x-m4v": ["m4v"],
  "video/x-matroska": ["mkv"],
  "video/webm": ["webm"],
  "video/3gpp": ["3gp"],
};

/** The content type for a file name, or null if it isn't accepted. */
export function mediaTypeFor(fileName: string): AcceptedMediaType | null {
  const ext = fileName.toLowerCase().split(".").pop() ?? "";
  for (const [type, exts] of Object.entries(mediaExtensions)) {
    if (exts.includes(ext)) return type as AcceptedMediaType;
  }
  return null;
}

export const isImageType = (t: string): t is AcceptedImageType =>
  (acceptedImageTypes as readonly string[]).includes(t);
export const isVideoType = (t: string): t is AcceptedVideoType =>
  (acceptedVideoTypes as readonly string[]).includes(t);

const MB = 1024 * 1024;

/**
 * What every saved file is compressed to. Images keep the app's current
 * standard (ImageCompressor: 1920 px, JPEG 80).
 */
export const mediaStandard = {
  image: {
    /**
     * JPEG; an image with transparency (PNG, WebP, GIF) is saved as PNG so
     * it keeps it. A GIF keeps its first frame only. HEIC/HEIF need a
     * decoder with HEVC support (sharp's prebuilt binaries lack it; use
     * libheif via ffmpeg or a sharp build with libheif).
     */
    format: "image/jpeg",
    transparentFormat: "image/png",
    /** Longest edge, in pixels; smaller images aren't enlarged. */
    maxDimension: 1920,
    jpegQuality: 80,
    /** Rotated upright from EXIF, then all metadata (GPS too) removed. */
    stripMetadata: true,
    thumbnail: { maxDimension: 480, jpegQuality: 75 },
  },
  video: {
    /** MP4, H.264 (High profile) + AAC: plays natively everywhere. */
    format: "video/mp4",
    videoCodec: "h264",
    audioCodec: "aac",
    /** Longest edge, in pixels (1080p); smaller videos aren't enlarged. */
    maxDimension: 1920,
    maxFps: 30,
    /** Constant quality, capped so big uploads still shrink. */
    crf: 23,
    maxVideoBitrateKbps: 5000,
    audioBitrateKbps: 128,
    /** moov atom first so playback starts before the download ends. */
    faststart: true,
    /** A JPEG poster frame, sized like an image thumbnail. */
    poster: { maxDimension: 480, jpegQuality: 75 },
  },
} as const;

/** What an upload is for; each has its own size limit and permission check. */
export const uploadPurposes = ["avatar", "post", "chat", "teamVideo", "teamImage"] as const;
export type UploadPurpose = (typeof uploadPurposes)[number];

/** Largest file accepted before compression, matching storage.rules today. */
export const uploadLimits: Record<UploadPurpose, { image: number; video: number | null }> = {
  avatar: { image: 10 * MB, video: null },
  post: { image: 10 * MB, video: 100 * MB },
  chat: { image: 10 * MB, video: 100 * MB },
  teamImage: { image: 10 * MB, video: null },
  teamVideo: { image: 10 * MB, video: 500 * MB },
};

/**
 * Where each purpose's files live in Cloud Storage: the app's layout, which
 * storage.rules guards for reads and documents store as `path`. Processed
 * files are named after the upload id ({id}.jpg, {id}_thumb.jpg, {id}.mp4,
 * {id}_poster.jpg) in the purpose's folder.
 */
export const mediaFolders: Record<UploadPurpose, string> = {
  avatar: "users/{uid}/profile",
  post: "users/{uid}/posts/{itemId}/{uploadId}",
  teamImage: "teams/{teamId}/posts/{itemId}/{uploadId}",
  teamVideo: "teams/{teamId}/videos/{itemId}",
  chat: "teams/{teamId}/chats/{roomId}/{uid}/{itemId} or conversations/{convId}/{uid}/{itemId}",
};

// ---- Chat attachments ------------------------------------------------------
//
// Team chat and direct messages take any file, as the app does
// (lib/domain/models/chat.dart): photos are compressed like any upload;
// videos and other files are stored as sent, so they play and open as they
// are. storage.rules' attachmentSizeOk sets the same limits.

/** Any chat file but a video: 10 MB (maxAttachmentBytes in the app). */
export const chatFileMax = 10 * MB;
/** A video in a message: 100 MB (maxVideoBytes in the app). */
export const chatVideoMax = 100 * MB;

/** File types by extension, the app's table (contentTypeFor in chat.dart); anything else is application/octet-stream. */
export const chatFileTypes: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  gif: "image/gif",
  webp: "image/webp",
  bmp: "image/bmp",
  heic: "image/heic",
  heif: "image/heif",
  pdf: "application/pdf",
  txt: "text/plain",
  csv: "text/csv",
  doc: "application/msword",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xls: "application/vnd.ms-excel",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ppt: "application/vnd.ms-powerpoint",
  pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  mp4: "video/mp4",
  mov: "video/quicktime",
  m4v: "video/mp4",
  webm: "video/webm",
  "3gp": "video/3gpp",
  zip: "application/zip",
};

/** The type a chat file is sent as, from its name (the app's contentTypeFor). */
export function chatContentTypeFor(fileName: string): string {
  const dot = fileName.lastIndexOf(".");
  const ext = dot < 0 ? "" : fileName.slice(dot + 1).toLowerCase();
  return chatFileTypes[ext] ?? "application/octet-stream";
}

/**
 * Types a chat file that isn't a photo or video may be stored as: the
 * app's document types, or application/octet-stream for anything else.
 * Never HTML, SVG or script, so a stored file can't run in a browser.
 */
export const chatDocumentTypes = [
  ...new Set(Object.values(chatFileTypes).filter((t) => !t.startsWith("image/") && !t.startsWith("video/"))),
  "application/octet-stream",
] as readonly string[];

/** Video names storage.rules lets past [chatFileMax] (attachmentSizeOk). */
export const chatVideoName = /\.(mp4|mov|m4v|webm|3gp)$/i;

/**
 * The most a chat file may be, as storage.rules' attachmentSizeOk has it:
 * [chatFileMax], or [chatVideoMax] for a video ([videoType] is a video/*
 * type, or none known) named like one.
 */
export function chatAttachmentMax(fileName: string, videoType: boolean): number {
  return videoType && chatVideoName.test(fileName) ? chatVideoMax : chatFileMax;
}

/** Longest file name kept on a chat file. */
export const chatFileNameMax = 120;

/**
 * [name] as a chat file's stored name: readable, with anything that would
 * add path segments or trip up Storage URLs replaced (the app's
 * AttachmentStorage._safeName), and its last 80 characters at most.
 */
export function safeFileName(name: string): string {
  const cleaned = name.replace(/[^A-Za-z0-9._ -]/g, "_").trim();
  const short = cleaned.length > 80 ? cleaned.slice(cleaned.length - 80) : cleaned;
  return short.length === 0 ? "file" : short;
}

/** "2.4 MB", "830 KB", "12 B" (the app's formatFileSize). */
export function formatFileSize(bytes: number): string {
  if (bytes >= MB) return `${(bytes / MB).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

/** Body of `POST /v1/uploads`: asks for a signed URL to upload one file. */
export const createUploadRequestSchema = z
  .strictObject({
    purpose: z.enum(uploadPurposes),
    /**
     * A photo or video type; for `chat`, also one of [chatDocumentTypes]
     * (any other file, stored as sent, as the app stores it).
     */
    contentType: z.string().min(1).max(160),
    size: z.number().int().positive(),
    /** The file's own name (`chat`): kept on the message, and decides the video limit as storage.rules does. */
    name: z.string().trim().min(1).max(chatFileNameMax).optional(),
    /** The team (teamImage, teamVideo) or chat (chat: `teams/{t}/chats/{r}` or `conversations/{c}`) it's for. */
    targetId: z.string().min(1).max(128).optional(),
    /**
     * The post, team post, video or message the file belongs to (every
     * purpose but avatar). With [targetId] it picks the file's folder, the
     * same layout the app uses (mediaFolders), so Storage's read rules apply.
     */
    itemId: z
      .string()
      .regex(/^[A-Za-z0-9_-]{1,128}$/)
      .optional(),
  })
  .superRefine((u, ctx) => {
    if (u.purpose !== "avatar" && !u.itemId) {
      ctx.addIssue({ code: "custom", path: ["itemId"], message: "Say which post, video or message this is for." });
    }
    const media = isImageType(u.contentType) || isVideoType(u.contentType);
    if (!media && !(u.purpose === "chat" && chatDocumentTypes.includes(u.contentType))) {
      ctx.addIssue({ code: "custom", path: ["contentType"], message: "That file can't be uploaded here." });
      return;
    }
    const max = uploadMax(u.purpose, u.contentType, u.name);
    if (max == null) {
      ctx.addIssue({ code: "custom", path: ["contentType"], message: "Videos can't be uploaded here." });
    } else if (u.size > max) {
      ctx.addIssue({
        code: "custom",
        path: ["size"],
        message: `That file is too big. The most is ${Math.round(max / MB)} MB.`,
      });
    }
  });
export type CreateUploadRequest = z.input<typeof createUploadRequestSchema>;

/** A name for a chat video sent without one, so its limit still follows its type. */
const videoExtensions: Record<string, string> = {
  "video/mp4": "mp4",
  "video/quicktime": "mov",
  "video/x-m4v": "m4v",
  "video/webm": "webm",
  "video/3gpp": "3gp",
  "video/x-matroska": "mkv",
};
export function videoFileName(contentType: string, id: string): string {
  return `${id}.${videoExtensions[contentType] ?? "bin"}`;
}

/**
 * The largest file of [contentType] for [purpose], or null if that kind
 * can't be uploaded for it. Chat follows storage.rules' attachmentSizeOk:
 * 10 MB for anything, 100 MB for a video named like one ([name], or its
 * type's own extension); other purposes, [uploadLimits].
 */
export function uploadMax(purpose: UploadPurpose, contentType: string, name?: string): number | null {
  if (purpose === "chat" && !isImageType(contentType)) {
    const video = isVideoType(contentType) || contentType === "application/octet-stream";
    return chatAttachmentMax(name ?? (isVideoType(contentType) ? videoFileName(contentType, "file") : ""), video);
  }
  const limits = uploadLimits[purpose];
  return isImageType(contentType) ? limits.image : isVideoType(contentType) ? limits.video : null;
}

/**
 * An upload's life (uploads/{id}.status): `pending` until the client says
 * it's uploaded, then `ready` (images, compressed in the request) or
 * `processing` (videos, until the transcode job ends in `ready` or
 * `failed`). A file that isn't what it claims is `failed`.
 */
export const uploadStatuses = ["pending", "processing", "ready", "failed"] as const;
export type UploadStatus = (typeof uploadStatuses)[number];

/** Answer to `POST /v1/uploads`: PUT the file to [uploadUrl] with [headers]. */
export interface CreateUploadResponse {
  id: string;
  uploadUrl: string;
  /** Send exactly these with the PUT (the URL is signed for them). */
  headers: Record<string, string>;
  /** ISO 8601; ask again after this. */
  expiresAt: string;
}

/** Answer to `POST /v1/uploads/{id}/complete`. */
export interface CompleteUploadResponse {
  id: string;
  status: UploadStatus;
  /** The saved file and its thumbnail or poster (Storage paths), once ready. */
  path?: string;
  thumbPath?: string;
  contentType?: string;
  width?: number;
  height?: number;
}
