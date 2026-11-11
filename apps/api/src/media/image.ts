// Image compression to mediaStandard.image (packages/shared/src/media.ts):
// upright, metadata (GPS) stripped, longest edge ≤ 1920 px, JPEG q80, or
// PNG when the image really has transparency; a GIF keeps its first frame;
// plus a 480 px JPEG thumbnail.
//
// HEIC: sharp's prebuilt binaries read HEIF only when it holds AVIF, not
// the HEVC that iPhones write, so HEIC (and HEIF that sharp can't read)
// goes through a HeicDecoder first: ffmpegHeicDecoder (ffmpeg on PATH, as
// in the API's container; 7.1+ for the tiled images iPhones make).
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type AcceptedImageType, mediaStandard } from "@stall10/shared";
import sharp from "sharp";

/** Turns HEIC/HEIF bytes into something sharp reads (PNG). */
export interface HeicDecoder {
  toPng(input: Buffer): Promise<Buffer>;
}

/** Thrown when an image can't be decoded at all. */
export class UnreadableImage extends Error {}

/** Runs [cmd] with [args]; rejects with its stderr on failure. */
export function run(cmd: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "ignore", "pipe"] });
    let err = "";
    p.stderr.on("data", (d) => (err += d));
    p.on("error", reject);
    p.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`${cmd} exited ${code}: ${err.slice(-500)}`))));
  });
}

/** HEIC through ffmpeg (needs a seekable file, so via a temp dir). */
export function ffmpegHeicDecoder(ffmpeg = process.env.FFMPEG_PATH ?? "ffmpeg"): HeicDecoder {
  return {
    async toPng(input) {
      const dir = await mkdtemp(join(tmpdir(), "heic-"));
      try {
        const src = join(dir, "in.heic");
        const out = join(dir, "out.png");
        await writeFile(src, input);
        await run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-y", "-i", src, "-frames:v", "1", out]);
        return await readFile(out);
      } finally {
        await rm(dir, { recursive: true, force: true });
      }
    },
  };
}

export interface ImageOut {
  data: Buffer;
  contentType: "image/jpeg" | "image/png";
  width: number;
  height: number;
}

const std = mediaStandard.image;

/** [input] as sharp can read it: HEIC/HEIF decoded first if need be. */
async function readable(input: Buffer, type: AcceptedImageType, heic?: HeicDecoder): Promise<Buffer> {
  if (type !== "image/heic" && type !== "image/heif") return input;
  try {
    // AVIF-coded HEIF, which sharp reads itself.
    await sharp(input).stats();
    return input;
  } catch {
    if (!heic) throw new UnreadableImage("HEIC images can't be read here yet.");
    return heic.toPng(input);
  }
}

/** Compresses [input] (sniffed as [type]) to the standard image and thumbnail. */
export async function compressImage(
  input: Buffer,
  type: AcceptedImageType,
  opts: { heic?: HeicDecoder } = {},
): Promise<{ image: ImageOut; thumb: ImageOut }> {
  const source = await readable(input, type, opts.heic);
  // pages: 1 keeps a GIF's (or WebP's) first frame.
  const open = () => sharp(source, { pages: 1 }).rotate();
  let opaque: boolean;
  try {
    opaque = (await open().stats()).isOpaque;
  } catch (e) {
    throw new UnreadableImage(String(e));
  }
  const fit = (n: number) => ({ width: n, height: n, fit: "inside" as const, withoutEnlargement: true });

  const main = open().resize(fit(std.maxDimension));
  const encoded = opaque ? main.jpeg({ quality: std.jpegQuality, mozjpeg: true }) : main.png({ compressionLevel: 9 });
  const { data, info } = await encoded.toBuffer({ resolveWithObject: true });

  const t = await open()
    .resize(fit(std.thumbnail.maxDimension))
    .flatten({ background: "#ffffff" })
    .jpeg({ quality: std.thumbnail.jpegQuality, mozjpeg: true })
    .toBuffer({ resolveWithObject: true });

  return {
    image: { data, contentType: opaque ? "image/jpeg" : "image/png", width: info.width, height: info.height },
    thumb: { data: t.data, contentType: "image/jpeg", width: t.info.width, height: t.info.height },
  };
}
