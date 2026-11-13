import type { TeamPage } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { cache } from "react";
import { Avatar } from "@/components/Avatar";
import { EventItem } from "@/components/EventItem";
import { FollowButton } from "@/components/FollowButton";
import { ForVisitors } from "@/components/ForVisitors";
import { LocalTime } from "@/components/LocalTime";
import { getPublic } from "@/lib/api";
import { listingSubtitle } from "@/lib/site";

type Props = { params: Promise<{ teamId: string }> };

const load = cache((id: string) => getPublic<TeamPage>(`/v1/public/teams/${encodeURIComponent(id)}`));

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { team } = await load((await params).teamId);
  const name = team.name || "A team";
  return {
    title: name,
    description: team.description?.slice(0, 200) || `${name} on Stall 10. ${listingSubtitle(team)}`.trim(),
  };
}

const isWebLink = (url: string) => /^https?:\/\//i.test(url);

export default async function Team({ params }: Props) {
  const { teamId } = await params;
  const { team, posts, events } = await load(teamId);
  const name = team.name || "Team";
  const group = team.kind && team.kind !== "team";
  const privateGroup = team.kind === "community" && team.requiresApproval === true;
  const subtitle = listingSubtitle(team);

  return (
    <div className="page">
      <header className="profile-head">
        <Avatar name={name} size={84} />
        <div>
          <h1>{name}</h1>
          {subtitle && <p className="muted" style={{ margin: 0 }}>{subtitle}</p>}
          {team.location?.address && <p className="muted" style={{ margin: 0 }}>{team.location.address}</p>}
        </div>
        <FollowButton type="team" targetId={teamId} />
      </header>
      {team.description && <p className="bio">{team.description}</p>}

      <ForVisitors>
        <div className="cta-card">
          <p>{group ? "Join this group on Stall 10." : "Follow this team on Stall 10."}</p>
          <Link className="btn btn-primary btn-small" href={`/sign-up?next=${encodeURIComponent(`/teams/${teamId}`)}`}>
            {group ? "Sign up to join" : "Sign up to follow"}
          </Link>
        </div>
      </ForVisitors>

      {privateGroup ? (
        <p className="empty">Only members see this group&apos;s posts and events.</p>
      ) : (
        <>
          <h2 className="section-title">Upcoming</h2>
          {events.length === 0 ? (
            <p className="empty">Nothing scheduled.</p>
          ) : (
            <div className="stack">
              {events.map((e) => (
                <EventItem key={e.id} startsAt={e.startsAt}>
                  <b>{e.title || "Event"}</b>
                  <small>
                    <LocalTime iso={e.startsAt} style="dateTime" />
                    {e.location ? ` · ${e.location}` : ""}
                  </small>
                </EventItem>
              ))}
            </div>
          )}

          <h2 className="section-title">Posts</h2>
          {posts.length === 0 ? (
            <p className="empty">No public posts yet.</p>
          ) : (
            <div className="stack">
              {posts.map((p) => (
                <article key={p.id} className="post">
                  <header className="post-head">
                    <b>{p.title || p.authorName || name}</b>
                    <span className="post-time">
                      <LocalTime iso={p.createdAt} style="relative" />
                    </span>
                  </header>
                  {p.location && <p className="muted" style={{ margin: "4px 0 0" }}>{p.location}</p>}
                  {p.body && <p className="post-body">{p.body}</p>}
                  {p.images?.length ? (
                    <div className={`post-images n${Math.min(p.images.length, 4)}`}>
                      {p.images.slice(0, 4).map((img) => (
                        <a key={img.path} href={img.url} target="_blank" rel="noopener">
                          <img src={img.url} alt={img.name ?? ""} loading="lazy" />
                        </a>
                      ))}
                    </div>
                  ) : null}
                  {p.links?.some(isWebLink) ? (
                    <ul className="post-links">
                      {p.links.filter(isWebLink).map((l) => (
                        <li key={l}>
                          <a href={l} target="_blank" rel="noopener nofollow ugc">
                            {l.replace(/^https?:\/\//i, "")}
                          </a>
                        </li>
                      ))}
                    </ul>
                  ) : null}
                </article>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
