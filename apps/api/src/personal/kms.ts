// Cloud KMS for personal details (PERSONAL_DETAILS_KMS_KEY, e.g.
// projects/<p>/locations/us/keyRings/stall10/cryptoKeys/personal-details).
// KMS encrypts the record itself (it's well under KMS's 64 KiB limit), with
// the document's path as additional authenticated data. Only the API's
// identity (and whoever is granted cloudkms.cryptoKeyEncrypterDecrypter on
// the key) can decrypt; see apps/api/DEPLOY.md.
import { KeyManagementServiceClient } from "@google-cloud/kms";
import type { PersonalCipher, Sealed } from "./cipher.js";

export class KmsCipher implements PersonalCipher {
  private readonly client = new KeyManagementServiceClient();

  constructor(private readonly keyName: string) {}

  async seal(plaintext: Buffer, context: string): Promise<Sealed> {
    const [res] = await this.client.encrypt({
      name: this.keyName,
      plaintext,
      additionalAuthenticatedData: Buffer.from(context),
    });
    if (!res.ciphertext) throw new Error("KMS returned no ciphertext");
    // KMS names the key version it used (projects/.../cryptoKeyVersions/N);
    // decrypting needs only the key, which picks the version itself.
    return { ciphertext: Buffer.from(res.ciphertext as Uint8Array).toString("base64"), key: this.keyName };
  }

  async open(sealed: Sealed, context: string): Promise<Buffer> {
    const [res] = await this.client.decrypt({
      name: sealed.key,
      ciphertext: Buffer.from(sealed.ciphertext, "base64"),
      additionalAuthenticatedData: Buffer.from(context),
    });
    if (!res.plaintext) throw new Error("KMS returned no plaintext");
    return Buffer.from(res.plaintext as Uint8Array);
  }
}
