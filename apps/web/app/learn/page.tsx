import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Learn to play ultimate",
  description:
    "New to ultimate frisbee? The basic rules in five minutes: the field, the pull, the stall count, scoring, turnovers and spirit of the game.",
};

// A beginner's summary in our own words, not an official rule book; keep it
// that way (no copied rule text). Reviewed by: [pending].

const sections = [
  ["basics", "The basics"],
  ["field", "The field"],
  ["pull", "Starting a point"],
  ["moving", "Moving the disc"],
  ["stall", "The stall count"],
  ["scoring", "Scoring and winning"],
  ["turnovers", "Turnovers"],
  ["defense", "Defense"],
  ["spirit", "Fouls and spirit of the game"],
  ["divisions", "Divisions and mixed"],
  ["words", "Words you'll hear"],
  ["start", "Getting started"],
] as const;

const glossary: Array<[string, string]> = [
  ["Handler", "A player who mostly throws, setting up the offense near the disc."],
  ["Cutter", "A player who runs to get open for passes, often down the field."],
  ["Mark / marker", "The defender guarding the thrower, who also counts the stall."],
  ["Force", "Which side the marker lets the thrower throw to, so the rest of the defense knows where passes will go."],
  ["Stack", "An offensive setup where cutters line up so they can run into open space one after another."],
  ["Huck", "A long throw down the field."],
  ["Layout", "A full-stretch dive to catch or block the disc."],
  ["Hammer", "An overhead throw that flips and floats over defenders."],
  ["Callahan", "Catching an interception in the end zone you're defending: an instant point for the defense."],
  ["Pick", "When a defender is blocked from following their player by someone else. Play stops so they can catch up."],
  ["Brick", "When the pull lands out of bounds, the offense may start from a spot partway down the field."],
  ["Line", "The seven players on the field for a point."],
];

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

      <nav className="card learn-toc" aria-label="On this page">
        <ol>
          {sections.map(([id, label]) => (
            <li key={id}>
              <a href={`#${id}`}>{label}</a>
            </li>
          ))}
        </ol>
      </nav>

      <article className="learn-body">
        <section id="basics">
          <h2>The basics</h2>
          <p>
            Two teams of seven try to score by catching the disc in the end zone they&apos;re attacking. You can&apos;t
            run while holding the disc: you move it by passing. If a pass isn&apos;t caught, the other team takes over
            where it landed and attacks the other way.
          </p>
          <ul>
            <li>Seven players a side, outdoors (smaller formats like 5-a-side are common indoors and on the beach).</li>
            <li>No running with the disc, and no contact.</li>
            <li>Any incomplete pass is a turnover.</li>
            <li>No referees in most games: players make and settle their own calls.</li>
          </ul>
        </section>

        <section id="field">
          <h2>The field</h2>
          <p>
            A rectangle about the size of a soccer field, with an end zone at each end. A typical outdoor field is
            about 70 yards long and 40 wide between the end zones, with end zones 20 to 25 yards deep. Exact sizes
            depend on the rules your league plays by, and pickup fields are often smaller.
          </p>
        </section>

        <section id="pull">
          <h2>Starting a point</h2>
          <p>
            Each point starts with both teams standing on their own end zone lines. The defending team throws the disc
            the length of the field to the other team: this is the <b>pull</b>, like a kickoff. The receiving team
            picks it up and starts attacking.
          </p>
          <p>Teams switch directions after every point, and the team that just scored pulls next.</p>
        </section>

        <section id="moving">
          <h2>Moving the disc</h2>
          <p>
            Once you catch the disc you have to stop as quickly as you safely can. You may then <b>pivot</b>: keep one
            foot planted and step around it with the other to find a throwing lane, like in basketball.
          </p>
          <p>
            You can throw to any teammate in any direction: forward, sideways or backward. Most teams move the disc
            with short passes near the thrower and longer throws to cutters down the field.
          </p>
        </section>

        <section id="stall">
          <h2>The stall count</h2>
          <p>
            The defender guarding the thrower counts out loud: &ldquo;stalling one, two, three…&rdquo; up to ten. If
            the disc hasn&apos;t left the thrower&apos;s hand by ten, it&apos;s a turnover. That&apos;s where Stall 10
            gets its name.
          </p>
          <p>The count keeps play moving: nobody can hold the disc and wait for the perfect throw.</p>
        </section>

        <section id="scoring">
          <h2>Scoring and winning</h2>
          <p>
            A point is scored when a player catches the disc in the end zone they&apos;re attacking, with both feet
            (or whatever touches the ground first) in the end zone.
          </p>
          <p>
            Games are usually played to 15 or 13 points, often with a time cap and a halftime when one team reaches
            half the target. Many leagues ask a team to win by two, up to a cap.
          </p>
        </section>

        <section id="turnovers">
          <h2>Turnovers</h2>
          <p>Possession switches to the other team when:</p>
          <ul>
            <li>a pass hits the ground or is dropped,</li>
            <li>a defender knocks the disc down (a <b>block</b> or <b>D</b>) or catches it (an interception),</li>
            <li>the disc is caught or lands out of bounds, or</li>
            <li>the thrower is stalled out.</li>
          </ul>
          <p>
            After a turnover the new offense picks up the disc where it stopped (or where it went out of bounds) and
            attacks the opposite end zone. There&apos;s no break in play.
          </p>
        </section>

        <section id="defense">
          <h2>Defense</h2>
          <p>
            Defenders guard players and try to block or intercept passes. Only one defender may guard the thrower, and
            they must leave the thrower room to pivot and throw: no contact, no wrapping their arms around the
            thrower, and no standing right on top of them.
          </p>
          <p>
            Defenders often <b>force</b> the thrower to one side, which makes passes more predictable for the rest of
            the team. Teams also play zone defenses, where players guard areas of the field instead of people.
          </p>
        </section>

        <section id="spirit">
          <h2>Fouls and spirit of the game</h2>
          <p>
            Ultimate is non-contact. When contact affects a play, the player fouled calls &ldquo;foul&rdquo; and play
            stops. The players involved talk it over: if they agree, they go with it; if they can&apos;t, the disc
            usually goes back to the last uncontested thrower and play starts again.
          </p>
          <p>
            This works because of <b>spirit of the game</b>: playing hard but fairly, knowing the rules, staying calm
            and respectful, and never winning by cheating or intimidation. Many tournaments score each team&apos;s
            spirit after every game. At higher levels, observers may help settle disputes, but players still make
            the calls.
          </p>
        </section>

        <section id="divisions">
          <h2>Divisions and mixed</h2>
          <p>
            Competitive ultimate is usually split into <b>open</b>, <b>women&apos;s</b> and <b>mixed</b> divisions,
            with club, college, youth, masters and recreational league levels.
          </p>
          <p>
            In mixed games, each team plays a set ratio of men and women on every point (for example four and three),
            and the rules say which team chooses the ratio for each point.
          </p>
        </section>

        <section id="words">
          <h2>Words you&apos;ll hear</h2>
          <dl className="glossary">
            {glossary.map(([term, meaning]) => (
              <div key={term}>
                <dt>{term}</dt>
                <dd>{meaning}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section id="start">
          <h2>Getting started</h2>
          <ul>
            <li>
              <b>Gear:</b> cleats, a light and a dark shirt (teams often split by color), water, and a regulation
              175-gram disc if you want to practice throwing.
            </li>
            <li>
              <b>Learn two throws:</b> the backhand (the classic frisbee throw) and the forehand or
              &ldquo;flick&rdquo;. You&apos;ll pick up the rest by playing.
            </li>
            <li>
              <b>Find a game:</b> pickup and league groups welcome beginners.{" "}
              <Link href="/explore">Search for groups and teams near you</Link>, or{" "}
              <Link href="/events">see what&apos;s coming up</Link>.
            </li>
          </ul>
          <p className="muted small">
            This is a beginner&apos;s summary, not an official rule book. Leagues and tournaments play by full rule
            sets (such as USA Ultimate&apos;s or WFDF&apos;s) that differ in the details. Check which rules your game
            uses.
          </p>
        </section>
      </article>

      <div className="cta-card">
        <p>Ready to play? Join Stall 10 to find pickup and keep up with your team.</p>
        <Link className="btn btn-primary btn-small" href="/sign-up">
          Sign up free
        </Link>
      </div>
    </div>
  );
}
