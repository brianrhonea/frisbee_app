import { createRequire } from "node:module";

/**
 * This API's version, from apps/api/package.json (next to dist/ in the
 * image, next to src/ in development). Bump it with each change to the API
 * and add the entry to apps/api/CHANGELOG.md (scripts/check-versions.mjs).
 */
export const apiVersion: string = (createRequire(import.meta.url)("../package.json") as { version: string }).version;

/** Response header naming the API version that answered. */
export const versionHeader = "x-stall10-api-version";
