"use client";
import { useState } from "react";
import { NavIcon } from "./NavIcons";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

/** A post's address on this site, for sharing outside Stall 10. */
export const postUrl = (id: string) => new URL(`/posts/${encodeURIComponent(id)}`, siteUrl).toString();

/** A hosted tournament or league's public page, for sharing (the app shares the same link). */
export const tournamentUrl = (id: string) => new URL(`/tournaments/${encodeURIComponent(id)}`, siteUrl).toString();

/**
 * Shares [url] with the device's share sheet where there is one (phones,
 * some desktops), otherwise copies it.
 */
export function ShareButton({
  url,
  title = "A post on Stall 10",
  className = "post-action",
}: {
  url: string;
  title?: string;
  className?: string;
}) {
  const [copied, setCopied] = useState(false);

  async function share() {
    try {
      if (typeof navigator.share === "function") {
        await navigator.share({ title, url });
        return;
      }
    } catch (e) {
      // Closing the share sheet isn't an error worth showing.
      if (e instanceof DOMException && e.name === "AbortError") return;
    }
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      window.prompt("Copy this link:", url);
    }
  }

  return (
    <button type="button" className={className} onClick={() => void share()} title="Share or copy the link">
      <NavIcon name="share" size={18} /> {copied ? "Link copied" : "Share"}
    </button>
  );
}
