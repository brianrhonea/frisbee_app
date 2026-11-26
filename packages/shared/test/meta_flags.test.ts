import { describe, expect, it } from "vitest";
import { isBuildAllowed, metaFlagDefaults, parseMetaFlags } from "../src/meta_flags.js";

describe("parseMetaFlags", () => {
  it("defaults to no gate and videos off", () => {
    expect(parseMetaFlags(undefined)).toEqual(metaFlagDefaults);
    expect(parseMetaFlags({})).toEqual({ minBuild: { ios: 0, android: 0 }, videoUploads: false });
    expect(metaFlagDefaults.videoUploads).toBe(false);
  });
  it("reads valid values", () => {
    expect(parseMetaFlags({ minBuild: { ios: 120, android: 7 }, videoUploads: true })).toEqual({
      minBuild: { ios: 120, android: 7 },
      videoUploads: true,
    });
  });
  it("ignores malformed values per field", () => {
    expect(parseMetaFlags({ minBuild: { ios: "120", android: -1 }, videoUploads: "true" })).toEqual(metaFlagDefaults);
    expect(parseMetaFlags({ minBuild: 5, videoUploads: 1 })).toEqual(metaFlagDefaults);
    expect(parseMetaFlags({ minBuild: { ios: 1.5, android: Number.NaN } }).minBuild).toEqual({ ios: 0, android: 0 });
    expect(parseMetaFlags("x")).toEqual(metaFlagDefaults);
  });
});

describe("isBuildAllowed", () => {
  const flags = parseMetaFlags({ minBuild: { ios: 100, android: 0 } });
  it("gates per platform", () => {
    expect(isBuildAllowed(flags, "ios", 99)).toBe(false);
    expect(isBuildAllowed(flags, "ios", 100)).toBe(true);
    expect(isBuildAllowed(flags, "android", 1)).toBe(true);
  });
  it("fails open when the flags can't be read", () => {
    expect(isBuildAllowed(null, "ios", 1)).toBe(true);
  });
});
