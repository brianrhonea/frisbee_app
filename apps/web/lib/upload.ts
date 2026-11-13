"use client";
import {
  type CompleteUploadResponse,
  type CreateUploadResponse,
  isImageType,
  mediaTypeFor,
  type UploadPurpose,
  uploadLimits,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import { ApiError, callApi } from "./client";

const MB = 1024 * 1024;

/** The file's media type: the browser's, or one from its name (HEIC often has none). */
export function fileType(file: File): string | null {
  if (file.type && file.type !== "application/octet-stream") return file.type;
  return mediaTypeFor(file.name);
}

/** Why [file] can't be a photo for [purpose], or null when it can. */
export function photoProblem(file: File, purpose: UploadPurpose = "post"): string | null {
  const type = fileType(file);
  if (!type || !isImageType(type)) return `${file.name} isn't a photo we can use. Try JPEG, PNG, HEIC, WebP or GIF.`;
  const max = uploadLimits[purpose].image;
  if (file.size > max) return `${file.name} is too big. The most is ${Math.round(max / MB)} MB.`;
  return null;
}

/**
 * Uploads one photo through the API (`/v1/uploads`): asks for a signed URL,
 * PUTs the file there, then has the API check and compress it. Returns the
 * upload once it's ready.
 */
export async function uploadPhoto(
  user: User,
  file: File,
  { purpose = "post", itemId, targetId }: { purpose?: UploadPurpose; itemId?: string; targetId?: string },
): Promise<CompleteUploadResponse> {
  const contentType = fileType(file);
  if (!contentType) throw new ApiError(`${file.name} isn't a photo we can use.`, 400);
  const ticket = await callApi<CreateUploadResponse>(user, "/v1/uploads", {
    method: "POST",
    body: { purpose, contentType, size: file.size, ...(itemId && { itemId }), ...(targetId && { targetId }) },
  });
  let put: Response;
  try {
    put = await fetch(ticket.uploadUrl, { method: "PUT", headers: ticket.headers, body: file });
  } catch {
    throw new ApiError("Couldn't upload the photo. Check your connection and try again.", 0);
  }
  if (!put.ok) throw new ApiError("Couldn't upload the photo. Try again.", put.status);
  const done = await callApi<CompleteUploadResponse>(user, `/v1/uploads/${encodeURIComponent(ticket.id)}/complete`, {
    method: "POST",
  });
  if (done.status !== "ready") throw new ApiError("That photo couldn't be used. Try another.", 400);
  return done;
}

/** A new document id, in Firestore's alphabet, for items whose files upload first. */
export function newId(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}
