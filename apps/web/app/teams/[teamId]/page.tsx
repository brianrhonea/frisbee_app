import { TeamFeed } from "@/components/team/TeamFeed";
import { loadTeam } from "@/lib/teamPage";

type Props = { params: Promise<{ teamId: string }> };

/** The hub's Feed: the team's posts, with what's coming up beside them. */
export default async function TeamFeedPage({ params }: Props) {
  const { posts, events } = await loadTeam((await params).teamId);
  return <TeamFeed publicPosts={posts} publicEvents={events} />;
}
