import { readFile } from "node:fs/promises";
import path from "node:path";

/** The text pages ported from firebase/hosting (content/<slug>.html). */
export const contentPages = ["about", "help", "privacy", "terms", "cookies", "delete-account"] as const;
export type ContentSlug = (typeof contentPages)[number];

export interface ContentPage {
  html: string;
  title: string;
  description: string;
  /** The class the static page's <main> had ("doc wrap" for text pages). */
  className: string;
}

/**
 * A text page's HTML and metadata. Each file starts with a comment like
 * `<!-- Ported from ... (class="doc wrap"). title: X | description: Y -->`.
 * Our own static content, read at build time.
 */
export async function contentPage(slug: ContentSlug): Promise<ContentPage> {
  const raw = await readFile(path.join(process.cwd(), "content", `${slug}.html`), "utf8");
  const header = /^<!--([\s\S]*?)-->\s*/.exec(raw);
  const meta = header?.[1] ?? "";
  return {
    html: header ? raw.slice(header[0].length) : raw,
    className: /class="([^"]*)"/.exec(meta)?.[1] ?? "",
    title: /title:\s*(.*?)\s*\|/.exec(meta)?.[1] ?? "Stall 10",
    description: /description:\s*(.*?)\s*$/.exec(meta)?.[1] ?? "",
  };
}
