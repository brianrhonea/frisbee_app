import type { Metadata } from "next";
import { LearnGuide } from "@/components/LearnGuide";

export const metadata: Metadata = {
  title: "Learn to play ultimate",
  description:
    "New to ultimate frisbee? The basic rules in five minutes: the field, the pull, the stall count, scoring, turnovers and spirit of the game.",
};

/** Public, and rendered on the server, so visitors and search engines read the whole guide. */
export default function Learn() {
  return (
    <div className="page learn">
      <div className="page-head">
        <p className="eyebrow">Learn to play</p>
        <h1>Ultimate in five minutes</h1>
        <p>
          Ultimate is a fast, non-contact team sport played with a flying disc. It mixes the running of soccer, the
          passing of football and the end zones of both, and players referee their own games.
        </p>
      </div>

      <LearnGuide />
    </div>
  );
}
