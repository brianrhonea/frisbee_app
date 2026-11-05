// Shrinks photos uploaded before the app compressed them (ImageCompressor
// in lib/data/services/image_compressor.dart does it for new ones).
//
// Dry run (lists what would change, writes nothing):
//   npx tsx scripts/compress-existing-images.ts --project frisbee-app-brianrhonea-dev
// Then for real:
//   npx tsx scripts/compress-existing-images.ts --project frisbee-app-brianrhonea-dev --write
//
// Needs Application Default Credentials for the project
// (`gcloud auth application-default login`). Run on dev first. Files keep
// their path, name and format, so every link and message still works:
// JPEGs are re-encoded at quality 80, PNGs recompressed, and anything
// larger than 1920px on its longest side is shrunk. A file is only
// replaced when the result is smaller. GIFs and other files are skipped.

import { initializeApp } from "firebase-admin/app";
import { getStorage } from "firebase-admin/storage";
import sharp from "sharp";

const args = process.argv.slice(2);
const project = args[args.indexOf("--project") + 1];
const write = args.includes("--write");
const minBytes = 500 * 1024;
const maxDimension = 1920;

if (!project || project.startsWith("--")) {
  console.error("usage: tsx scripts/compress-existing-images.ts --project <id> [--write]");
  process.exit(2);
}

initializeApp({ projectId: project, storageBucket: `${project}.firebasestorage.app` });

async function main() {
  const bucket = getStorage().bucket();
  const [files] = await bucket.getFiles();
  let seen = 0;
  let changed = 0;
  let saved = 0;
  for (const file of files) {
    const type = file.metadata.contentType ?? "";
    const size = Number(file.metadata.size ?? 0);
    if (!/^image\/(jpeg|png)$/.test(type) || size < minBytes) continue;
    seen++;
    const [original] = await file.download();
    const resized = sharp(original, { failOn: "none" })
      .rotate() // upright, from EXIF orientation
      .resize({ width: maxDimension, height: maxDimension, fit: "inside", withoutEnlargement: true });
    const out =
      type === "image/png"
        ? await resized.png({ compressionLevel: 9, palette: false }).toBuffer()
        : await resized.jpeg({ quality: 80, mozjpeg: true }).toBuffer();
    if (out.length >= original.length) continue;
    changed++;
    saved += original.length - out.length;
    console.log(`${write ? "shrunk" : "would shrink"} ${file.name}: ${kb(original.length)} → ${kb(out.length)}`);
    if (write) {
      await file.save(out, {
        resumable: false,
        metadata: {
          contentType: type,
          cacheControl: "public, max-age=31536000, immutable",
          // Keep custom metadata, including the download token the app's
          // links use.
          metadata: file.metadata.metadata,
        },
      });
    }
  }
  console.log(
    `${seen} photos over ${kb(minBytes)}; ${changed} ${write ? "shrunk" : "would shrink"}, saving ${kb(saved)}.` +
      (write ? "" : " Dry run: add --write to apply."),
  );
}

const kb = (n: number) => (n >= 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)} MB` : `${Math.round(n / 1024)} KB`);

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
