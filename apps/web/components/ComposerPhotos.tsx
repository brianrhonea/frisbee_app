"use client";
import { MemberImage } from "./MemberImage";

/** One photo in a composer: a stored one, or a new one uploading (its preview an object URL). */
export type ComposerPhoto =
  | { kind: "saved"; key: string; path: string; url: string; alt: string }
  | { kind: "new"; key: string; preview: string; uploading: boolean; error?: string };

/** The photos under a post composer (home's and a team's): each with its upload state and a remove button. */
export function ComposerPhotos({ photos, onRemove }: { photos: ComposerPhoto[]; onRemove: (i: number) => void }) {
  if (photos.length === 0) return null;
  return (
    <ul className={`composer-photos n${photos.length}`}>
      {photos.map((p, i) => (
        <li key={p.key} className={p.kind === "new" && p.error ? "failed" : ""}>
          {p.kind === "saved" ? <MemberImage path={p.path} url={p.url} alt={p.alt} /> : <img src={p.preview} alt="" />}
          {p.kind === "new" && p.uploading && <span className="photo-status">Uploading…</span>}
          {p.kind === "new" && p.error && <span className="photo-status">{p.error}</span>}
          <button type="button" className="photo-remove" aria-label="Remove photo" onClick={() => onRemove(i)}>
            ×
          </button>
        </li>
      ))}
    </ul>
  );
}
