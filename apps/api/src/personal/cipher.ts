// Encryption for personal details. The service sees only this interface;
// kms.ts is the real one (Cloud KMS), LocalCipher is for the emulators,
// tests use test/fakes.ts.
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

/** A ciphertext and the key that made it, as stored. */
export interface Sealed {
  /** Base64. */
  ciphertext: string;
  /** The key's name, so a record says what opens it. */
  key: string;
}

export interface PersonalCipher {
  /**
   * Encrypts [plaintext], bound to [context] (the document's path): the
   * same ciphertext copied anywhere else won't decrypt.
   */
  seal(plaintext: Buffer, context: string): Promise<Sealed>;
  open(sealed: Sealed, context: string): Promise<Buffer>;
}

/**
 * AES-256-GCM with a key from the environment, for the emulators only
 * (server.ts refuses it otherwise): records it writes can't be read by the
 * deployed API, so it must never write to a real project.
 */
export class LocalCipher implements PersonalCipher {
  static readonly keyName = "local";
  private readonly key: Buffer;

  constructor(base64Key: string) {
    this.key = Buffer.from(base64Key, "base64");
    if (this.key.length !== 32) throw new Error("PERSONAL_DETAILS_LOCAL_KEY must be 32 bytes, base64.");
  }

  async seal(plaintext: Buffer, context: string): Promise<Sealed> {
    const iv = randomBytes(12);
    const c = createCipheriv("aes-256-gcm", this.key, iv);
    c.setAAD(Buffer.from(context));
    const body = Buffer.concat([c.update(plaintext), c.final()]);
    return { ciphertext: Buffer.concat([iv, c.getAuthTag(), body]).toString("base64"), key: LocalCipher.keyName };
  }

  async open(sealed: Sealed, context: string): Promise<Buffer> {
    const raw = Buffer.from(sealed.ciphertext, "base64");
    const d = createDecipheriv("aes-256-gcm", this.key, raw.subarray(0, 12));
    d.setAAD(Buffer.from(context));
    d.setAuthTag(raw.subarray(12, 28));
    return Buffer.concat([d.update(raw.subarray(28)), d.final()]);
  }
}
