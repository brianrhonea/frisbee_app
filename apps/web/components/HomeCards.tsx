import Link from "next/link";
import { NavIcon } from "./NavIcons";

/** "The field is calling": to Explore, for pickup and teams nearby. */
export function PickupCard() {
  return (
    <Link className="card pickup-card" href="/explore">
      <span>
        <small>The field is calling</small>
        <b>Find your next pickup game</b>
      </span>
      <NavIcon name="external" size={18} />
    </Link>
  );
}

/** The indigo card to Learn. */
export function LearnPromo({ label = "Level up your game" }: { label?: string }) {
  return (
    <div className="card promo-card">
      <small>{label}</small>
      <b>Your next great throw starts here.</b>
      <p>The rules, the field and the spirit of the game, in five minutes.</p>
      <Link className="btn btn-amber btn-small" href="/learn">
        Learn to play <NavIcon name="external" size={14} />
      </Link>
    </div>
  );
}

/** "Good people. Great ultimate." The sidebar's (and phones' home's) about card. */
export function BrandCard() {
  return (
    <Link className="brand-card" href="/about">
      <b>Good people. Great ultimate.</b>
      <small>A community built on spirit, on and off the field.</small>
      <span>
        About Stall 10 <NavIcon name="external" size={13} />
      </span>
    </Link>
  );
}
