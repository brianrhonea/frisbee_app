"use client";
import { where } from "firebase/firestore";
import Link from "next/link";
import { useLiveQuery } from "@/lib/live";
import { useTeamHub, viewerSectionOn } from "../TeamContext";
import "./videos.css";

/** On an event: the team's videos tagged to it (F6), when its Videos section is on. */
export function EventVideos({ eventId }: { eventId: string }) {
  const { teamId, viewer } = useTeamHub();
  const on = viewer.state === "member" && viewerSectionOn(viewer, "videos");
  const live = useLiveQuery<{ title?: string; createdAt?: string }>(on ? `teams/${teamId}/videos` : null, [where("eventId", "==", eventId)], `event-videos-${eventId}`);
  const videos = (live.data ?? []).slice().sort((a, b) => (b.createdAt ?? "").localeCompare(a.createdAt ?? ""));
  if (videos.length === 0) return null;
  return (
    <div className="event-videos">
      <h3>Videos</h3>
      <ul>
        {videos.map((v) => (
          <li key={v.id}>
            <Link href={`/teams/${encodeURIComponent(teamId)}/videos/${encodeURIComponent(v.id)}`}>▶ {v.title || "Video"}</Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
