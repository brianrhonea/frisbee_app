// Stall 10's own guides, the same in the app and on the website: a fuller
// guide to the rules of ultimate (our own words, not an official rule book;
// it links to the official rules) and Help for the app. Keep in step with
// packages/shared/src/guides.ts; test/shared_fixtures/guide_fixtures_test.dart
// writes fixtures/guides, which checks both.
// Reviewed by: [pending].

class GuideSection {
  const GuideSection({
    required this.id,
    required this.title,
    this.intro,
    required this.points,
  });

  final String id;
  final String title;
  final String? intro;
  final List<String> points;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'intro': ?intro,
    'points': points,
  };
}

class GuideLink {
  const GuideLink({required this.label, required this.url, required this.note});

  final String label;
  final String url;
  final String note;

  Map<String, Object?> toMap() => {'label': label, 'url': url, 'note': note};
}

/// The official rule books the Rules screen sends people to.
const officialRules = [
  GuideLink(
    label: 'USA Ultimate rules',
    url: 'https://usaultimate.org/rules/',
    note: 'The official rules for play in the United States.',
  ),
  GuideLink(
    label: 'WFDF rules',
    url: 'https://rules.wfdf.org/',
    note:
        'The World Flying Disc Federation\'s rules, used at international events.',
  ),
];

/// The rules of ultimate, on Learn to play (Routes.learnRules; /learn#rules on the website).
const rulesGuide = [
  GuideSection(
    id: 'spirit',
    title: 'Spirit of the Game',
    intro:
        'Ultimate trusts the players. There are no referees in most games: you make and settle your own calls, and you\'re expected to play hard and fair.',
    points: [
      'Know the rules, and don\'t break them on purpose, even to stop a score.',
      'Call what you see honestly, and listen to the other side before deciding.',
      'Avoid dangerous play: no reckless contact, and watch where you dive.',
      'Be respectful in words and actions. After a game, teams often meet in a spirit circle to talk about how it went.',
      'Many events score each opponent\'s spirit and give a spirit award.',
    ],
  ),
  GuideSection(
    id: 'field',
    title: 'The field and the teams',
    intro: 'Each team has seven players on the field at once.',
    points: [
      'A full field is a rectangle with an end zone at each end. Each team attacks one end zone and defends the other.',
      'The lines themselves are out of bounds, including the sidelines and the back of the end zones.',
      'Mixed (co-ed) games set how many players of each gender are on the field for each point, usually four of one and three of the other.',
      'Players can change between points, and during a point only for an injury or illness.',
    ],
  ),
  GuideSection(
    id: 'pull',
    title: 'Starting a point: the pull',
    intro: 'Every point starts with a throw-off called the pull.',
    points: [
      'Both teams line up on their own end zone lines. The defense pulls the disc to the offense, usually as far as it can.',
      'The team that just scored pulls next, so the teams swap ends after each point.',
      'Defenders can\'t cross their line until the disc is released.',
      'If the pull lands out of bounds, the offense can play it where it went out, or call "brick" and start from the brick mark: the middle of the field, a set distance from the end zone it defends.',
    ],
  ),
  GuideSection(
    id: 'moving',
    title: 'Moving the disc',
    intro: 'You can\'t run with the disc. It moves only by passing.',
    points: [
      'Once you catch it, slow down as fast as you safely can and set a pivot foot. Keep that foot in place while you throw: you may step in any direction with the other foot.',
      'Moving your pivot foot before you release the disc is a travel. Play stops and the thrower sets up again where they should have been.',
      'You can throw in any direction, any way you like, but you can\'t hand the disc to a teammate: it has to be in the air between you.',
      'You can\'t catch your own throw unless someone else touches it first.',
    ],
  ),
  GuideSection(
    id: 'stall',
    title: 'The stall count',
    intro:
        'The defender guarding the thrower, the marker, counts out loud to give the thrower time to throw.',
    points: [
      'The marker says "stalling" and counts from one to ten, about a second apart.',
      'If the disc hasn\'t left the thrower\'s hand when the marker starts to say "ten", it\'s a turnover.',
      'Only one defender may guard the thrower. A second defender close to the thrower who isn\'t guarding someone else is a double team.',
      'Counting too fast, a double team, or a straddle (standing over the pivot) are violations: the marker starts the count again, lower.',
    ],
  ),
  GuideSection(
    id: 'scoring',
    title: 'Scoring',
    intro:
        'A team scores when a player catches the disc in the end zone it\'s attacking.',
    points: [
      'The catcher\'s first touch of the ground after the catch must be in the end zone, not on the line.',
      'A defender who intercepts a pass in the end zone they\'re defending scores right away (a Callahan).',
      'Games are often played to 15 points, or 13, and must be won by two, with a points cap and a time cap. Halftime comes when one team reaches half the target, such as 8 in a game to 15.',
      'The exact targets and caps differ from event to event: check your tournament or league.',
    ],
  ),
  GuideSection(
    id: 'turnovers',
    title: 'Turnovers',
    intro: 'The other team takes over the disc when a pass isn\'t completed.',
    points: [
      'A pass that hits the ground, is caught out of bounds, is knocked down or is intercepted is a turnover.',
      'A stall count reaching ten is a turnover.',
      'The new offense starts where the disc stopped, or where it went out of bounds.',
      'If the disc stops in the end zone the new offense is defending, they can walk it to the goal line or play it from there.',
    ],
  ),
  GuideSection(
    id: 'bounds',
    title: 'In and out of bounds',
    points: [
      'A player is out of bounds when any part of them touches the ground outside the field, including the lines.',
      'A catch counts if the player\'s first contact with the ground after catching it is in bounds. A player landing out can\'t catch it in.',
      'A disc that goes out is brought back in where it last crossed the line.',
      'The disc itself is in until it touches the ground, or a player, out of bounds: it can curve outside the lines in the air and come back in.',
    ],
  ),
  GuideSection(
    id: 'fouls',
    title: 'Fouls and calls',
    intro:
        'Ultimate is non-contact. When contact affects a play, the player who was fouled calls it.',
    points: [
      'Call "foul" when someone\'s contact affects your play: a defender hitting the thrower, two players colliding for the disc, a strip that knocks it out of the thrower\'s hand.',
      'If the other player agrees, the play is replayed or the fouled player gets the disc, depending on what happened.',
      'If they disagree, they say "contest", and the disc usually goes back to the thrower to try again.',
      'Talk it out briefly and calmly. If you can\'t agree, send the disc back and play on.',
      'Other calls stop play too: "travel", "pick", "strip", "double team", "fast count" and "in" or "out".',
    ],
  ),
  GuideSection(
    id: 'picks',
    title: 'Picks',
    points: [
      'A pick is when another player gets in the way of a defender who\'s following the player they guard.',
      'The defender calls "pick" and everyone stops. The defender catches up to their player, and play starts again.',
      'Offenses shouldn\'t set picks on purpose. Cutters spread out and run around groups of players to avoid them.',
    ],
  ),
  GuideSection(
    id: 'timeouts',
    title: 'Timeouts, injuries and restarts',
    points: [
      'Each team usually gets a few timeouts per game or half; your event\'s rules give the number and length.',
      'Anyone can stop play for an injury. The injured player can be replaced, and play restarts as it was.',
      'After any stoppage, play restarts with a check: the defender touches the disc, or says "disc in", to put it back in play.',
      'Teams can also stop for a dangerous situation, like someone wandering onto the field.',
    ],
  ),
  GuideSection(
    id: 'observers',
    title: 'Observers',
    points: [
      'At many high-level games, observers help with calls. They rule on lines and some disputes when players ask, and keep time.',
      'Even with observers, players make most calls themselves, and Spirit of the Game still comes first.',
    ],
  ),
];

/// Help in Settings (Routes.settingsHelp; /settings/help on the website).
const helpTopics = [
  GuideSection(
    id: 'start',
    title: 'Getting started',
    points: [
      'Sign in with Google, Apple or email. New accounts pick a username, agree to the Community Guidelines and add their details.',
      'Fill in your profile in Settings → Profile so teammates know who you are.',
      'Find teams, pickup groups and events from Explore, or join with an invite your team sends you.',
    ],
  ),
  GuideSection(
    id: 'join',
    title: 'Joining a team or community',
    points: [
      'Open the invite link a captain sends you, or scan their QR code. You join as a player.',
      'Or search for the team (Explore, or 🔍 on the Teams tab), tap Join and type the code an admin shows you on the team\'s Members page.',
      'Private groups ask an admin to accept you. Club teams need you to be 16 or older, with your date of birth in Personal details.',
    ],
  ),
  GuideSection(
    id: 'create',
    title: 'Making a team or community',
    points: [
      'Teams → New: pick a team, a pickup community, or a school or club.',
      'Teams pick a division and level. Communities don\'t; teams made inside a school or club pick their own level.',
      'Invite people from the team\'s Invite button: share a link, show a QR code, or search for someone on Stall 10.',
    ],
  ),
  GuideSection(
    id: 'notifications',
    title: 'Not getting notifications',
    points: [
      'Check that Stall 10\'s notifications are allowed in your phone\'s settings.',
      'In Settings → Notifications, make sure the kind you want (chat, events, posts…) is on, for every team or just one.',
      'A muted room or conversation sends nothing, except when someone @mentions you by name or role. Press and hold it to unmute.',
      'Notifications go to the phones you\'ve signed in on. Signing out and in again re-registers your phone.',
    ],
  ),
  GuideSection(
    id: 'chats',
    title: 'Chats and messages',
    points: [
      'The Chats tab has your teams\' chats at the top and your private messages below. Tap a heading to fold that list away.',
      'Press and hold a message to react, reply, copy, pin or delete it. Press and hold a room to mute it.',
      'Type @ to mention a teammate. Owners, coaches, captains and chat managers can also mention a role or @everyone.',
      'Messages from people you don\'t follow wait under Requests until you accept.',
    ],
  ),
  GuideSection(
    id: 'events',
    title: 'Events and RSVPs',
    points: [
      'Your team\'s Schedule tab lists its events. Open one to answer Going, Maybe or Can\'t go.',
      'Admins add events, repeat them weekly and choose who sees them.',
      'Settings → Calendars adds your events to your phone\'s or computer\'s calendar.',
    ],
  ),
  GuideSection(
    id: 'tournaments',
    title: 'Tournaments and leagues',
    points: [
      'Find one in Events → Find events. A team\'s owner or captain applies with the team; players sign up alone when the event takes players.',
      'Hosts set who can enter: teams, players, or (for leagues) both. Players who sign up alone are drafted onto teams.',
      'Captains report scores from the tournament page or the card on Home on the day.',
    ],
  ),
  GuideSection(
    id: 'fees',
    title: 'Fees and payments',
    points: [
      'When a host takes payments online, Pay online opens a secure Stripe checkout. Otherwise, pay the host their way; they mark you paid.',
      'If you paid your whole team\'s fee, use Split a team fee on the team\'s page to set each teammate\'s share and how to pay you.',
      'Refunds and disputes go to whoever you paid; Stall 10 doesn\'t hold your money.',
    ],
  ),
  GuideSection(
    id: 'safety',
    title: 'Safety, blocking and reporting',
    points: [
      'Report a post, message or profile from its menu. Stall 10 staff and the team\'s admins review reports.',
      'Blocking someone hides them from you and you from them. Manage blocks in Settings → Blocked accounts.',
      'Settings → Privacy controls who sees your profile and whether others see when you\'ve read their messages.',
    ],
  ),
  GuideSection(
    id: 'offline',
    title: 'Using Stall 10 offline',
    points: [
      'Messages and posts you send without a connection wait and go out when you\'re back online.',
      'Anything still waiting shows as Waiting to send. You can retry or delete it.',
    ],
  ),
  GuideSection(
    id: 'account',
    title: 'Your account and data',
    points: [
      'Change your name, username, email or password in Settings → Account.',
      'Delete your account in Settings → Account → Delete account. It removes your profile, posts and messages.',
      'Still stuck? Email support@stall10.app and we\'ll help.',
    ],
  ),
];
