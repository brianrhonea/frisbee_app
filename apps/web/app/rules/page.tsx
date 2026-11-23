import type { Metadata } from "next";
import Link from "next/link";
import { officialRules, rulesGuide } from "@stall10/shared";
import { GuidePoints } from "@/components/Guides";

export const metadata: Metadata = {
  title: "Rules of ultimate",
  description:
    "How ultimate is played: Spirit of the Game, the pull, the stall count, scoring, fouls, picks and more, with links to the official USA Ultimate and WFDF rules.",
};

/** Public and rendered on the server, like Learn (the app's RulesScreen). */
export default function Rules() {
  return (
    <div className="page learn">
      <div className="page-head">
        <p className="eyebrow">Rules</p>
        <h1>The rules of ultimate</h1>
        <p>
          A plain-language guide to how ultimate is played. For anything it leaves out, or if a call is in doubt, the
          official rules decide.
        </p>
      </div>

      <section className="card guide-official" aria-label="Official rules">
        <h2 className="card-title">Official rules</h2>
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
      </section>

      <nav className="card learn-toc" aria-label="On this page">
        <ol>
          {rulesGuide.map((s, i) => (
            <li key={s.id}>
              <a href={`#${s.id}`}>
                <span className="learn-num">{i + 1}</span>
                {s.title}
              </a>
            </li>
          ))}
        </ol>
      </nav>

      <article className="learn-body">
        {rulesGuide.map((s) => (
          <section key={s.id} id={s.id}>
            <h2>{s.title}</h2>
            <GuidePoints section={s} />
          </section>
        ))}
        <p className="muted small">
          This guide is Stall 10&apos;s summary, not an official rule book. Events can change things like game length and
          timeouts. New to ultimate? <Link href="/learn">Learn to play in five minutes</Link>.
        </p>
      </article>
    </div>
  );
}
