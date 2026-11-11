"use client";
import type { ReactNode } from "react";
import { useAuth } from "./AuthProvider";

/** Sign-up prompts: shown to visitors, never to someone signed in. */
export function ForVisitors({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  return user ? null : <>{children}</>;
}
