"use client";
import { useAuth } from "./AuthProvider";
import { JoinWithCode } from "./CreateTeam";

/** On an invite link, members can join right here instead of in the app. */
export function JoinLink({ code }: { code: string }) {
  const { user } = useAuth();
  if (!user) return null;
  return <JoinWithCode initial={code} auto />;
}
