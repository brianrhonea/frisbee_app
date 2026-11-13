// The beginner's guide to ultimate, in our own words, not an official rule
// book; keep it that way (no copied rule text). Keep it in step with the
// website's /learn (apps/web/app/learn/page.tsx).

/// One part of a [LearnSection]: a paragraph, a bulleted list, or terms
/// and meanings. `**bold**` marks words to emphasize.
sealed class LearnBlock {
  const LearnBlock();
}

class LearnText extends LearnBlock {
  const LearnText(this.text);
  final String text;
}

class LearnBullets extends LearnBlock {
  const LearnBullets(this.items);
  final List<String> items;
}

class LearnGlossary extends LearnBlock {
  const LearnGlossary(this.terms);
  final List<(String, String)> terms;
}

class LearnSection {
  const LearnSection(this.title, this.blocks);
  final String title;
  final List<LearnBlock> blocks;
}

const learnIntro =
    'Ultimate is a fast, non-contact team sport played with a flying disc. '
    'It mixes the running of soccer, the passing of football and the end '
    'zones of both, and players referee their own games.';

const learnSections = <LearnSection>[
  LearnSection('The basics', [
    LearnText(
      "Two teams of seven try to score by catching the disc in the end zone "
      "they're attacking. You can't run while holding the disc: you move it "
      "by passing. If a pass isn't caught, the other team takes over where it "
      'landed and attacks the other way.',
    ),
    LearnBullets([
      'Seven players a side, outdoors (smaller formats like 5-a-side are '
          'common indoors and on the beach).',
      'No running with the disc, and no contact.',
      'Any incomplete pass is a turnover.',
      'No referees in most games: players make and settle their own calls.',
    ]),
  ]),
  LearnSection('The field', [
    LearnText(
      'A rectangle about the size of a soccer field, with an end zone at '
      'each end. A typical outdoor field is about 70 yards long and 40 wide '
      'between the end zones, with end zones 20 to 25 yards deep. Exact '
      'sizes depend on the rules your league plays by, and pickup fields are '
      'often smaller.',
    ),
  ]),
  LearnSection('Starting a point', [
    LearnText(
      'Each point starts with both teams standing on their own end zone '
      'lines. The defending team throws the disc the length of the field to '
      'the other team: this is the **pull**, like a kickoff. The receiving '
      'team picks it up and starts attacking.',
    ),
    LearnText(
      'Teams switch directions after every point, and the team that just '
      'scored pulls next.',
    ),
  ]),
  LearnSection('Moving the disc', [
    LearnText(
      'Once you catch the disc you have to stop as quickly as you safely '
      'can. You may then **pivot**: keep one foot planted and step around it '
      'with the other to find a throwing lane, like in basketball.',
    ),
    LearnText(
      'You can throw to any teammate in any direction: forward, sideways or '
      'backward. Most teams move the disc with short passes near the thrower '
      'and longer throws to cutters down the field.',
    ),
  ]),
  LearnSection('The stall count', [
    LearnText(
      'The defender guarding the thrower counts out loud: "stalling one, '
      'two, three…" up to ten. If the disc hasn\'t left the thrower\'s hand '
      "by ten, it's a turnover. That's where Stall 10 gets its name.",
    ),
    LearnText(
      'The count keeps play moving: nobody can hold the disc and wait for '
      'the perfect throw.',
    ),
  ]),
  LearnSection('Scoring and winning', [
    LearnText(
      "A point is scored when a player catches the disc in the end zone "
      "they're attacking, with both feet (or whatever touches the ground "
      'first) in the end zone.',
    ),
    LearnText(
      'Games are usually played to 15 or 13 points, often with a time cap '
      'and a halftime when one team reaches half the target. Many leagues '
      'ask a team to win by two, up to a cap.',
    ),
  ]),
  LearnSection('Turnovers', [
    LearnText('Possession switches to the other team when:'),
    LearnBullets([
      'a pass hits the ground or is dropped,',
      'a defender knocks the disc down (a **block** or **D**) or catches it '
          '(an interception),',
      'the disc is caught or lands out of bounds, or',
      'the thrower is stalled out.',
    ]),
    LearnText(
      'After a turnover the new offense picks up the disc where it stopped '
      '(or where it went out of bounds) and attacks the opposite end zone. '
      "There's no break in play.",
    ),
  ]),
  LearnSection('Defense', [
    LearnText(
      'Defenders guard players and try to block or intercept passes. Only '
      'one defender may guard the thrower, and they must leave the thrower '
      'room to pivot and throw: no contact, no wrapping their arms around '
      'the thrower, and no standing right on top of them.',
    ),
    LearnText(
      'Defenders often **force** the thrower to one side, which makes passes '
      'more predictable for the rest of the team. Teams also play zone '
      'defenses, where players guard areas of the field instead of people.',
    ),
  ]),
  LearnSection('Fouls and spirit of the game', [
    LearnText(
      'Ultimate is non-contact. When contact affects a play, the player '
      'fouled calls "foul" and play stops. The players involved talk it '
      "over: if they agree, they go with it; if they can't, the disc usually "
      'goes back to the last uncontested thrower and play starts again.',
    ),
    LearnText(
      'This works because of **spirit of the game**: playing hard but '
      'fairly, knowing the rules, staying calm and respectful, and never '
      "winning by cheating or intimidation. Many tournaments score each "
      "team's spirit after every game. At higher levels, observers may help "
      'settle disputes, but players still make the calls.',
    ),
  ]),
  LearnSection('Divisions and mixed', [
    LearnText(
      "Competitive ultimate is usually split into **open**, **women's** and "
      '**mixed** divisions, with club, college, youth, masters and '
      'recreational league levels.',
    ),
    LearnText(
      'In mixed games, each team plays a set ratio of men and women on '
      'every point (for example four and three), and the rules say which '
      'team chooses the ratio for each point.',
    ),
  ]),
  LearnSection("Words you'll hear", [
    LearnGlossary([
      (
        'Handler',
        'A player who mostly throws, setting up the offense near the disc.',
      ),
      (
        'Cutter',
        'A player who runs to get open for passes, often down the '
            'field.',
      ),
      (
        'Mark / marker',
        'The defender guarding the thrower, who also counts the stall.',
      ),
      (
        'Force',
        'Which side the marker lets the thrower throw to, so the rest of the '
            'defense knows where passes will go.',
      ),
      (
        'Stack',
        'An offensive setup where cutters line up so they can run into open '
            'space one after another.',
      ),
      ('Huck', 'A long throw down the field.'),
      ('Layout', 'A full-stretch dive to catch or block the disc.'),
      ('Hammer', 'An overhead throw that flips and floats over defenders.'),
      (
        'Callahan',
        "Catching an interception in the end zone you're defending: an "
            'instant point for the defense.',
      ),
      (
        'Pick',
        'When a defender is blocked from following their player by someone '
            'else. Play stops so they can catch up.',
      ),
      (
        'Brick',
        'When the pull lands out of bounds, the offense may start from a '
            'spot partway down the field.',
      ),
      ('Line', 'The seven players on the field for a point.'),
    ]),
  ]),
  LearnSection('Getting started', [
    LearnBullets([
      '**Gear:** cleats, a light and a dark shirt (teams often split by '
          'color), water, and a regulation 175-gram disc if you want to '
          'practice throwing.',
      '**Learn two throws:** the backhand (the classic frisbee throw) and '
          'the forehand or "flick". You\'ll pick up the rest by playing.',
      '**Find a game:** pickup and league groups welcome beginners. Search '
          'Explore for groups and teams near you, or see what\'s coming up '
          'in Events.',
    ]),
  ]),
];

/// The note under the guide.
const learnDisclaimer =
    "This is a beginner's summary, not an official rule book. Leagues and "
    "tournaments play by full rule sets (such as USA Ultimate's or WFDF's) "
    'that differ in the details. Check which rules your game uses.';
