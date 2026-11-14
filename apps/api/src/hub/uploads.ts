// Photos and files on hub writes come from the caller's finished uploads
// (`/v1/uploads`) for exactly this item, never from paths the client names.
import type { UploadPurpose } from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError } from "../errors.js";
import { docIdParam } from "../ids.js";
import type { MediaStorage } from "../media/storage.js";
import type { DocStore } from "../store.js";

/** A stored file, as ChatAttachment.toMap writes it. */
export interface StoredFile {
  path: string;
  name: string;
  contentType: string;
  size: number;
}

export function filesOf(v: unknown): StoredFile[] {
  if (!Array.isArray(v)) return [];
  return v.flatMap((i) => {
    if (!i || typeof i !== "object" || typeof (i as StoredFile).path !== "string") return [];
    const f = i as Partial<StoredFile>;
    return [
      {
        path: f.path!,
        name: typeof f.name === "string" ? f.name : "",
        contentType: typeof f.contentType === "string" ? f.contentType : "application/octet-stream",
        size: typeof f.size === "number" ? f.size : 0,
      },
    ];
  });
}

/**
 * The caller's finished uploads [ids] for [purpose], [targetId] and
 * [itemId], in order. [imagesOnly] refuses anything but photos.
 */
export async function uploadedFiles(
  store: DocStore,
  caller: Caller,
  ids: string[],
  want: { purpose: UploadPurpose; targetId: string; itemId: string; imagesOnly?: boolean },
): Promise<StoredFile[]> {
  const unique = [...new Set(ids)];
  const uploads = await Promise.all(unique.map((id) => store.get(`uploads/${docIdParam(id)}`)));
  return uploads.map((u, i) => {
    if (!u || u.uid !== caller.uid || u.purpose !== want.purpose || u.targetId !== want.targetId || u.itemId !== want.itemId) {
      throw new ApiError("invalid_argument", "That file wasn't uploaded for this.");
    }
    if (u.status !== "ready" || typeof u.path !== "string") {
      throw new ApiError("failed_precondition", "A file is still being processed. Try again in a moment.");
    }
    const contentType = typeof u.contentType === "string" ? u.contentType : "image/jpeg";
    if (want.imagesOnly && !contentType.startsWith("image/")) {
      throw new ApiError("invalid_argument", "Only photos can be added here.");
    }
    return {
      path: u.path,
      name: u.path.split("/").pop() ?? unique[i]!,
      contentType,
      size: typeof u.actualSize === "number" ? u.actualSize : 0,
    };
  });
}

/**
 * Deletes [files] that sit under [folder] (and the thumbnail and poster the
 * API made beside each). Best effort: a missing file isn't an error.
 */
export async function deleteFilesUnder(media: MediaStorage | undefined, folder: string, files: StoredFile[]) {
  if (!media) return;
  const paths = files
    .map((f) => f.path)
    .filter((p) => p.startsWith(`${folder}/`) && !p.includes(".."))
    .flatMap((p) => [p, p.replace(/\.(\w+)$/, "_thumb.jpg"), p.replace(/\.(\w+)$/, "_poster.jpg")]);
  await Promise.all([...new Set(paths)].map((p) => media.delete(p).catch(() => undefined)));
}
