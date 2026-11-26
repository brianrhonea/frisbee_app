"use client";
import { type MetaFlags, metaFlagDefaults, parseMetaFlags } from "@stall10/shared";
import { useLiveDoc } from "./live";

/**
 * The server flags in `meta/flags` (contract: docs/specifications/contracts/meta-flags.md),
 * read live from Firestore (readable signed out). While loading, or if the
 * read fails or the document is missing, the defaults apply: that is,
 * video uploads stay CLOSED. The API and storage rules enforce it; this
 * only keeps the website from offering what they'd refuse.
 */
export function useMetaFlags(): MetaFlags {
  const { data } = useLiveDoc<Record<string, unknown>>("meta/flags");
  return data ? parseMetaFlags(data) : metaFlagDefaults;
}

/** Whether native video upload is open (`meta/flags.videoUploads === true`). */
export function useVideoUploads(): boolean {
  return useMetaFlags().videoUploads;
}
