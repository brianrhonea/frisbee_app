// The media standard (ARCHITECTURE.md §6): what people may upload, and the
// one format everything is compressed to before it's saved, so every file
// plays and shows natively on iOS, Android and the web.
import { z } from "zod";

/** Accepted uploads: PNG and JPEG photos, MP4 and MKV videos. */
export const acceptedImageTypes = ["image/png", "image/jpeg"] as const;
export const acceptedVideoTypes = ["video/mp4", "video/x-matroska"] as const;
export type AcceptedImageType = (typeof acceptedImageTypes)[number];
export type AcceptedVideoType = (typeof acceptedVideoTypes)[number];
export type AcceptedMediaType = AcceptedImageType | AcceptedVideoType;

/** File extensions for each accepted type (pickers and sniffing). */
export const mediaExtensions: Record<AcceptedMediaType, readonly string[]> = {
  "image/png": ["png"],
  "image/jpeg": ["jpg", "jpeg"],
  "video/mp4": ["mp4"],
  "video/x-matroska": ["mkv"],
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
    /** JPEG; a PNG with transparency stays PNG so it keeps it. */
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

/** Body of `POST /v1/uploads`: asks for a signed URL to upload one file. */
export const createUploadRequestSchema = z
  .strictObject({
    purpose: z.enum(uploadPurposes),
    contentType: z.enum([...acceptedImageTypes, ...acceptedVideoTypes]),
    size: z.number().int().positive(),
    /** The team, post or conversation it's for, when the purpose has one. */
    targetId: z.string().min(1).max(128).optional(),
  })
  .superRefine((u, ctx) => {
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
