"use client";
import { clubTooYoungMessage } from "@stall10/shared";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { useIsClubTeam } from "./ClubAge";
import { JoinWithCode } from "./CreateTeam";

/**
 * On an invite link, members can join right here instead of in the app.
 * A club team's link says it's for players 16 and over, as the app's does.
 */
export function JoinLink({ code }: { code: string }) {
  const { user } = useAuth();
  if (!user) return null;
  return <SignedInJoin code={code} />;
}

function SignedInJoin({ code }: { code: string }) {
  // inviteCodes/{code} names the team (single gets only, as the app reads it).
  const invite = useLiveDoc<{ teamId?: string }>(`inviteCodes/${code.trim().toUpperCase().replace(/[^A-Z0-9]/g, "")}`);
  const club = useIsClubTeam(invite.data?.teamId ?? null);
  return <JoinWithCode initial={code} auto note={club ? clubTooYoungMessage : undefined} />;
}
