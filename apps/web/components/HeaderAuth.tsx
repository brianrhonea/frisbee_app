"use client";
import { signOut } from "firebase/auth";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef } from "react";
import { firebaseAuth } from "@/lib/firebase";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";

/** Log in / Sign up for visitors; an account menu for members. */
export function HeaderAuth() {
  const { user } = useAuth();
  const menu = useRef<HTMLDetailsElement>(null);
  const path = usePathname();

  // Close the menu after following one of its links.
  useEffect(() => {
    if (menu.current) menu.current.open = false;
  }, [path]);

  if (user === undefined) return null;
  if (user) {
    const name = user.displayName || "Your account";
    return (
      <details className="account-menu" ref={menu}>
        <summary aria-label="Your account">
          <Avatar name={name} url={user.photoURL ?? undefined} size={36} />
          <span className="account-name">{name}</span>
        </summary>
        <div className="account-list">
          <Link href={`/players/${encodeURIComponent(user.uid)}`}>Your profile</Link>
          <Link href="/notifications">Notifications</Link>
          <Link href="/settings">Settings</Link>
          <button type="button" onClick={() => void signOut(firebaseAuth()!)}>
            Log out
          </button>
        </div>
      </details>
    );
  }
  return (
    <>
      <Link className="link" href="/sign-in">Log in</Link>
      <Link className="btn btn-primary btn-small" href="/sign-up">Sign up</Link>
    </>
  );
}
