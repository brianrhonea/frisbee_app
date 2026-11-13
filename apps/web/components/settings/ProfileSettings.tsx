"use client";
import { profileLimits, throwingHands } from "@stall10/shared";
import Link from "next/link";
import { type FormEvent, useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { searchTagsFor, useMyProfile } from "./useMyProfile";

const thisYear = new Date().getFullYear();
const handLabels: Record<(typeof throwingHands)[number], string> = { right: "Right", left: "Left", both: "Both" };

/** What the player writes about themselves (`PUT /v1/me/profile/details`). */
export function ProfileSettings() {
  const { user } = useAuth();
  const { profile, error: loadError } = useMyProfile();
  const [form, setForm] = useState({
    bio: "",
    pronouns: "",
    hometown: "",
    school: "",
    throwingHand: "" as "" | (typeof throwingHands)[number],
    playingSince: "",
  });
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  // Fill the form once, then leave the member's edits alone.
  useEffect(() => {
    if (!profile || loaded) return;
    setForm({
      bio: profile.bio ?? "",
      pronouns: profile.pronouns ?? "",
      hometown: profile.hometown ?? "",
      school: profile.school ?? "",
      throwingHand: profile.throwingHand ?? "",
      playingSince: profile.playingSince ? String(profile.playingSince) : "",
    });
    setLoaded(true);
  }, [profile, loaded]);

  if (!user) return null;
  if (loadError) return <p className="form-error">{loadError}</p>;
  if (!profile) return <p className="muted">Loading…</p>;
  const me = user;

  const set = (k: keyof typeof form) => (e: { target: { value: string } }) => {
    setForm((f) => ({ ...f, [k]: e.target.value }));
    setMessage(null);
  };

  async function save(e: FormEvent) {
    e.preventDefault();
    const since = form.playingSince ? Number(form.playingSince) : null;
    if (since !== null && (!Number.isInteger(since) || since < 1960 || since > thisYear)) {
      return setMessage({ ok: false, text: `Playing since is a year from 1960 to ${thisYear}.` });
    }
    setBusy(true);
    try {
      const next = { ...profile, ...form, throwingHand: form.throwingHand || null, playingSince: since };
      await callApi(me, "/v1/me/profile/details", {
        method: "PUT",
        body: {
          bio: form.bio,
          pronouns: form.pronouns,
          hometown: form.hometown,
          school: form.school,
          throwingHand: form.throwingHand || null,
          playingSince: since,
          visibility: { stats: true, teams: true, games: true, ...profile?.visibility },
          tags: searchTagsFor(next),
        },
      });
      setMessage({ ok: true, text: "Saved." });
    } catch (err) {
      setMessage({ ok: false, text: err instanceof ApiError ? err.message : "Couldn't save. Try again." });
    } finally {
      setBusy(false);
    }
  }

  const name = profile.name || me.displayName || "You";
  return (
    <form className="card settings-form" onSubmit={(e) => void save(e)}>
      <div className="settings-who">
        <Avatar name={name} url={profile.photoUrl ?? me.photoURL ?? undefined} size={64} />
        <div>
          <b>{name}</b>
          {profile.username && <p className="muted small">@{profile.username}</p>}
          <p className="muted small">Your name and photo are changed in the Stall 10 app for now.</p>
        </div>
        <Link className="btn btn-small" href={`/players/${encodeURIComponent(me.uid)}`}>
          View profile
        </Link>
      </div>

      <label>
        Bio
        <textarea value={form.bio} maxLength={profileLimits.bio} rows={3} onChange={set("bio")} />
        <small className="muted">
          {form.bio.length}/{profileLimits.bio}
        </small>
      </label>
      <div className="form-grid">
        <label>
          Pronouns
          <input value={form.pronouns} maxLength={profileLimits.pronouns} onChange={set("pronouns")} />
        </label>
        <label>
          Playing since
          <input
            type="number"
            inputMode="numeric"
            min={1960}
            max={thisYear}
            placeholder="e.g. 2019"
            value={form.playingSince}
            onChange={set("playingSince")}
          />
        </label>
        <label>
          Hometown
          <input value={form.hometown} maxLength={profileLimits.hometown} onChange={set("hometown")} />
        </label>
        <label>
          School
          <input value={form.school} maxLength={profileLimits.school} onChange={set("school")} />
        </label>
      </div>
      <fieldset>
        <legend>Throwing hand</legend>
        <div className="segmented">
          {(["", ...throwingHands] as const).map((h) => (
            <button
              key={h || "none"}
              type="button"
              className={form.throwingHand === h ? "on" : ""}
              aria-pressed={form.throwingHand === h}
              onClick={() => set("throwingHand")({ target: { value: h } })}
            >
              {h ? handLabels[h] : "Not set"}
            </button>
          ))}
        </div>
      </fieldset>
      <div className="form-actions">
        {message && <span className={message.ok ? "form-ok" : "form-error"}>{message.text}</span>}
        <button className="btn btn-primary" type="submit" disabled={busy}>
          {busy ? "Saving…" : "Save"}
        </button>
      </div>
    </form>
  );
}
