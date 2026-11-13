import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { type ContentSlug, contentPage, contentPages } from "@/lib/content";

// About, Help and the legal pages: static HTML ported from firebase/hosting.
// Any other single-segment path that no route matches is a 404.
export const dynamicParams = false;

export function generateStaticParams() {
  return contentPages.map((slug) => ({ slug }));
}

type Props = { params: Promise<{ slug: string }> };

function slugOf(slug: string): ContentSlug {
  if (!(contentPages as readonly string[]).includes(slug)) notFound();
  return slug as ContentSlug;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const page = await contentPage(slugOf((await params).slug));
  // The titles already name the site.
  return { title: { absolute: page.title }, description: page.description };
}

export default async function ContentRoute({ params }: Props) {
  const page = await contentPage(slugOf((await params).slug));
  return <div className={page.className || undefined} dangerouslySetInnerHTML={{ __html: page.html }} />;
}
