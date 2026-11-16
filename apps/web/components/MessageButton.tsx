"use client";
import type { OpenConversationResult } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";

/**
 * Opens (or starts) the direct conversation with [uid] (`POST
 * /v1/conversations`). Their message settings decide, as in the app:
 * straight to their inbox if they follow you, a message request if they
 * allow one, else the API's "doesn't take messages from you".
 */
export function openConversation(user: User, uid: string) {
  return callApi<OpenConversationResult>(user, "/v1/conversations", { method: "POST", body: { with: uid } });
}

/** "Message" on a player's page (the app's profile Message button), for anyone signed in but them. */
export function MessageButton({ uid }: { uid: string }) {
  const { user } = useAuth();
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (!user || user.uid === uid) return null;

  async function open() {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      const res = await openConversation(user, uid);
      router.push(`/messages?c=${encodeURIComponent(res.id)}`);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  return (
    <>
      <button type="button" className="btn btn-small" disabled={busy} onClick={() => void open()}>
        Message
      </button>
      {error && (
        <p className="form-error small" role="alert">
          {error}
        </p>
      )}
    </>
  );
}
