import type { Metadata } from "next";
import Link from "next/link";
import { helpTopics } from "@stall10/shared";
import { GuidePoints } from "@/components/Guides";

export const metadata: Metadata = { title: "Help" };

const supportEmail = "support@stall10.app";

/** Help in Settings: common questions (guides.ts, as the app's HelpScreen), then more help. */
export default function HelpSettingsPage() {
  return (
    <div className="stack guide-help">
      <h2>How can we help?</h2>
      <p className="muted">Answers to the things people ask about most.</p>
      <div className="card help-topics">
        {helpTopics.map((s) => (
          <details key={s.id} id={s.id}>
            <summary>{s.title}</summary>
            <div className="help-answer">
              <GuidePoints section={s} />
            </div>
          </details>
        ))}
      </div>
      <h3>More help</h3>
      <ul className="help-more">
        <li>
          <Link href="/rules">Rules of ultimate</Link> <small className="muted">How the game is played</small>
        </li>
        <li>
          <Link href="/learn">Learn to play</Link> <small className="muted">Ultimate in five minutes</small>
        </li>
        <li>
          <a href={`mailto:${supportEmail}`}>Contact support</a> <small className="muted">{supportEmail}</small>
        </li>
      </ul>
    </div>
  );
}
