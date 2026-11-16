"use client";
// A hosted tournament's or league's News tab (the app's _NewsTab in
// hosted_tournament_screen.dart): the host's public posts tagged with the
// event, live, and for the host's admins (manageTeam, as the app's
// canPostNews) a headline and details to post once the event is
// published. News goes out as a public post on the host's page, so the
// host's and the event's followers both see it.
import { teamPostTitleMax, tournamentFollowKey } from "@stall10/shared";
import { where } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useState } from "react";
import { useAuth } from "@/components/AuthProvider";
import { TeamPostCard, type TeamPostView } from "@/components/team/TeamPostCard";
import { callApi, problem } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { canOn, type TournamentState } from "./useTournament";
import "./tournament_news.css";

/** The app's dialog caps the details at 2,000 characters (the rule allows 5,000). */
const detailsMax = 2000;

export function TournamentNews({ s }: { s: TournamentState }) {
  const t = s.t;
  const hostId = t?.hostId ?? "";
  const key = hostId ? tournamentFollowKey(hostId, s.id) : "";
  const posts = useLiveQuery<TeamPostView>(hostId ? `teams/${hostId}/posts` : null, [where("public", "==", true), where("tournamentKey", "==", key)], key);
  const rows = [...(posts.data ?? [])].sort((a, b) => (b.createdAt ?? "￿").localeCompare(a.createdAt ?? "￿"));
  const canPost = canOn(s.host, s.uid, "manageTeam");
  const published = !!t && t.status !== "draft";
  const hostName = t?.hostName ?? "The host";

  return (
    <div className="stack news-tab">
      {canPost && published && <NewsComposer hostId={hostId} tournamentKey={key} hostName={hostName} />}
      {posts.error && <p className="form-error">{posts.error}</p>}
      {posts.data && rows.length === 0 && (
        <div className="card">
          <p className="muted small">
            {canPost
              ? published
                ? `No news yet. Updates you post here go on ${hostName}'s page too, and followers get them.`
                : "Publish the event to post updates."
              : `Updates from ${hostName} show up here. Follow the event to get them.`}
          </p>
        </div>
      )}
      {rows.map((p) => (
        <TeamPostCard key={p.id} post={p} teamName={hostName} />
      ))}
      {rows.length > 0 && hostId && (
        <small className="muted">
          Also on <Link href={`/teams/${encodeURIComponent(hostId)}`}>{hostName}&apos;s page</Link>.
        </small>
      )}
    </div>
  );
}

/** "Post an update": a headline and details, public on the host's page and tagged with the event. */
function NewsComposer({ hostId, tournamentKey, hostName }: { hostId: string; tournamentKey: string; hostName: string }) {
  const { user } = useAuth();
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);

  async function post(e: FormEvent) {
    e.preventDefault();
    if (!user) return;
    // The rule needs words or a photo in the body; a headline alone isn't a post.
    if (!body.trim()) return setError(title.trim() ? "Add some details under the headline." : "Write something first.");
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(hostId)}/posts`, {
        method: "POST",
        body: { title: title.trim(), body: body.trim(), public: true, tournamentKey },
      });
      setTitle("");
      setBody("");
      setOpen(false);
    } catch (err) {
      setError(problem(err, "Couldn't post that. Try again."));
    } finally {
      setBusy(false);
    }
  }

  if (!open) {
    return (
      <div className="news-start">
        <button type="button" className="btn btn-primary" onClick={() => setOpen(true)}>
          Post an update
        </button>
        <small className="muted">Goes on {hostName}&apos;s page too; followers of either get it.</small>
      </div>
    );
  }
  return (
    <form className="card settings-form news-composer" onSubmit={(e) => void post(e)}>
      <h2 className="card-title">Post an update</h2>
      <label>
        Headline
        <input
          value={title}
          maxLength={teamPostTitleMax}
          placeholder="e.g. Semis start at 2pm on field 3"
          onChange={(e) => setTitle(e.target.value)}
          autoFocus
        />
      </label>
      <label>
        Details
        <textarea value={body} maxLength={detailsMax} rows={4} onChange={(e) => setBody(e.target.value)} />
      </label>
      {error && <p className="form-error">{error}</p>}
      <div className="form-actions">
        <button type="submit" className="btn btn-primary" disabled={busy}>
          {busy ? "Posting…" : "Post"}
        </button>
        <button
          type="button"
          className="btn"
          disabled={busy}
          onClick={() => {
            setOpen(false);
            setError(null);
          }}
        >
          Cancel
        </button>
      </div>
    </form>
  );
}
