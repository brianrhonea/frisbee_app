"use client";
import type { PersonalDetailsResponse } from "@stall10/shared";
import { useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { PersonalDetailsForm } from "../PersonalDetailsForm";
import { usePersonalStatus } from "../PersonalGate";

/** Their legal name, birthday, contact details and address (`/v1/me/personal`). */
export function PersonalSettings() {
  const { user } = useAuth();
  const { refresh } = usePersonalStatus();
  const [data, setData] = useState<PersonalDetailsResponse | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!user) return;
    callApi<PersonalDetailsResponse>(user, "/v1/me/personal")
      .then(setData)
      .catch((e) => setError(e instanceof ApiError ? e.message : "Couldn't load your details. Try again."));
  }, [user]);

  if (!user) return null;
  if (error) return <p className="form-error">{error}</p>;
  if (!data) return <p className="muted">Loading…</p>;
  return (
    <div className="card">
      <h2 className="card-title">Personal details</h2>
      <PersonalDetailsForm
        user={user}
        email={data.email}
        initial={data.details}
        prefill={{ name: user.displayName }}
        onSaved={refresh}
      />
    </div>
  );
}
