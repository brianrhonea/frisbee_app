import type { TeamVideoDoc, VideoFolderDoc } from "@stall10/shared";
import type { Doc } from "@/lib/live";

export type Video = Doc<TeamVideoDoc>;
export type Folder = Doc<VideoFolderDoc>;

/** Which videos the list shows (VideoFilter): all, unsorted, or one folder's. */
export type VideoFilter = { kind: "all" } | { kind: "unsorted" } | { kind: "folder"; id: string };

const teamPath = (teamId: string) => `/teams/${encodeURIComponent(teamId)}`;
export const videosHref = (teamId: string) => `${teamPath(teamId)}/more?tab=videos`;
export const videoHref = (teamId: string, id: string) => `${teamPath(teamId)}/videos/${encodeURIComponent(id)}`;
export const videosApi = (teamId: string) => `/v1/teams/${encodeURIComponent(teamId)}/videos`;
export const foldersApi = (teamId: string) => `/v1/teams/${encodeURIComponent(teamId)}/video-folders`;

/** Newest first; unsaved timestamps count as now (TeamVideo.newestFirst). */
export function newestFirst(a: Video, b: Video): number {
  const t = (v: Video) => (v.createdAt ? Date.parse(v.createdAt) : Number.MAX_SAFE_INTEGER);
  return t(b) - t(a);
}

/** A–Z, ignoring case (VideoFolder.byName). */
export const byName = (a: Folder, b: Folder) => (a.name ?? "").toLowerCase().localeCompare((b.name ?? "").toLowerCase());

/** The folder [v] is in; undefined when unsorted (its folder may have been deleted). */
export const folderOf = (v: Video, folders: Folder[]) => folders.find((f) => f.id === v.folderId);

export function matches(v: Video, f: VideoFilter, folders: Folder[]): boolean {
  if (f.kind === "all") return true;
  if (f.kind === "unsorted") return !folderOf(v, folders);
  return v.folderId === f.id;
}

/** Bytes the team's uploads use (TeamVideo.bytesUsed). */
export const bytesUsed = (videos: Video[]) => videos.reduce((sum, v) => sum + (v.file?.size ?? 0), 0);

/** The app's confirm copy for removing a video. */
export function removeMessage(v: Video): string {
  return v.file
    ? "The uploaded file will be deleted and its space freed."
    : "It will no longer be listed for the team. The video stays on YouTube.";
}
