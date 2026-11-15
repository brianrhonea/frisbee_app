"use client";
import {
  chatContentTypeFor,
  chatDocumentTypes,
  formatFileSize,
  type CompleteUploadResponse,
  type CreateUploadResponse,
  isImageType,
  isVideoType,
  mediaTypeFor,
  type UploadPurpose,
  uploadLimits,
  uploadMax,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import { ApiError, callApi } from "./client";

const MB = 1024 * 1024;

/** The file's media type: the browser's, or one from its name (HEIC often has none). */
function fileType(file: File): string | null {
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
 * The type a chat attachment is sent as: a photo or video type we take,
 * else the app's type for its name if it's a document type, else
 * application/octet-stream. Any file goes, as in the app.
 */
function chatFileType(file: File): string {
  const media = fileType(file);
  if (media && (isImageType(media) || isVideoType(media))) return media;
  const byName = chatContentTypeFor(file.name);
  return chatDocumentTypes.includes(byName) ? byName : "application/octet-stream";
}

/** Why [file] can't go in a message, or null when it can (10 MB; 100 MB for a video). */
export function chatFileProblem(file: File): string | null {
  const max = uploadMax("chat", chatFileType(file), file.name) ?? uploadLimits.chat.image;
  if (file.size > max) return `${file.name} is larger than ${formatFileSize(max)}.`;
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
  // Chat takes any file, with its name; everything else, photos only.
  const contentType = purpose === "chat" ? chatFileType(file) : fileType(file);
  if (!contentType) throw new ApiError(`${file.name} isn't a photo we can use.`, 400);
  const name = purpose === "chat" ? file.name.trim().slice(-120) : "";
  const ticket = await callApi<CreateUploadResponse>(user, "/v1/uploads", {
    method: "POST",
    body: {
      purpose,
      contentType,
      size: file.size,
      ...(itemId && { itemId }),
      ...(targetId && { targetId }),
      ...(name && { name }),
    },
  });
  let put: Response;
  try {
    put = await fetch(ticket.uploadUrl, { method: "PUT", headers: ticket.headers, body: file });
  } catch {
    throw new ApiError(`Couldn't upload ${purpose === "chat" ? file.name : "the photo"}. Check your connection and try again.`, 0);
  }
  if (!put.ok) throw new ApiError(`Couldn't upload ${purpose === "chat" ? file.name : "the photo"}. Try again.`, put.status);
  const done = await callApi<CompleteUploadResponse>(user, `/v1/uploads/${encodeURIComponent(ticket.id)}/complete`, {
    method: "POST",
  });
  if (done.status !== "ready") throw new ApiError(purpose === "chat" ? `${file.name} couldn't be used. Try another.` : "That photo couldn't be used. Try another.", 400);
  return done;
}

/**
 * Takes an unsent chat file out of the composer (`DELETE /v1/uploads/{id}`):
 * the API deletes what it stored. Best effort, as the app's Remove is.
 */
export function removeUpload(user: User, id: string): Promise<void> {
  return callApi<void>(user, `/v1/uploads/${encodeURIComponent(id)}`, { method: "DELETE" }).catch(() => undefined);
}

/** A new document id, in Firestore's alphabet, for items whose files upload first. */
export function newId(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}
