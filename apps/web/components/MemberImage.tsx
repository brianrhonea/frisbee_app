"use client";
import { getDownloadURL, ref } from "firebase/storage";
import { useEffect, useState } from "react";
import { firebaseStorage } from "@/lib/firebase";
import { useAuth } from "./AuthProvider";

/**
 * A stored photo. The API's URL only works for photos anyone may see; for
 * the rest (a private friend's post), Storage gives a signed-in member a
 * link when its rules let them read the file. Visitors just see "Photo
 * unavailable". Without a public [url] it goes to Storage straight away
 * (team posts and chat attachments store only the path).
 */
export function MemberImage({ path, url, alt }: { path: string; url: string; alt: string }) {
  const { user } = useAuth();
  const [src, setSrc] = useState(url);
  const [failed, setFailed] = useState(false);
  // The public URL failed; try Storage once we know who is signed in.
  const [needsStorage, setNeedsStorage] = useState(!url);

  useEffect(() => {
    setSrc(url);
    setFailed(false);
    setNeedsStorage(!url);
  }, [url]);

  useEffect(() => {
    if (!needsStorage || user === undefined) return;
    const storage = firebaseStorage();
    if (!user || !storage) return setFailed(true);
    let live = true;
    // The flag clears only once this settles, so re-running can't cancel it.
    getDownloadURL(ref(storage, path)).then(
      (u) => {
        if (!live) return;
        setSrc(u);
        setNeedsStorage(false);
      },
      () => live && setFailed(true),
    );
    return () => {
      live = false;
    };
  }, [needsStorage, user, path]);

  if (failed) return <span className="image-missing">Photo unavailable</span>;
  // A member-only photo with no public URL: wait for Storage's link.
  if (!src) return <span className="image-missing" aria-busy="true" />;
  return (
    <img
      src={src}
      alt={alt}
      loading="lazy"
      onError={() => {
        if (src === url) setNeedsStorage(true);
        else setFailed(true);
      }}
    />
  );
}
