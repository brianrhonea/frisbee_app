"use client";
import { getDownloadURL, ref } from "firebase/storage";
import { useEffect, useState } from "react";
import { firebaseStorage } from "@/lib/firebase";

/**
 * A stored photo in a member's view. The API's URL only works for photos
 * anyone may see; for the rest (a private friend's post), Storage gives the
 * signed-in member a link when its rules let them read the file. Visitors
 * (`signedIn` false) skip that and just see "Photo unavailable".
 */
export function MemberImage({ path, url, alt, signedIn = true }: { path: string; url: string; alt: string; signedIn?: boolean }) {
  const [src, setSrc] = useState(url);
  const [failed, setFailed] = useState(false);

  async function viaStorage() {
    const storage = firebaseStorage();
    if (!storage) return setFailed(true);
    try {
      setSrc(await getDownloadURL(ref(storage, path)));
    } catch {
      setFailed(true);
    }
  }

  useEffect(() => {
    setSrc(url);
    setFailed(false);
  }, [url]);

  if (failed) return <span className="image-missing">Photo unavailable</span>;
  return (
    <img
      src={src}
      alt={alt}
      loading="lazy"
      onError={() => {
        if (src === url && signedIn) void viaStorage();
        else setFailed(true);
      }}
    />
  );
}
