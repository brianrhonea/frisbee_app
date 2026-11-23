import type { Metadata } from "next";
import { officialRules, rulesGuide } from "@stall10/shared";
import { GuidePoints } from "@/components/Guides";
import { LearnGuide } from "@/components/LearnGuide";

export const metadata: Metadata = {
  title: "Learn to play ultimate",
  description:
    "New to ultimate frisbee? The basics in five minutes, then the rules of ultimate: the pull, the stall count, scoring, fouls, picks and spirit of the game, with links to the official USA Ultimate and WFDF rules.",
};

/**
 * Learn to play: the lessons, then the rules of ultimate (rulesGuide, each
 * opening in place; the app's LearnScreen). Public, and rendered on the
 * server, so visitors and search engines read the whole guide. /rules
 * redirects to #rules.
 */
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

      <section id="rules" className="learn-rules" aria-labelledby="rules-title">
        <p className="eyebrow">The rules</p>
        <h2 id="rules-title">The rules of ultimate</h2>
        <p className="learn-rules-intro">
          A plain-language guide to how ultimate is played. For anything it leaves out, or if a call is in doubt, the
          official rules decide.
        </p>

        <div className="card guide-official">
          <h3 className="card-title">Official rules</h3>
          <ul>
            {officialRules.map((l) => (
              <li key={l.url}>
                <a href={l.url} target="_blank" rel="noopener noreferrer">
                  {l.label} ↗
                </a>
                <small className="muted">{l.note}</small>
              </li>
            ))}
          </ul>
        </div>

        <div className="card rules-list">
          {rulesGuide.map((s) => (
            <details key={s.id} id={`rule-${s.id}`}>
              <summary>{s.title}</summary>
              <div className="rules-answer">
                <GuidePoints section={s} />
              </div>
            </details>
          ))}
        </div>
        <p className="muted small">
          This guide is Stall 10&apos;s summary, not an official rule book. Events can change things like game length
          and timeouts.
        </p>
      </section>
    </div>
  );
}
