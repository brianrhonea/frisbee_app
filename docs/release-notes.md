# Stall 10 release notes

What's new in each version, for testers and players. Newest first. The
developer log with data, rules and function changes is
[CHANGELOG.md](CHANGELOG.md).

Versions stay at `0.0.x` until the first App Store release. TestFlight
builds come from the `development` branch and use the test (dev)
Firebase project; App Store builds come from `main` and use production.

---

## 0.0.40

**Schedule**
- Times open ready to type the hour and minutes; tap the clock to pick
  on the dial instead.
- Share any event in a message or email, right from the event.
- Make a shared calendar while adding an event: name it, pick people,
  done. No trip to Settings first.
- The Schedule tab has a Calendars button and a Calendars card for
  sharing, new calendars and Outlook, Apple or Google Calendar.

**Teams**
- Creating a club team explains what's wrong when it can't be created,
  instead of a permissions error.

---

## 0.0.39

**Chat**
- Double-tap a message to react: a bubble of reactions pops up above
  it. Tap + for any other emoji.

**Events**
- Changing your RSVP (Going, Maybe, Can't go) works straight away; no
  need to close the event and open it again.
- The RSVP choices look like buttons now.

---

## 0.0.38

**Teams**
- The Teams tab always shows your list of teams.
- Team pages show how many are going to the next event and how many
  chat rooms have new messages.
- The roster shows everyone's role and can be grouped into O-line and
  D-line. Admins see pending invites and can withdraw them.
- Pin up to 3 posts to the top of the team feed, and comment on team
  posts.
- Give someone a role in one tap (Captain, Coach, Admin…) or switch
  each permission on or off.
- Teams can let people ask to join; admins approve or decline.
- Community pages start with the next pickup: RSVP right on the card.

**Chat**
- Post a poll in a team chat room.

**Videos**
- Pin notes to a moment in a team video, clip a range, comment, and tag
  the video to a game.

**Tournaments**
- A bracket page of its own, bigger score buttons (− / +), leagues a
  week at a time, and a step-by-step host form with Save draft and
  Publish. Share a tournament's link.

**Calendar**
- "Add to calendar" opens your phone's calendar so you pick which
  calendar it goes in.

**Discord**
- When importing from Discord, pick which channels to bring.

## 0.0.37

**Live scores**
- Captains can keep a game's score as it's played. Everyone following
  the tournament sees it live on the game, the schedule and Discover.
  It's never the final score: that's still reported as before.

**Teams**
- New teams start simple: Feed, Schedule, Chat and Roster. The owner
  can turn on Playbook, Videos, Stats and Meetings in Settings ›
  Sections. Existing teams keep everything.
- Admins can make the team page private to outsiders with the "Public
  team page" switch in Settings › Visibility.
- Chat: pin important messages to the top of a room, and share an
  event into chat so people can RSVP right there.
- A team's Meetings page lists upcoming and past meetings.

**Playbook**
- New Whiteboard: sketch on a blank field with a pen, players, disc and
  cones, then save it or throw it away.

**Schedule**
- Add a short note to your RSVP, like "Late 15 min".
- A month view, with dots on days that have something on.

**Discover and more**
- Pickup games and public team events are listed in Discover.
- Tournaments show how many spots are left.
- The Learn guide shows how many lessons you've read.
- Download a copy of your data from Settings › Account.

## 0.0.36

**Find your way faster**
- The tabs are now Home, Discover, Schedule, Teams and Inbox.
  **Discover** is one place to find tournaments, leagues, pickup,
  teams, communities and players.
- If you're on one team, the Teams tab opens it straight away.
- Your feed has three tabs: Your teams, Following and Everyone.

**Every screen in the new look**
- Team pages have a compact header with the team's initials, and
  Invite and Message buttons up top.
- RSVP shows how many are going on each answer; events you haven't
  answered say "Needs RSVP".
- Tournament days open on the schedule, with live games in navy.
- Inbox shows team chats above direct messages.
- Settings are grouped into cards, with a Light / Dark / System switch.
- Delete and leave buttons are no longer red; red now only means a
  live game.

## 0.0.35

**A new look**
- New colours across the app, in light and dark mode: green for
  buttons and links, navy for anything live or happening today, and
  amber only for things that need you (report a score, RSVP, unread).
- Scores, dates and big numbers use a bold sports typeface.

## 0.0.34

**Tournaments up front**
- While your team has a tournament coming up, **Tournaments** gets its
  own tab on the team page, right after Chat, instead of sitting under
  More. On the day, it opens with your team's next game.

## 0.0.33

**Tournament day**
- When your team is playing a tournament, Home and the team page show
  its day at a glance: who you play next, when and on which field, your
  record and place in your pool, and your last result. The evening
  before, it shows tomorrow's first game.
- Captains get a **Report score** button there when a game has started
  without a score (or **Confirm score** when the other captain has
  reported). It opens that game on the tournament page, ready to enter.

## 0.0.32

**Every chat in Messages**
- Your teams' and communities' chats are now in the **Messages** tab,
  above your private messages. Each shows which rooms have something new
  ("New in #general") with a dot; tap it to jump straight into that room.
- The Messages badge counts team chats with something new, and a team's
  room list shows new rooms in bold with a dot.
- Rooms start showing as new from their next message.

## 0.0.31

**Stats by team**
- On a team or two with stats? Your profile's stats have a **Team** menu
  beside the season menu: pick one team to see just your numbers and
  seasons for it, or **All teams**. It works on other players' profiles
  too, and on the website.
- Per-team stats show only when you share both your stats and your teams
  (Settings → Privacy).

---

## 0.0.30

**Clearer names**
- Community groups are now called **pickup communities**, and the app
  says "community" for them and for schools and clubs everywhere. Group
  messages are still group messages.
- In a team's Stats, **Track a tournament** keeps stats for every game
  you play at one tournament (it used to say "New tournament", which was
  easy to mix up with hosting one).

**Inviting**
- The invite dialog has a **QR code** button: show it and people next to
  you join by pointing their phone's camera at it.

**Messages**
- Press and hold a message to see when it was sent.

---

## 0.0.29

**Privacy**
- If your profile is private, the photos on your posts, single posts and
  their comments are now locked down on the server, not only hidden in
  the app: only you and the people you've accepted can open them, like
  them or comment. (Feeds get the same lock in a later update.)
- Posts from private profiles can't be reposted.

---

## 0.0.28

**Works offline**
- Send a message, post or comment with no signal and it waits on your
  phone, then sends by itself as soon as you're back online, even if you
  closed the app in between. Nothing gets posted twice.
- A strip at the top says when you're offline and how many things are
  waiting. Tap it to see them, try one again or discard it.
- Messages that haven't gone out yet show in the chat as "Waiting to
  send". If the server turns one down (say you left the chat), it says
  "Not sent" and the rest still go.
- Likes, reactions, RSVPs and edits still need a connection.

**Posts**
- One "Photos +" button: tap it, then Take photo or Upload photos. Up
  to 4 photos a post, as before.

---

## 0.0.26

**Workouts**
- Every box in a workout now says what it's for above it (Minutes,
  Distance, Sets, Reps, Weight), with an example inside. Each exercise
  gets its own card.

**Messages**
- You can keep scrolling while you drag left to see message times.

**Notifications**
- Opening a notification from outside the app, then going back, now
  takes you to where that page belongs (a message → Messages, a post →
  Home), not to whatever you had open before.

---

## 0.0.25

**Messages**
- Swipe a message bubble to the right to reply. Swiping beside it no
  longer starts a reply.
- Drag the conversation to the left to see every message's time, like
  on iMessage. Let go and they slide away.

**Profiles**
- Opening someone's profile from Following, follow requests or a
  notification now has a back button that returns you there.

**Notifications**
- Notifications stay in the list after you open them. New ones are bold
  and larger; ones you've opened are lighter. Clear removes them.
- Follow requests are now at the top of Notifications, not in Settings.

---

## 0.0.24

**Keyboard**
- Tap anywhere outside a text box to close the keyboard. Send buttons in
  chats and comments still keep it open while you type.
- Closing the Send or Repost popup no longer opens the keyboard again.

**Sending posts**
- People who deleted their account no longer show up under Recent.

**Links**
- There's no Link button on posts any more: paste a link into your text
  and it shows as a link people can tap.

**Workouts**
- Adding a workout takes less room, and workouts in the feed are
  cleaner: the numbers stand out, with less clutter around them.

**Deleting your account**
- Your profile and header photos are deleted with it.

---

## 0.0.23

**The website, signed out**
- Without an account the website shows team and community pages and the
  community feed. Other tabs ask you to sign up or log in, then bring
  you back.

**Your birthday is remembered**
- After signing up with email, "About you" remembers your date of birth
  after the app restarts or on another device.

**Posting from Home**
- Tap the post box and type: Post sends it. Photo, Link and Workout open
  inside the same box instead of a popup, and "To" lets you post to a
  team you manage.

**Explore**
- The filters sit on one row that scrolls sideways.

**Rankings**
- Rankings have Level and Division filters, as on the website. Youth
  teams aren't ranked and players on youth teams aren't rated.

**Club teams are 16 and over**
- Club teams are now for players 16 and over. Add your date of birth in
  About you to join one. Anyone already on a club team stays on it.

**Youth teams**
- A youth team's roster is only for its members (and its school or
  club's admins). Others see "Rosters of youth teams are private: only
  members see them."
- The tournament form says the location and About are public.

**Signing up with Google or Apple**
- We now ask your first and last name along with your username, so your
  profile, posts and rosters show the name you choose, even if Apple hid
  it. "About you" starts from that name.

**The top bar**
- On phones the top bar shows just "Stall 10", as the website does,
  and notifications are a bell instead of the flying disc.

**Home**
- The Your teams tab shows your teams' posts.
- A strip of your teams sits under the composer, with New / Join.
- An empty feed shows a Get started checklist.
- A Needs you card lists join requests waiting for you.

**Inviting people**
- The invite dialog makes a link as soon as it opens, and again when
  you pick another length. It also lists join requests to approve or
  decline, and the people you've just invited.
- The Invite button shows how many join requests are waiting.

## 0.0.22

**A new icon**
- The app icon is now white with an indigo disc, matching the app's new
  colours. Same "10" with the flying disc.

## 0.0.21

**A new look, matching the website**
- The app uses the website's colours: indigo on a cool off-white, and
  "Midnight" in dark mode. The sidebar and top bar are light (or Midnight),
  the selected tab is indigo, and calls to action on indigo cards are amber.
- The sign-in screen's field and disc are in the new colours too.

**Tidier layouts**
- Photos in posts fill the width of the post (one photo at 4:3, more in
  two columns), so they no longer overflow narrow screens or leave a gap.
- Home's post buttons (Photo, Workout, Record, Team post) line up on the
  left when they wrap onto a second row.
- Settings → Account shows a long email under its label instead of
  squeezing the label.

## 0.0.20

**Fresh Home feed**
- Pull down on Home, or tap Home again, to load the newest posts.

**Calendars, like Outlook or Apple Calendar**
- In **Settings → Calendars**, make calendars (Training, Family…) with
  their own color, and invite friends, a coach or family as **Can view**
  or **Can edit**. They get an invite and see nothing until they accept.
  Change what someone can do, or remove them, any time.
- Invites show on your Schedule with **Accept** and **Decline**.
  Calendars you're on show there in their colors; pull down to refresh.
- **New event** lets you pick which calendar it goes on.
- **Add to calendar** on any event puts it in your phone's calendar app.
- Or subscribe: **Settings → Calendars → Subscribe in Apple Calendar or
  Outlook** (or Google Calendar) keeps every calendar you're on there,
  updated about once an hour. Viewers never see notes.

## 0.0.19

**Your details, kept private**
- Signing up now asks your date of birth. You need to be 13 or older.
- New players add their legal name, phone, gender and mailing address
  (and, under 18, a parent or guardian) to finish signing up, like a USA
  Ultimate membership.
- Only you can see these. They're encrypted and never shown on your
  profile or to teams. Change them in **Settings → Personal details**.
- Already have an account? You'll see a card on Home asking you to add
  them; you can skip it for now.

## 0.0.18 (in TestFlight from `development`)

**A tidier Teams tab**
- Your own teams come first. Schools, clubs and other communities come
  next, each with its teams tucked under it, so being in one doesn't fill
  the tab.
- One **+** button to join with a code, find a team, or start one.

**Team pages**
- Tabs, including **More**, now open right on the team page. The
  header folds up into a slim bar with the team's name, and the tabs stay
  just under it. Back takes you out of the team, not between tabs.
- Coaches and captains who also play can **Add yourself** to the roster
  in one tap (Roster → Players).

**Communities**
- A school or club's page has a **Teams** tab with all of its teams.
- Admins can invite people straight to any of its teams from there.

## 0.0.17

**Learn to play**
- New to ultimate? **Learn to play** walks through the rules in five
  minutes: the field, the stall count, turnovers, spirit of the game and
  the words you'll hear. Find it in **Explore** and in **Settings**.

## 0.0.16

**A simpler layout**
- Five tabs at the bottom: **Home**, **Explore**, **Events**, **Teams**
  and **Messages**.
- **Events** has your schedule and, under **Find events**, tournaments
  and leagues to join.
- Your **profile and settings** open from your picture at the top left.
- Every team and group page has the same five tabs: **Feed**,
  **Schedule**, **Chat**, **Roster** and **More**. Roster has the members
  and, on teams, the players; More has the playbook, videos, stats and
  tournaments.

## 0.0.15

**Leagues and hat tournaments**
- Teams, groups and schools/clubs can host a **league** or a **hat
  tournament** from **Host an event**: set the weeks, and let teams enter
  or players sign up on their own.
- Player sign-ups are split into teams by a **balanced draft** (from
  everyone's self-rating) or a **captains' live draft** you run together
  on your phones.
- Find leagues and tournaments in one place, filtered by type.
- Official events show a verified badge.

## 0.0.14

**Host a tournament**
- Any team, pickup group or school/club can host a tournament from its
  **Tournaments** section: dates, place, public or invite only, and an
  optional **bid fee** (teams pay you directly; you mark them paid).
- Add **divisions** (say Club Mixed and Club Open), each with its own
  team cap, format and game rules. **Suggest** picks a format for the
  number of teams.
- Team admins **apply** with their team and pick captains; hosts
  **invite** teams, then accept, waitlist or decline.
- **Seed** teams by dragging, **publish the schedule**, and captains
  report scores like in hat tournaments. The new **pool play + placement
  bracket** format gives every team a final place.
- Everyone can follow a tournament for its schedule, results and news.
  Find tournaments from **Explore → Find a tournament**.

**Removed**
- USA Ultimate events and rankings.

---

## 0.0.13 (in TestFlight from `development`)

**Notifications on iPhone**
- Fixed: notifications could fail to reach iPhones while the app was
  closed. Open **Notification settings** once after updating. If your
  phone still can't get notifications, that page now says why, with
  **Try again**.
- The notifications list is more compact, and its button is now a
  flying disc.

**Chat**
- The green **Send** button now shows on tablets and wide windows too.
- Older messages load as you scroll up.
- Sending lots of messages very fast pauses you for 10 minutes ("You're
  going too fast"). Normal chatting is never affected.

**Photos**
- Photos are shrunk before uploading, so they send faster and use less
  data. You can pick photos up to 50 MB.

**Home**
- Older posts load as you scroll, a page at a time.

---

## 0.0.12

**Schools and clubs**
- Make a **School or club** community (Teams → New → School or club) and
  put several teams in it, like a men's and a women's team.
- The community decides which roles get onto each team. Give someone
  "Woof Captain" and they're on Woof; take it away and they're off.
- Teams can ask to join a community, or the community can make a new
  team inside itself.
- Community events can be shown to just some roles (**Who sees it**).

**Discord import sorts rooms into teams**
- Importing a Discord server into a community puts each team's channels
  in that team's chat, and keeps shared channels in the community chat.
  You can change where any room goes before importing.
- Team versions of roles like Woof Captain follow the community, so
  captains-only rooms stay captains-only.
- If you imported before, those rooms move to their team (you're asked
  first, and their old messages go with the old room).

**Sign-in and privacy**
- Sign in with your **@username** or your email.
- **Private profile** (Settings → Privacy): people must ask to follow you,
  and only people you accept see your stats, teams and games. Answer in
  Settings → **Follow requests**.
- **Change password** in Settings → Account.

**Notifications**
- While the app is open, new messages and activity show as a small bubble
  at the top.
- If notifications are off on your phone, Settings tells you and offers
  to turn them on.

**Playbook**
- Players and the disc are easier to grab and drag with a finger.

---

## 0.0.11

**Usernames and a better sign-up**
- Everyone has a unique **@username**. Sign-up asks for your first and
  last name, a username (it tells you right away if it's taken), your
  email, and your password twice.
- If you sign up with Google or Apple, or had an account before
  usernames, the app asks you to pick one before you go any further.
- Your @username shows under your name on your profile, and people can
  find you by it in search and New message.
- Passwords need 8 or more characters with a letter and a number, and
  can't be a common password. A strength bar and checklist show as you
  type, and the eye button shows or hides what you typed.
- Sign-in and sign-up fit on the screen without scrolling.

**Settings**
- Settings is its own page now. Tap the **gear** at the top right of
  your profile and it slides in from the right (a side panel on wide
  screens).
- It's organised into **General** (light or dark theme), **Notifications**,
  **Privacy** (read receipts), **People you follow** and **Account**
  (display name, username, email, delete account), plus **Sign out**.

**Messages**
- **Read receipts**: your own message shows **Seen** once the other
  person has read it. Turn it off in Settings → Privacy; then you won't
  see theirs either.
- On phones, a conversation has a normal **back arrow** to Messages, and
  going back is one smooth slide.

**Notifications**
- The app asks once whether you want notifications, and again when you
  join a team ("Get notified about this team?") or follow someone
  ("Get notified when they post?").
- Fewer buttons: muting a chat room moved into the room's **⋮** menu,
  and a person's post notifications are in the **Following ▾** menu on
  their profile.

**Search**
- One search box on Home (phones) and at the top of every page (tablet
  and desktop) searches players, teams, groups and upcoming USA Ultimate
  events. Filter the results with chips.
- Every search box in the app looks and works the same, with a clear
  button.
- On a computer, **Ctrl K** (⌘K on a Mac) opens a command menu from
  anywhere: jump to a section or team, start a post or message, or search.
  **Ctrl 1–5** switch tabs.

**Roles**
- Teams have just **Owner** and **Player** built in. The owner creates
  any other roles (Coach, Captain, Stats…) and picks what each can do.
  Existing coaches and captains become custom roles automatically when
  the owner next opens the team, keeping what they could do.

**Polish**
- Deleting a post, comment or chat message happens right away with an
  **Undo** toast, instead of an "Are you sure?" pop-up.
- Grey placeholder rows show while pages load, instead of spinners, and
  photos fade in.
- Smoother page transitions, smooth rounded corners, drag handles on
  sheets you can swipe down, and numbers that don't jiggle as they change.
- Headlines wrap evenly, with no single word left on the last line.
- Phones stay in portrait, and the bottom bar shows every tab.

**Fixed**
- Messages from someone with the same name as another account could seem
  to go missing; usernames now tell people apart.

---

## 0.0.10

- **Comments** on posts, with notifications for the post's author.
- **Send** a post to someone as a direct message, copy its link or share
  it to other apps. Post links open in the app.
- **Custom roles** with permissions, Discord-style, and chat rooms that
  use them. Rooms live in folders you can drag to rearrange.
- **Import roles and channels from a Discord server template** link.
- **Voice channels** in team chat; members who can read but not post
  listen only.
- Discord-style message rows and composer.
- Faster back navigation, and swipe back on iPhone.
- TestFlight builds now use a separate test environment, so testing
  never touches real data.

## 0.0.9

- **Record runs, rides, walks and hikes with GPS**: a live map, time,
  distance and pace; keeps recording with the screen locked. The post
  shows the route and your splits, and hides your start and finish.
- New sign-in and sign-up screens with the thrown-disc animation.
- **Likes and reposts**, with notifications for likes, reposts and new
  followers (with **Follow back**).
- Share a team or personal event with your followers.
- Distances in miles or kilometres depending on where you are.

## 0.0.8

- **Follow** people, teams, groups and tournaments, with a bell for post
  notifications.
- The **Home feed**: your posts, your teams' and groups' posts, and
  everything you follow.
- Post updates with photos and links, or **workouts** with time,
  distance, effort and exercises.
- **Profiles** for every player.
- **Invite links** you can share anywhere, and invite codes that change
  every 30 seconds.
- The app is now called **Stall 10**, with a new logo. Team pages have
  tabs.

## 0.0.7

- **Community groups** for pickup: open or approval-only joining, a
  description and a map.
- **Pickup tournaments**: teams from RSVPs, round robin, pools and
  brackets over one or more days, with captain-reported scores.

## 0.0.6

- Team **Videos**: YouTube links or uploaded files, in folders.
- **Watch together** in meetings, in sync for everyone.

## 0.0.5

- Team **meetings** with video calls, screen share, in-call chat and
  per-person volume.
- Also: USA Ultimate schedules and brackets, team chat and direct
  messages, notifications, team home pages and posts, and stat undo.

## 0.0.4

- A new Home, your own personal schedule, and a Schedule tab with
  swipe-to-delete and Undo.
- Search USA Ultimate teams; light, dark or system theme.
- Paid and USA Ultimate status and the invite code are visible to team
  admins only.

## 0.0.3

- Import and sync your roster from your team's USA Ultimate page.

## 0.0.2

- Live **stats**: lines, O/D, pull timer, subs, timeouts and stat sheets.
- Team roles: owner, coach, captain and player.

## 0.0.1

- Team calendar with RSVPs, reactions and polls.
- Animated plays in the playbook.

## 0.0.0

- Sign in with email, Google or Apple; teams, roster and invite codes;
  the playbook; USA Ultimate tournaments and rankings.
