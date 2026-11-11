// Cloud Storage access for uploads. MediaStorage is what the upload service
// and the transcode job use; FirebaseMediaStorage is the real one (Admin
// SDK, the API's service account). Signing upload URLs needs credentials
// that can sign (on Cloud Run: the service account with
// iam.serviceAccounts.signBlob on itself); the emulator can't sign, so
// emulator tests put files with the Admin SDK instead.
import type { Storage } from "firebase-admin/storage";

type Bucket = ReturnType<Storage["bucket"]>;

/** Saved media is never rewritten in place (new paths), so it caches for a year. */
export const mediaCacheControl = "public, max-age=31536000, immutable";

export interface MediaStorage {
  /**
   * A URL the client PUTs one file to, valid until [expiresAt], signed for
   * [contentType] and at most [maxBytes] (x-goog-content-length-range).
   * Returns the headers the client must send with it.
   */
  signedUploadUrl(
    path: string,
    contentType: string,
    maxBytes: number,
    expiresAt: Date,
  ): Promise<{ url: string; headers: Record<string, string> }>;
  /** The object's size in bytes, or null if there's none. */
  size(path: string): Promise<number | null>;
  /** The first [bytes] bytes, or the whole object without a limit. */
  read(path: string, bytes?: number): Promise<Buffer>;
  write(path: string, data: Buffer, contentType: string): Promise<void>;
  downloadTo(path: string, file: string): Promise<void>;
  uploadFrom(file: string, path: string, contentType: string): Promise<void>;
  delete(path: string): Promise<void>;
}

export class FirebaseMediaStorage implements MediaStorage {
  constructor(private readonly bucket: Bucket) {}

  async signedUploadUrl(
    path: string,
    contentType: string,
    maxBytes: number,
    expiresAt: Date,
  ): Promise<{ url: string; headers: Record<string, string> }> {
    const headers = { "x-goog-content-length-range": `0,${maxBytes}` };
    const [url] = await this.bucket.file(path).getSignedUrl({
      version: "v4",
      action: "write",
      expires: expiresAt,
      contentType,
      extensionHeaders: headers,
    });
    return { url, headers: { "content-type": contentType, ...headers } };
  }

  async size(path: string) {
    const [exists] = await this.bucket.file(path).exists();
    if (!exists) return null;
    const [meta] = await this.bucket.file(path).getMetadata();
    return Number(meta.size ?? 0);
  }

  async read(path: string, bytes?: number) {
    const [data] = await this.bucket.file(path).download(bytes ? { start: 0, end: bytes - 1 } : {});
    return data;
  }

  async write(path: string, data: Buffer, contentType: string) {
    await this.bucket.file(path).save(data, { contentType, resumable: false, metadata: { cacheControl: mediaCacheControl } });
  }

  async downloadTo(path: string, file: string) {
    await this.bucket.file(path).download({ destination: file });
  }

  async uploadFrom(file: string, path: string, contentType: string) {
    await this.bucket.upload(file, { destination: path, contentType, metadata: { cacheControl: mediaCacheControl } });
  }

  async delete(path: string) {
    await this.bucket.file(path).delete({ ignoreNotFound: true });
  }
}
