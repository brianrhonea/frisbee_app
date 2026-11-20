// A team's Videos section (teams/{id}/videos and videoFolders; TeamVideo
// and VideoFolder in the app): YouTube links (stored as the 11-character
// id, never a URL) and uploaded files, filed in folders. The limits are the
// rules' (firebase/firestore.rules, match /videos and /videoFolders).
import { z } from "zod";

const MB = 1024 * 1024;

export const videoLimits = {
  title: 100,
  description: 2000,
  /** A video's folderId, and a folder's name. */
  folderId: 40,
  folderName: 40,
  authorName: 80,
  fileName: 200,
  /** Per uploaded file (storage.rules and firestore.rules). */
  fileBytes: 500 * MB,
  /** Per team (the app's; rules can't add files up). */
  teamQuotaBytes: 5 * 1024 * MB,
} as const;

/** A YouTube video id, as stored. */
export const youtubeIdPattern = /^[A-Za-z0-9_-]{11}$/;

/**
 * File extensions the app uploads and their content types (VideoFile.types;
 * validFile's list in firestore.rules).
 */
export const videoFileTypes: Record<string, string> = {
  mp4: "video/mp4",
  m4v: "video/x-m4v",
  mov: "video/quicktime",
  mkv: "video/x-matroska",
  webm: "video/webm",
  avi: "video/x-msvideo",
  wmv: "video/x-ms-wmv",
  mpg: "video/mpeg",
  mpeg: "video/mpeg",
  "3gp": "video/3gpp",
};
export const videoFileContentTypes = [...new Set(Object.values(videoFileTypes))];

/**
 * The video id in a YouTube link (watch, youtu.be, shorts, live, embed) or a
 * bare id; null if [text] isn't one (TeamVideo.youtubeIdFrom).
 */
export function youtubeIdFrom(text: string): string | null {
  const t = text.trim();
  if (youtubeIdPattern.test(t)) return t;
  // No URL class here (shared has no DOM or Node types): split it by hand.
  const withScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(t) ? t : `https://${t}`;
  const m = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(?:[^@/?#]*@)?([^/?#:]*)(?::\d*)?([^?#]*)(?:\?([^#]*))?/.exec(withScheme);
  if (!m) return null;
  const scheme = m[1]!.toLowerCase();
  if (scheme !== "http" && scheme !== "https") return null;
  const host = m[2]!.toLowerCase().replace(/^(www|m)\./, "");
  const decode = (s: string) => {
    try {
      return decodeURIComponent(s.replace(/\+/g, " "));
    } catch {
      return s;
    }
  };
  const segments = m[3]!.split("/").filter((s) => s.length > 0).map(decode);
  const query = (name: string) => {
    for (const pair of (m[4] ?? "").split("&")) {
      const eq = pair.indexOf("=");
      if (decode(eq < 0 ? pair : pair.substring(0, eq)) === name) return eq < 0 ? "" : decode(pair.substring(eq + 1));
    }
    return null;
  };
  let id: string | null | undefined = null;
  if (host === "youtu.be") id = segments[0];
  else if (host === "youtube.com" || host === "music.youtube.com" || host === "youtube-nocookie.com") {
    if (segments[0] === "watch") id = query("v");
    else if (["shorts", "live", "embed", "v"].includes(segments[0] ?? "") && segments.length >= 2) id = segments[1];
  }
  return id && youtubeIdPattern.test(id) ? id : null;
}

export const youtubeWatchUrl = (id: string) => `https://www.youtube.com/watch?v=${id}`;
/** YouTube's 480×360 thumbnail; every video has one. */
export const youtubeThumbnailUrl = (id: string) => `https://i.ytimg.com/vi/${id}/hqdefault.jpg`;

/** Empty for no folder. */
const folderIdField = z.string().max(videoLimits.folderId);
const titleField = z.string().trim().min(1, "Give the video a title.").max(videoLimits.title);
const descriptionField = z.string().trim().max(videoLimits.description);

/** `POST /v1/teams/:teamId/videos`: a YouTube video. Uploads are the app's for now. */
export const createVideoRequestSchema = z.strictObject({
  youtubeId: z.string().regex(youtubeIdPattern, "Paste a YouTube link."),
  folderId: folderIdField.default(""),
  title: titleField,
  description: descriptionField.default(""),
});

/**
 * `PATCH /v1/teams/:teamId/videos/:videoId`: any of the fields editors may
 * change (TeamVideo.toEditableMap). Moving to a folder is just `folderId`.
 * An uploaded video keeps `youtubeId` empty.
 */
export const editVideoRequestSchema = z
  .strictObject({
    youtubeId: z.string().max(11).optional(),
    folderId: folderIdField.optional(),
    title: titleField.optional(),
    description: descriptionField.optional(),
  })
  .refine((v) => Object.values(v).some((x) => x !== undefined), "Nothing to change.");

/** `POST /v1/teams/:teamId/video-folders` and `PATCH .../video-folders/:folderId`. */
export const saveVideoFolderRequestSchema = z.strictObject({
  name: z.string().trim().min(1, "Name the folder.").max(videoLimits.folderName),
});

/** An uploaded file (VideoFile). */
export interface VideoFileDoc {
  path?: string;
  name?: string;
  size?: number;
  contentType?: string;
}

/** A stored video (TeamVideo). */
export interface TeamVideoDoc {
  youtubeId?: string;
  file?: VideoFileDoc | null;
  folderId?: string;
  title?: string;
  description?: string;
  authorId?: string;
  authorName?: string;
  createdAt?: string;
  updatedAt?: string;
  /** The team event it's tagged to (F6), set through the API only. */
  eventId?: string;
}

/** A stored folder (VideoFolder). */
export interface VideoFolderDoc {
  name?: string;
  createdAt?: string;
}

/** "1.2 GB", "340 MB" (TeamVideo.formatBytes). */
export function formatVideoBytes(bytes: number): string {
  const gb = 1024 * MB;
  if (bytes >= gb) return `${(bytes / gb).toFixed(1)} GB`;
  return `${Math.ceil(bytes / MB)} MB`;
}

/** "MKV", "MP4", … (VideoFile.format). */
export function videoFileFormat(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot < 0 ? "Video" : name.substring(dot + 1).toUpperCase() || "Video";
}

// Notes, clips and comments on a team video (redesign F4, F5):
// teams/{id}/videos/{videoId}/comments. One collection: a comment pinned to
// a time (`atMs`) is a note, and a note with an end (`endMs`) is a clip.
// Members read and write them; the author or a manager (manageTeam) deletes.
// API-only (firestore.rules lets clients read them, and managers delete
// them only to clear a removed video's).

export const videoCommentLimits = {
  body: 1000,
  /** Times are within a day of the start (as watch together's positions). */
  maxMs: 24 * 3600 * 1000,
  /** Most a video page lists (newest kept). */
  list: 500,
} as const;

const videoMs = z.number().int().min(0).max(videoCommentLimits.maxMs);

/**
 * `POST /v1/teams/:teamId/videos/:videoId/comments`: a comment, a note at
 * `atMs`, or a clip from `atMs` to `endMs`.
 */
export const videoCommentRequestSchema = z
  .strictObject({
    body: z
      .string()
      .trim()
      .min(1, "Write something first.")
      .max(videoCommentLimits.body, `Keep it under ${videoCommentLimits.body} characters.`),
    atMs: videoMs.optional(),
    endMs: videoMs.optional(),
  })
  .refine((v) => v.endMs === undefined || (v.atMs !== undefined && v.endMs > v.atMs), {
    message: "A clip ends after it starts.",
    path: ["endMs"],
  });
export type VideoCommentRequest = z.infer<typeof videoCommentRequestSchema>;

/** `PUT /v1/teams/:teamId/videos/:videoId/event`: tags the video to a team event; null untags it. */
export const tagVideoEventRequestSchema = z.strictObject({
  eventId: z.string().min(1).max(100).nullable(),
});

/** A stored note, clip or comment (VideoComment). */
export interface VideoCommentDoc {
  authorId?: string;
  authorName?: string;
  body?: string;
  atMs?: number;
  endMs?: number;
  createdAt?: string;
}

/** Pinned to a time: a note (or clip), not a plain comment. */
export const isVideoNote = (c: VideoCommentDoc) => typeof c.atMs === "number";

/** "0:07", "1:23", "1:02:03" (VideoComment.formatTime). */
export function formatVideoTime(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = String(total % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
}

/** "1:23", or "1:23–1:40" for a clip. */
export const videoNoteTime = (c: VideoCommentDoc) =>
  typeof c.endMs === "number" ? `${formatVideoTime(c.atMs ?? 0)}–${formatVideoTime(c.endMs)}` : formatVideoTime(c.atMs ?? 0);

const createdMs = (c: VideoCommentDoc) => (c.createdAt ? Date.parse(c.createdAt) : Number.MAX_SAFE_INTEGER);

/**
 * A video's notes by time (ties oldest first) and its comments oldest
 * first (unsaved ones last), as both pages list them.
 */
export function splitVideoComments<T extends VideoCommentDoc>(all: T[]): { notes: T[]; comments: T[] } {
  const notes = all.filter(isVideoNote).sort((a, b) => (a.atMs ?? 0) - (b.atMs ?? 0) || createdMs(a) - createdMs(b));
  const comments = all.filter((c) => !isVideoNote(c)).sort((a, b) => createdMs(a) - createdMs(b));
  return { notes, comments };
}
