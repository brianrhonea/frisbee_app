// Video transcoding to mediaStandard.video, as the Cloud Run job runs it
// (ARCHITECTURE.md §6, §8). Self-contained on purpose: no HTTP and no
// Firebase imports, only the MediaStorage and DocStore interfaces, so the
// job's entry point (owned with the deployment work) wires real ones in
// and calls runTranscodeJob for each queued job.
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mediaStandard, type UploadStatus } from "@stall10/shared";
import { type DocStore, serverTime } from "../store.js";
import type { MediaStorage } from "./storage.js";

const v = mediaStandard.video;

/**
 * ffmpeg arguments turning [input] into the standard MP4: H.264 High +
 * AAC 128 kbps stereo, longest edge ≤ 1920 (never enlarged, even sizes),
 * ≤ 30 fps, CRF 23 capped at 5 Mbps, yuv420p, moov first, metadata (GPS)
 * dropped. A video without sound stays silent (the audio map is optional).
 */
export function transcodeArgs(input: string, output: string): string[] {
  const max = v.maxDimension;
  const kbps = v.maxVideoBitrateKbps;
  return [
    "-hide_banner",
    "-loglevel", "error",
    "-y",
    "-i", input,
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-map_metadata", "-1",
    "-vf", `scale=w='min(${max},iw)':h='min(${max},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,format=yuv420p`,
    "-fpsmax", String(v.maxFps),
    "-c:v", "libx264",
    "-profile:v", "high",
    "-preset", "medium",
    "-crf", String(v.crf),
    "-maxrate", `${kbps}k`,
    "-bufsize", `${kbps * 2}k`,
    "-c:a", "aac",
    "-b:a", `${v.audioBitrateKbps}k`,
    "-ac", "2",
    ...(v.faststart ? ["-movflags", "+faststart"] : []),
    "-f", "mp4",
    output,
  ];
}

/**
 * ffmpeg arguments for the poster: the first frame, longest edge ≤ 480,
 * as JPEG. ffmpeg's -q:v 4 is about JPEG quality 75.
 */
export function posterArgs(input: string, output: string): string[] {
  const max = v.poster.maxDimension;
  return [
    "-hide_banner",
    "-loglevel", "error",
    "-y",
    "-i", input,
    "-frames:v", "1",
    "-map_metadata", "-1",
    "-vf", `scale=w='min(${max},iw)':h='min(${max},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2`,
    "-q:v", "4",
    output,
  ];
}

/** What happens to an upload. */
export type UploadEvent = "image_saved" | "video_queued" | "transcoded" | "rejected" | "failed";

const transitions: Record<UploadStatus, Partial<Record<UploadEvent, UploadStatus>>> = {
  pending: { image_saved: "ready", video_queued: "processing", rejected: "failed", failed: "failed" },
  processing: { transcoded: "ready", failed: "failed" },
  ready: {},
  failed: {},
};

/** The status after [event], or throws if [event] can't happen in [status]. */
export function nextStatus(status: UploadStatus, event: UploadEvent): UploadStatus {
  const next = transitions[status][event];
  if (!next) throw new Error(`Upload can't go from ${status} on ${event}.`);
  return next;
}

/** A queued transcode (transcodeJobs/{uploadId}). */
export interface TranscodeJob {
  uploadId: string;
  /** Storage paths. */
  input: string;
  output: string;
  poster: string;
}

/** Where a job's outputs go: upload [id]'s folder (mediaFolder). */
export const videoOutputs = (folder: string, id: string) => ({
  output: `${folder}/${id}.mp4`,
  poster: `${folder}/${id}_poster.jpg`,
});

export interface TranscodeDeps {
  store: DocStore;
  storage: MediaStorage;
  /** Runs ffmpeg with the given arguments (spawn in production). */
  ffmpeg: (args: string[]) => Promise<void>;
  workDir?: string;
}

/**
 * Runs one job: download the raw file, transcode it and make the poster,
 * save both, delete the raw file, and mark the upload ready, or failed
 * (with the reason) if any step fails. Safe to run twice: an upload no
 * longer processing is left alone.
 */
export async function runTranscodeJob(job: TranscodeJob, deps: TranscodeDeps): Promise<UploadStatus> {
  const uploadPath = `uploads/${job.uploadId}`;
  const upload = await deps.store.get(uploadPath);
  if (upload?.status !== "processing") return (upload?.status as UploadStatus) ?? "failed";
  const dir = await mkdtemp(join(deps.workDir ?? tmpdir(), "transcode-"));
  try {
    const src = join(dir, "in");
    const mp4 = join(dir, "out.mp4");
    const jpg = join(dir, "poster.jpg");
    await deps.storage.downloadTo(job.input, src);
    await deps.ffmpeg(transcodeArgs(src, mp4));
    await deps.ffmpeg(posterArgs(src, jpg));
    await deps.storage.uploadFrom(mp4, job.output, "video/mp4");
    await deps.storage.uploadFrom(jpg, job.poster, "image/jpeg");
    await finish(deps, job, "transcoded", { path: job.output, thumbPath: job.poster, contentType: "video/mp4" });
    await deps.storage.delete(job.input).catch(() => undefined);
    return "ready";
  } catch (e) {
    await finish(deps, job, "failed", { error: String(e instanceof Error ? e.message : e).slice(0, 500) });
    return "failed";
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

async function finish(deps: TranscodeDeps, job: TranscodeJob, event: UploadEvent, fields: Record<string, unknown>) {
  await deps.store.transact(async (tx) => {
    const upload = await tx.get(`uploads/${job.uploadId}`);
    const status = nextStatus((upload?.status as UploadStatus) ?? "processing", event);
    tx.update(`uploads/${job.uploadId}`, { ...fields, status, updatedAt: serverTime });
    tx.update(`transcodeJobs/${job.uploadId}`, { status: status === "ready" ? "done" : "failed", updatedAt: serverTime });
  });
}
