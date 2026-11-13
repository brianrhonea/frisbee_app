// What a file really is, from its first bytes, so an upload's type never
// depends on its name or the type the client declared. Covers every type
// in acceptedImageTypes and acceptedVideoTypes (packages/shared/src/media.ts).
import type { AcceptedMediaType } from "@stall10/shared";

/** How many leading bytes sniffing needs. */
export const sniffBytes = 64;

const ascii = (b: Uint8Array, start: number, end: number) => String.fromCharCode(...b.subarray(start, end));
const startsWith = (b: Uint8Array, sig: number[], at = 0) => sig.every((x, i) => b[at + i] === x);

/** ISO base media (MP4, MOV, HEIC…) brands, major then compatible. */
function ftypBrands(b: Uint8Array): string[] | null {
  if (b.length < 12 || ascii(b, 4, 8) !== "ftyp") return null;
  const size = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  const end = Math.min(b.length, size > 0 ? size : b.length);
  const brands = [ascii(b, 8, 12)];
  for (let i = 16; i + 4 <= end; i += 4) brands.push(ascii(b, i, i + 4));
  return brands.map((x) => x.trim().toLowerCase());
}

const heicBrands = new Set(["heic", "heix", "heim", "heis", "hevc", "hevx", "hevm", "hevs"]);
const heifBrands = new Set(["mif1", "msf1", "heif"]);

/**
 * The accepted type of a file starting with [head], or null if it's none
 * of them. Pass at least [sniffBytes] bytes.
 */
export function sniffMediaType(head: Uint8Array): AcceptedMediaType | null {
  const b = head;
  if (startsWith(b, [0xff, 0xd8, 0xff])) return "image/jpeg";
  if (startsWith(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "image/png";
  if (ascii(b, 0, 6) === "GIF87a" || ascii(b, 0, 6) === "GIF89a") return "image/gif";
  if (ascii(b, 0, 4) === "RIFF" && ascii(b, 8, 12) === "WEBP") return "image/webp";
  // Matroska and WebM: an EBML header naming its DocType.
  if (startsWith(b, [0x1a, 0x45, 0xdf, 0xa3])) {
    return ascii(b, 0, b.length).includes("webm") ? "video/webm" : "video/x-matroska";
  }
  const brands = ftypBrands(b);
  if (!brands) return null;
  const [major] = brands;
  // The major brand decides; compatible brands break ties for images.
  if (heicBrands.has(major)) return "image/heic";
  if (heifBrands.has(major)) return brands.some((x) => heicBrands.has(x)) ? "image/heic" : "image/heif";
  if (major === "qt") return "video/quicktime";
  if (major.startsWith("m4v")) return "video/x-m4v";
  if (major.startsWith("3gp") || major.startsWith("3g2")) return "video/3gpp";
  // isom, iso2…iso6, mp41, mp42, avc1, dash, M4A-less MP4 brands.
  if (/^(iso\d|isom|mp4\d|avc\d|dash|mmp4|f4v)$/.test(major)) return "video/mp4";
  return null;
}
