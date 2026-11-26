// Server flags in the Firestore document `meta/flags` (Sprint 2, Q19).
// The contract is docs/specifications/contracts/meta-flags.md. The older
// boolean kill switches in that document (`use_api_*`, `compress_images`)
// are the app's (feature_flags.dart) and are not described here.

/** The app platforms that have a build number. The website has no gate. */
export type AppPlatform = "ios" | "android";

export interface MetaFlags {
  /**
   * The lowest app build number (pubspec `+N`) allowed to run, per platform.
   * 0 means no gate.
   */
  minBuild: Record<AppPlatform, number>;
  /** Whether native video upload is open. Off until the owner turns it on. */
  videoUploads: boolean;
}

/** What applies when a field is missing, malformed, or the document can't be read. */
export const metaFlagDefaults: MetaFlags = {
  minBuild: { ios: 0, android: 0 },
  videoUploads: false,
};

const buildNumber = (v: unknown): number =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0 ? v : 0;

/**
 * Reads `meta/flags` data field by field: anything missing or of the wrong
 * type takes its default, so a typo in the console never locks anyone out
 * (minBuild) or opens video uploads (videoUploads).
 */
export function parseMetaFlags(data: unknown): MetaFlags {
  const d = data != null && typeof data === "object" ? (data as Record<string, unknown>) : {};
  const mb = d.minBuild != null && typeof d.minBuild === "object" ? (d.minBuild as Record<string, unknown>) : {};
  return {
    minBuild: { ios: buildNumber(mb.ios), android: buildNumber(mb.android) },
    videoUploads: d.videoUploads === true,
  };
}

/**
 * Whether [build] may run. [flags] null (the read failed or timed out)
 * allows it: the gate fails OPEN, an outage must not lock everyone out.
 */
export function isBuildAllowed(flags: MetaFlags | null, platform: AppPlatform, build: number): boolean {
  if (flags == null) return true;
  return build >= flags.minBuild[platform];
}
