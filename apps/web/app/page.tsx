import { redirect } from "next/navigation";

// As on the Flutter web site, visitors land on the community feed.
export default function Home() {
  redirect("/community");
}
