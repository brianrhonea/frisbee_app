"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import { useAuth } from "./AuthProvider";
import { StoreBadges } from "./StoreBadges";

/**
 * A members' page that isn't on the web yet: signed-out visitors go to
 * sign-in; members get a pointer to the app. The member area (home feed,
 * teams, chat) comes next, through the API.
 */
export function MembersOnly({ what }: { what: string }) {
  const { user } = useAuth();
  const router = useRouter();
  const path = usePathname();
  useEffect(() => {
    if (user === null) router.replace(`/sign-in?next=${encodeURIComponent(path)}`);
  }, [user, path, router]);
  if (!user) return null;
  return (
    <section className="center-card">
      <h1>Hi{user.displayName ? `, ${user.displayName.split(" ")[0]}` : ""}</h1>
      <p className="lead">{what} is coming to the website soon. For now, it&apos;s in the Stall 10 app.</p>
      <StoreBadges center />
      <p className="web-cta">
        Meanwhile, <Link href="/community">see what&apos;s happening</Link> or{" "}
        <Link href="/explore">find players and teams</Link>.
      </p>
    </section>
  );
}
