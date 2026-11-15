"use client";
import { formatFileSize } from "@stall10/shared";
import { getDownloadURL, ref } from "firebase/storage";
import { useEffect, useState } from "react";
import { firebaseStorage } from "@/lib/firebase";
import { useAuth } from "./AuthProvider";
import { MemberImage } from "./MemberImage";
import "./chat_attachments.css";

/** A message's stored file (ChatAttachment in the app). */
export interface ChatFile {
  path: string;
  name?: string;
  contentType?: string;
  size?: number;
}

/** A link to [path] from Storage, when its rules let the member read it; null if they don't. */
function useStorageUrl(path: string, wanted: boolean): string | null | undefined {
  const { user } = useAuth();
  const [url, setUrl] = useState<string | null | undefined>(undefined);
  useEffect(() => {
    if (!wanted || user === undefined) return;
    const storage = firebaseStorage();
    if (!user || !storage) return setUrl(null);
    let live = true;
    getDownloadURL(ref(storage, path)).then(
      (u) => live && setUrl(u),
      () => live && setUrl(null),
    );
    return () => {
      live = false;
    };
  }, [wanted, user, path]);
  return url;
}

/**
 * One attachment in a thread, as the app shows it: photos inline, videos
 * playing in the conversation ("Video · 12.3 MB"), any other file as its
 * name and size, to download.
 */
export function ChatAttachment({ file }: { file: ChatFile }) {
  const type = file.contentType ?? "";
  const image = type.startsWith("image/");
  const video = type.startsWith("video/");
  const url = useStorageUrl(file.path, !image);
  const name = file.name || "Attachment";
  const size = formatFileSize(file.size ?? 0);
  if (image) {
    return (
      <span className="message-image">
        <MemberImage path={file.path} url="" alt={file.name ?? ""} />
      </span>
    );
  }
  if (video) {
    if (url === null) return <span className="image-missing">Video unavailable</span>;
    return (
      <span className="message-video">
        {url ? <video src={url} controls preload="metadata" playsInline aria-label={name} /> : <span className="image-missing" aria-busy="true" />}
        <small className="muted">Video · {size}</small>
      </span>
    );
  }
  const label = (
    <>
      <span aria-hidden="true">📄</span>
      <span className="message-file-main">
        <b>{name}</b>
        <small>{size}</small>
      </span>
      {url && <span aria-hidden="true">⤓</span>}
    </>
  );
  return url ? (
    <a className="message-file" href={url} download={name} target="_blank" rel="noopener noreferrer" aria-label={`Download ${name}`}>
      {label}
    </a>
  ) : (
    <span className="message-file" aria-busy={url === undefined}>
      {label}
      {url === null && <small className="muted">Unavailable</small>}
    </span>
  );
}
