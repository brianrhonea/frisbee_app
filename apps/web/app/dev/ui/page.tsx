import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Showcase } from "@/components/ui/Showcase";

// Every shared component in every state, for review and the browser tests
// (axe, hit areas, 200% text). Not a product page: development and test builds
// only, a 404 in production.
export const metadata: Metadata = { title: "Components", robots: { index: false, follow: false } };

export default function Page() {
  if (process.env.NODE_ENV === "production") notFound();
  return <Showcase />;
}
