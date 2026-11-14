"use client";
import { type MessagePolicy, messagePolicies, messagePolicyLabels, type MessagePolicyResponse } from "@stall10/shared";
import { useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";

/** Who can start a conversation with them (`/v1/me/message-policy`), as in the app's Settings. */
export function MessagePolicySettings() {
  const { user } = useAuth();
  const [policy, setPolicy] = useState<MessagePolicy | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!user) return;
    callApi<MessagePolicyResponse>(user, "/v1/me/message-policy")
      .then((r) => setPolicy(r.messagePolicy))
      .catch(() => setError("Couldn't load your message settings."));
  }, [user]);

  if (!user) return null;
  const me = user;

  async function choose(next: MessagePolicy) {
    const before = policy;
    setPolicy(next);
    setBusy(true);
    setError(null);
    try {
      await callApi(me, "/v1/me/message-policy", { method: "PUT", body: { messagePolicy: next } });
    } catch (e) {
      setPolicy(before);
      setError(e instanceof ApiError ? e.message : "Couldn't save. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card">
      <h2 className="card-title">Who can message you</h2>
      {policy === null && !error && <p className="muted">Loading…</p>}
      {policy !== null && (
        <fieldset className="radio-list" disabled={busy}>
          <legend className="visually-hidden">Who can message you</legend>
          {messagePolicies.map((p) => (
            <label key={p} className="switch-row">
              <span>
                <b>{messagePolicyLabels[p].label}</b>
                <small className="muted">{messagePolicyLabels[p].detail}</small>
              </span>
              <input type="radio" name="messagePolicy" checked={policy === p} onChange={() => void choose(p)} />
            </label>
          ))}
        </fieldset>
      )}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}
