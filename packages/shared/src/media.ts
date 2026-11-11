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

/** Body of `POST /v1/uploads`: asks for a signed URL to upload one file. */
export const createUploadRequestSchema = z
  .strictObject({
    purpose: z.enum(uploadPurposes),
    contentType: z.enum([...acceptedImageTypes, ...acceptedVideoTypes]),
    size: z.number().int().positive(),
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
    const limits = uploadLimits[u.purpose];
    const max = isImageType(u.contentType) ? limits.image : limits.video;
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
