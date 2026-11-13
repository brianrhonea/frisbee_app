"use client";
import type { ReactNode } from "react";
import { useAuth } from "./AuthProvider";
import { Dashboard } from "./Dashboard";

/**
 * The home page: members get their dashboard; visitors (and everyone while
 * the browser restores the session) get the server-rendered preview.
 */
export function HomeGate({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  if (user) return <Dashboard user={user} />;
  return <>{children}</>;
}
