import type { PublicListing } from "@stall10/shared";
import Link from "next/link";
import { listingSubtitle } from "@/lib/site";
import { Avatar } from "./Avatar";

export function ListingCard({ team }: { team: PublicListing }) {
  return (
    <Link className="row-card" href={`/teams/${encodeURIComponent(team.id)}`}>
      <Avatar name={team.name} />
      <span>
        <b>{team.name || "Team"}</b>
        <small>{listingSubtitle(team)}</small>
      </span>
    </Link>
  );
}
