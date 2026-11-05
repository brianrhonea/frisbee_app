# Stall 10 release notes

What's new in each version, for testers and players. Newest first. The
developer log with data, rules and function changes is
[CHANGELOG.md](CHANGELOG.md).

Versions stay at `0.0.x` until the first App Store release. TestFlight
builds come from the `development` branch and use the test (dev)
Firebase project; App Store builds come from `main` and use production.

---

## 0.0.12 (in TestFlight from `development`)

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
