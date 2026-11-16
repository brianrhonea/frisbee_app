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
