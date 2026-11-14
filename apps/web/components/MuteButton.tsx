"use client";
import { mutedConversationKey, mutedRoomKey } from "@stall10/shared";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "./AuthProvider";

type Target = { teamId: string; roomId: string } | { conversationId: string };

/** Mutes or unmutes notifications from one team chat room or conversation. */
export function MuteButton({ target }: { target: Target }) {
  const { user } = useAuth();
  const prefs = useLiveDoc<{ mutedRooms?: string[] }>(user ? `users/${user.uid}/settings/notifications` : null);
  const [busy, setBusy] = useState(false);
  if (!user || prefs.data === undefined) return null;
  const me = user;
  const key = "conversationId" in target ? mutedConversationKey(target.conversationId) : mutedRoomKey(target.teamId, target.roomId);
  const muted = (prefs.data?.mutedRooms ?? []).includes(key);

  async function toggle() {
    setBusy(true);
    try {
      await callApi(me, "/v1/me/notification-settings/mute", { method: "PUT", body: { ...target, muted: !muted } });
    } catch {
      window.alert("Couldn't change that. Try again.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <button type="button" className="text-btn" disabled={busy} aria-pressed={muted} onClick={() => void toggle()}>
      {muted ? "Unmute" : "Mute"}
    </button>
  );
}
