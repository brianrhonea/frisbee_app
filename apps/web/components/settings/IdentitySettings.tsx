"use client";
import { type IdentityResult, profileLimits } from "@stall10/shared";
import type { User } from "firebase/auth";
import Link from "next/link";
import { type ChangeEvent, type FormEvent, useRef, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { photoProblem, uploadPhoto } from "@/lib/upload";
import { Avatar } from "../Avatar";

interface Props {
  me: User;
  name: string;
  username?: string;
  photoUrl: string | null;
  headerUrl: string | null;
}

/**
 * The name everyone sees, the profile picture and the header photo
 * (`PUT /v1/me/identity`; pictures upload as `avatar` first).
 */
export function IdentitySettings({ me, name: initialName, username, photoUrl, headerUrl }: Props) {
  const [name, setName] = useState(initialName);
  const [savedName, setSavedName] = useState(initialName);
  const [shown, setShown] = useState({ photoUrl, headerUrl });
  const [busy, setBusy] = useState<null | "name" | "photo" | "header">(null);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const photoInput = useRef<HTMLInputElement>(null);
  const headerInput = useRef<HTMLInputElement>(null);

  async function save(what: "name" | "photo" | "header", body: object, done: string) {
    setBusy(what);
    setMessage(null);
    try {
      const r = await callApi<IdentityResult>(me, "/v1/me/identity", { method: "PUT", body });
      setShown({ photoUrl: r.photoUrl, headerUrl: r.headerUrl });
      setName(r.name);
      setSavedName(r.name);
      // The header and menus read the Auth record's name and photo.
      await me.reload().catch(() => undefined);
      setMessage({ ok: true, text: done });
    } catch (err) {
      setMessage({ ok: false, text: problem(err, "Couldn't save. Try again.") });
    } finally {
      setBusy(null);
    }
  }

  async function pick(kind: "photo" | "header", e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    const bad = photoProblem(file, "avatar");
    if (bad) return setMessage({ ok: false, text: bad });
    setBusy(kind);
    setMessage(null);
    try {
      const up = await uploadPhoto(me, file, { purpose: "avatar" });
      await save(kind, kind === "photo" ? { photoUploadId: up.id } : { headerUploadId: up.id }, kind === "photo" ? "Profile picture updated." : "Header photo updated.");
    } catch (err) {
      setMessage({ ok: false, text: problem(err, "Couldn't upload that picture. Try again.") });
      setBusy(null);
    }
  }

  function rename(e: FormEvent) {
    e.preventDefault();
    const next = name.trim();
    if (!next) return setMessage({ ok: false, text: "Enter your name." });
    void save("name", { name: next }, "Name saved.");
  }

  return (
    <section className="card identity-card" aria-labelledby="identity-title">
      <div className="identity-header" style={shown.headerUrl ? { backgroundImage: `url(${JSON.stringify(shown.headerUrl)})` } : undefined}>
        <div className="identity-header-actions">
          <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => headerInput.current?.click()}>
            {busy === "header" ? "Uploading…" : shown.headerUrl ? "Change header" : "Add a header photo"}
          </button>
          {shown.headerUrl && (
            <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => void save("header", { headerUploadId: null }, "Header photo removed.")}>
              Remove
            </button>
          )}
        </div>
      </div>
      <div className="identity-body">
        <div className="identity-photo">
          <Avatar name={name || "You"} url={shown.photoUrl ?? undefined} size={88} />
          <div className="identity-photo-actions">
            <button type="button" className="link-button small" disabled={busy !== null} onClick={() => photoInput.current?.click()}>
              {busy === "photo" ? "Uploading…" : shown.photoUrl ? "Change photo" : "Add a photo"}
            </button>
            {shown.photoUrl && (
              <button type="button" className="link-button small" disabled={busy !== null} onClick={() => void save("photo", { photoUploadId: null }, "Profile picture removed.")}>
                Remove
              </button>
            )}
          </div>
        </div>
        <form className="settings-form identity-name" onSubmit={rename}>
          <h2 id="identity-title" className="card-title">
            Name and pictures
          </h2>
          <label>
            Name
            <input value={name} maxLength={profileLimits.name} autoComplete="name" onChange={(e) => { setName(e.target.value); setMessage(null); }} />
          </label>
          <div className="home-actions">
            <button className="btn btn-primary btn-small" disabled={busy !== null || name.trim() === savedName}>
              {busy === "name" ? "Saving…" : "Save name"}
            </button>
            {username && <span className="muted small">@{username}</span>}
            <Link className="btn btn-small" href={`/players/${encodeURIComponent(me.uid)}`}>
              View profile
            </Link>
          </div>
          <p className="muted small">Your name, photo and header show on your profile even when it&apos;s private.</p>
          {message && <p className={message.ok ? "form-ok" : "form-error"} role="status">{message.text}</p>}
        </form>
      </div>
      <input ref={photoInput} type="file" accept="image/*,.heic,.heif" hidden onChange={(e) => void pick("photo", e)} />
      <input ref={headerInput} type="file" accept="image/*,.heic,.heif" hidden onChange={(e) => void pick("header", e)} />
    </section>
  );
}
