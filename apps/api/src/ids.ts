import { ApiError } from "./errors.js";

/**
 * [v] as one document id from a URL or body, or a 400. Ids are joined into
 * document paths ("teams/" + id), so one holding "/" (even sent as %2F)
 * could point at another document.
 */
export function docIdParam(v: unknown): string {
  if (typeof v !== "string" || v.length === 0 || v.length > 128 || v.includes("/") || v === "." || v === ".." || /^__.*__$/.test(v)) {
    throw new ApiError("invalid_argument", "Invalid id.");
  }
  return v;
}
