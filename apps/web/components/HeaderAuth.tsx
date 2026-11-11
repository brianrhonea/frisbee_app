"use client";
import { signOut } from "firebase/auth";
import Link from "next/link";
import { firebaseAuth } from "@/lib/firebase";
import { useAuth } from "./AuthProvider";

export function HeaderAuth() {
  const { user } = useAuth();
  if (user === undefined) return null;
  if (user) {
    return (
      <>
        <Link className="link" href="/home">{user.displayName || "Home"}</Link>
        <button className="btn btn-small" type="button" onClick={() => signOut(firebaseAuth()!)}>
          Log out
        </button>
      </>
    );
  }
  return (
    <>
      <Link className="link" href="/sign-in">Log in</Link>
      <Link className="btn btn-primary btn-small" href="/sign-up">Sign up</Link>
    </>
  );
}
