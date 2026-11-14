"use client";
import { searchWords } from "@stall10/shared";
import { collection, getDocs, limit, query, where } from "firebase/firestore";
import { useEffect, useState } from "react";
import { firestoreDb } from "@/lib/firebase";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";

/** Someone found in the people directory (profiles/{uid}: name, username and photo). */
export interface PickedPerson {
  uid: string;
  name: string;
  username: string | null;
  photoUrl: string | null;
}

const searchLimit = 10;

/**
 * Finds people by name or username as the app's people search does: the
 * longest word against profiles' `keywords` in Firestore (members may read
 * the directory), the rest of the words here. [exclude] are left out.
 */
export function PersonPicker({
  onPick,
  exclude = [],
  label = "Find people",
  disabled = false,
}: {
  onPick: (p: PickedPerson) => void;
  exclude?: string[];
  label?: string;
  disabled?: boolean;
}) {
  const { user } = useAuth();
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<PickedPerson[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const words = searchWords(q);
    const db = firestoreDb();
    if (words.length === 0 || !db) {
      setHits(null);
      return;
    }
    const key = [...words].sort((a, b) => b.length - a.length)[0]!.slice(0, 20);
    let live = true;
    const t = setTimeout(() => {
      getDocs(query(collection(db, "profiles"), where("keywords", "array-contains", key), limit(searchLimit * 2)))
        .then((snap) => {
          if (!live) return;
          const people = snap.docs
            .map((d) => {
              const data = d.data();
              return {
                uid: d.id,
                name: typeof data.name === "string" && data.name ? data.name : "Player",
                username: typeof data.username === "string" && data.username ? data.username : null,
                photoUrl: typeof data.photoUrl === "string" && data.photoUrl ? data.photoUrl : null,
              };
            })
            .filter((p) => {
              const hay = `${p.name} ${p.username ?? ""}`.toLowerCase();
              return words.every((w) => hay.includes(w));
            })
            .slice(0, searchLimit);
          setHits(people);
          setError(null);
        })
        .catch(() => live && setError("Couldn't search. Try again."));
    }, 250);
    return () => {
      live = false;
      clearTimeout(t);
    };
  }, [q]);

  const shown = hits?.filter((h) => h.uid !== user?.uid && !exclude.includes(h.uid)) ?? null;
  return (
    <div className="person-picker">
      <label className="sr-only" htmlFor="person-picker">
        {label}
      </label>
      <input
        id="person-picker"
        className="search-input"
        type="search"
        value={q}
        placeholder={label}
        autoComplete="off"
        disabled={disabled}
        onChange={(e) => setQ(e.target.value)}
      />
      {error && <p className="form-error">{error}</p>}
      {shown &&
        (shown.length === 0 ? (
          <p className="muted small">No one matches.</p>
        ) : (
          <ul className="person-list">
            {shown.map((p) => (
              <li key={p.uid}>
                <button
                  type="button"
                  className="person-row"
                  disabled={disabled}
                  onClick={() => {
                    onPick(p);
                    setQ("");
                  }}
                >
                  <Avatar name={p.name} url={p.photoUrl ?? undefined} size={32} />
                  <span>
                    <b>{p.name}</b>
                    {p.username && <small className="muted"> @{p.username}</small>}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        ))}
    </div>
  );
}
