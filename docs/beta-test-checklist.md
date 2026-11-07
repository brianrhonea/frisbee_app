# Stall 10 beta test checklist

Two parts: **mobile setup and limits** (do once per device or build), then
**features** (every use case, by area). Tick each box on iPhone and on
Android where both apply. Use at least **two accounts** (A and B) on
separate devices. Where a check needs a third person, that's account C.

Note each failure with: device, account, steps, and what you saw. A
screenshot or screen recording helps.

---

## Part 1 — Mobile setup, devices and limits

### 1.1 Before the first TestFlight build

- [ ] Apple Developer enrollment approved.
- [ ] App created in App Store Connect; its numeric **Apple ID** replaces
      the `0000000000` placeholder (`APP_STORE_APPLE_ID` in
      `codemagic.yaml`). Builds stop early until this is done.
- [ ] App Store Connect API key added to Codemagic (integration, not the
      repo).
- [ ] **APNs auth key** (`.p8`) uploaded to Firebase → Project settings →
      Cloud Messaging. Without it iOS gets no push.
- [ ] `frisbee_secrets` group in Codemagic has every key in
      `secrets.example.json`, plus the iOS Google Sign-In IDs.
- [ ] Push to `development` → Codemagic builds → build shows in TestFlight.
- [ ] Testers added to the TestFlight group (internal first, then external
      with a beta review).
- [ ] Android: a signed release APK or internal-testing track on Play
      Console (faster than iOS review for quick checks).

### 1.2 Firebase and backend

- [ ] **Cloud Storage** bucket set up and `storage.rules` deployed (photos,
      profile pictures, video uploads).
- [ ] `firestore.rules` and `firestore.indexes.json` deployed (done for
      0.0.9; re-check after any change).
- [ ] Function groups deployed: `notifications`, `meetings`, `account`,
      `follows`.
- [ ] LiveKit secrets set (`LIVEKIT_URL`, `LIVEKIT_API_KEY`,
      `LIVEKIT_API_SECRET`).
- [ ] Firebase Hosting serves the invite-link page (`hosting/`), and the
      iOS Associated Domains / Android App Links verify, so links open the
      app.
- [ ] **Budget alerts** on the Google Cloud billing account (e.g. $5,
      $20, $50).
- [ ] Map tiles: switch off the public OpenStreetMap tile server (its
      policy forbids app traffic at scale) to a provider with a key
      before external testers.

### 1.3 Install, permissions and device behavior (each device)

- [ ] Fresh install from TestFlight / APK opens without a red screen.
- [ ] App name **Stall 10** and the disc logo on the home screen.
- [ ] Notification permission prompt appears; allowing it registers the
      device (push arrives later in 2.13).
- [ ] Deny notifications → app still works; in-app Notifications list
      still fills.
- [ ] Location permission asked only when you first **Record**.
      "While using" works; background recording works with the screen
      locked (iOS: allow location in background; Android: the
      persistent notification shows).
- [ ] Deny location → Record explains why and doesn't crash.
- [ ] Camera / photo library prompts when adding a photo or video.
- [ ] Microphone / camera prompts on joining a meeting.
- [ ] Rotate the phone on each main tab: nothing overflows (yellow-black
      stripes) or clips.
- [ ] Small phone (e.g. iPhone SE) and large phone: text fits, buttons
      reachable, keyboard doesn't cover the field you're typing in.
- [ ] Dark mode, light mode, system (Profile → theme).
- [ ] Larger system text size: labels wrap, nothing clipped.
- [ ] Reduce Motion on: the sign-in animation is skipped.
- [ ] Airplane mode: cached screens still show; actions fail with a
      message, not a crash; going back online catches up.
- [ ] Background the app for 10+ minutes, return: still signed in, data
      refreshes.
- [ ] Kill the app and relaunch: still signed in.
- [ ] Tapping a push notification with the app killed, backgrounded and
      open each lands on the right page.

### 1.4 Usage and API limits (watch during the test)

Check daily in the Firebase console (Usage and billing) and Google Cloud
console, and note numbers per active tester.

- [ ] **Firestore reads** per user per day. The home feed, follows,
      notifications and team listeners are the big ones. Flag anything
      over a few thousand reads per user per day.
- [ ] Firestore writes and deletes (likes, RSVPs, stats, chat).
- [ ] **Cloud Functions invocations**: `postLiked` runs on every post
      update, `userPost` on every post, `newFollower` on every follow.
      Check errors and cold-start time in the logs.
- [ ] FCM: messages sent vs delivered; no duplicate pushes.
- [ ] **Storage**: GB stored and downloaded (photos, video uploads up to
      500 MB each, 5 GB per team).
- [ ] **LiveKit** participant minutes per meeting.
- [ ] Nominatim (address search) and map tile requests aren't throttled.
- [ ] YouTube oEmbed checks for added video links succeed.
- [ ] Battery and data use for a 30-minute GPS recording.
- [ ] Crashes: check TestFlight crash reports and Play Console vitals.

---

## Part 2 — Feature checklist

### 2.1 Sign in, sign up and account

- [ ] The sign-in animation plays once per launch (disc thrown, stall
      counts 1–9, caught as the "0"); tap the field to replay it.
- [ ] Sign up with first and last name, username, email, password and
      confirmation; bad email, mismatched or weak password show errors.
- [ ] Username: a taken one says so as you type; `pa`, `pat lee`, `.pat`
      and `admin` are refused; the account gets the one you picked.
- [ ] Password strength bar and checklist update as you type; the eye
      shows and hides it.
- [ ] Google / Apple sign-up (and an older account) is asked to **pick a
      username** before Home; invite links still finish joining after.
- [ ] Sign-in and sign-up fit the screen without scrolling (smallest
      phone you have).
- [ ] Sign in with email; wrong password shows an error.
- [ ] Sign in with **Google** (iOS and Android).
- [ ] Sign in with **Apple** (iOS; on Android if offered).
- [ ] After sign-in or sign-up you land on **Community**.
- [ ] Sign out, then sign in as another account: no data from the first
      account shows.
- [ ] Profile shows **@username** under the name (yours and others').
- [ ] The **gear** on your profile slides Settings in; General, Privacy,
      Account and Notifications slide in over it, and back slides them
      away. On a wide screen it's a side panel; clicking outside closes it.
- [ ] Settings → Account: change display name; it shows on posts, the
      roster and chat.
- [ ] App version shows at the bottom of Settings and matches the build.
- [ ] **Delete account**: confirms first. Then the user's posts, follows
      and personal events are gone, their teams handle the departure,
      and they can sign up again with the same email.

### 2.2 Teams

- [ ] Create a team; you're its Owner.
- [ ] Team page tabs: Home, Team Events, Chat, Roster, Playbook, Videos,
      Stats, Members. Switching tabs changes only the content; back leaves
      the team.
- [ ] Find a team in Teams search (filter All / Teams / Groups).
- [ ] **Join by code**: admin taps **Show code** (changes every 30 s); B
      enters it within 45 s → joins. An expired code fails clearly.
- [ ] **Invite link**: pick 1 hour / 1 day / 7 days / 30 days; copy and
      **Share** to Messages or WhatsApp. B taps it:
  - [ ] with the app installed → Join screen naming the team;
  - [ ] signed out → sign in, then back to the Join screen;
  - [ ] without the app → hosting page with **Open in Stall 10**;
  - [ ] after it expires → a clear "expired" message.
- [ ] Inviting someone found by search sends them the link as a DM.
- [ ] Roles: Owner sets Coach / Captain / Player; stats access add-on for
      players; Owner transfers ownership.
- [ ] Coaches and captains can show codes and make links; players can't.
- [ ] Players see only names, numbers and positions on the roster; Paid
      only for owner, coach and captain.
- [ ] Leave a team (non-owner). Remove a member (admin).
- [ ] Delete a team: confirms, then its events, meetings, videos, folders
      and posts go; members no longer see it.

### 2.3 Roster

- [ ] Add, edit and remove players by hand.
- [ ] Paid mark, paid count, **Unpaid only** filter.
- [ ] No USA Ultimate import, sync, events or rankings anywhere.

### 2.4 Community groups and pickup tournaments

- [ ] Create a group; tabs are Home, Events, Chat, Tournaments, Members.
- [ ] Set a description and location (address search, fine-tune on the
      map); Home shows the map and **Directions** opens Maps.
- [ ] B **Joins** an open group. Turn on **Approve new members** → C
      **Asks to join** → organizer approves; another request is declined.
- [ ] Group invite link (`/g/…`) opens the group page.
- [ ] Roles: Owner, Organizer, Member.
- [ ] Pickup event with Attending / Planning to attend / Not able to make
      it RSVPs.
- [ ] Create a tournament: format (round robin, pool play + single elim,
      single elim, double elim), 3v3–7v7, game length, breaks, cap,
      timeouts, fields, ideal end time.
- [ ] Multi-day tournament splits games across days and warns past the
      ideal end time.
- [ ] Add players from RSVPs and by hand; **Assign teams** deals them
      evenly with a random captain; rename teams.
- [ ] Publish the schedule; the tournament page shows schedule, pool
      standings, bracket, teams and "You're on…".
- [ ] Captain **reports** a score; other captain **confirms**, or reports
      a different score; organizer corrects a score.
- [ ] Confirmed results move teams on in the bracket; seeding from pools
      works; the double-elim if-needed final appears only when needed.
- [ ] Someone outside the tournament sees the public summary with
      **Follow**.

### 2.5 Schedule, events, RSVPs and polls

- [ ] Schedule tab: one week at a time, All / Team / Personal filters,
      blue team events and purple personal events.
- [ ] **Add event** from **Coming up** on Home: asks which schedule
      (personal or a team you admin), then opens over the page.
- [ ] Add event from the Schedule tab and from a team's Team Events
      (**New → Event**).
- [ ] Each type: practice, game, tournament, social, workout, scrimmage,
      pickup.
- [ ] Close the editor with changes → "Discard this event?"; with no
      changes it just closes. The Android back gesture does the same.
- [ ] Save → snackbar **View** opens the event.
- [ ] **Share with followers** (new events, not private groups): with and
      without a note → the post appears on your profile and followers'
      feeds; a shared **team** event also appears for every team member.
- [ ] Edit and delete an event (admin); players can't.
- [ ] Swipe to delete on Schedule with a 4-second **Undo**.
- [ ] RSVP Going / Maybe / Can't go; no-reply list; emoji reactions;
      single- and multi-choice polls; only members who are going can
      react or vote.
- [ ] Public events show on the public team page (globe icon).
- [ ] Past events: **Show past events** on Team Events.

### 2.6 Meetings (LiveKit)

- [ ] Admin schedules a meeting for chosen roles and/or people, with and
      without "Require admin approval to join".
- [ ] Only invitees see it on their schedule.
- [ ] Attending / Not attending RSVP.
- [ ] Lobby: pick mic, speaker and camera; camera preview; volume.
- [ ] Admin starts (even early); others join; with approval on, admin
      admits or denies.
- [ ] Video, profile photo when the camera is off, speaking highlight,
      in-call chat, mute, camera, sound and leave.
- [ ] Per-person volume (0–200%) and mute, just for you.
- [ ] Screen share (Android; iOS if supported).
- [ ] **Watch together**: admin picks a team video; it plays in sync for
      everyone; play, pause and seek follow; another admin takes control;
      Stop returns to the call.
- [ ] Admin ends the meeting for everyone.
- [ ] Notifications for invite, cancellation and start; the in-app
      **Join** banner.
- [ ] Phone call or switching apps mid-meeting, then return.

### 2.7 Playbook

- [ ] Create a play on the field editor; draw, move and delete players
      and the disc.
- [ ] Record animation steps (drag cuts, drag throws); play back with
      scrubbing, speed and captions.
- [ ] Leave the editor mid-edit: no error.
- [ ] Players can view; only admins edit.

### 2.8 Videos

- [ ] Add a YouTube link: thumbnail and title fill in; private or
      non-embeddable videos warn.
- [ ] Upload a video file with a progress bar; the 500 MB and team space
      limits are enforced; admins see space used.
- [ ] Play YouTube and uploaded videos in the app.
- [ ] Folders: create, rename, delete (videos move to Unsorted); filter
      chips; **Move to folder**.
- [ ] Edit title and description; remove a video.

### 2.9 Stats

- [ ] Tournaments as folders of games; create and delete each.
- [ ] Live game: lines of 7, O/D tracking, pull timer, subs, timeouts,
      point log.
- [ ] Undo history.
- [ ] Stat sheets (O efficiency, break rate, ratings, glossary); season
      stats.
- [ ] Only owner, coach, captain and players granted stats access can
      record.

### 2.10 Chat and messages

- [ ] Team chat rooms: send, receive in real time on the other device.
- [ ] Direct messages: start one from a profile's **Message** or people
      search.
- [ ] Links are tappable; Stall 10 links open in the app.
- [ ] New message notifications (push and in-app).
- [ ] **Seen** shows under your last DM once the other person reads it.
      With Read receipts off (Settings → Privacy) on either side, neither
      sees it.
- [ ] Phone: back from a conversation slides cleanly to Messages.
- [ ] Delete a message: it goes at once with **Undo**; Undo brings it
      back; otherwise it's gone on the other device after ~5 s.
- [ ] Room ⋮ → **Mute notifications** stops that room's pushes.

### 2.11 Follows, profiles and the home feed

- [ ] **Follow** a person, team, group and group tournament; the
      follower count changes.
- [ ] Bell on → that one's new posts notify you; bell off → they don't.
- [ ] **Following** list (Profile → Following): bells and Unfollow work.
- [ ] Profile (`/people/:uid`): name, photo, followers / following
      counts, Follow, Message, their posts. Opens from a post's author,
      Members, and **View profile** in search.
- [ ] Home feed has: your posts, all posts from your teams and groups,
      public posts from followed teams, posts by people you follow, posts
      tagged with followed tournaments, and shared team events from your
      teams. Newest first; **Show older posts**.
- [ ] Unfollow → their posts leave the feed.

### 2.12 Posts, workouts and GPS

- [ ] Text post; up to 4 photos; up to 5 links; tag a tournament or event
      you follow. Over the limits is blocked.
- [ ] Edit and delete your post (photos removed too).
- [ ] Team post (admin) on the team Home.
- [ ] Manual workout: each type (run, sprints, throwing, gym, agility,
      mobility, ride, walk, hike), time, distance with pace for runs,
      effort 1–10, up to 20 exercises with sets, reps and weight.
- [ ] Units: miles in the US/UK, km elsewhere (change the phone's
      region to check).
- [ ] **Record** (Home and Profile): run, ride, walk, hike. Live map,
      time, distance, average and current pace (speed for rides).
- [ ] Pause, Resume, Finish, Discard (confirms).
- [ ] Recording keeps going with the screen locked and while using other
      tabs; the Record button shows the clock.
- [ ] Finish → composer pre-filled with time, distance and route.
- [ ] **Hide your start and finish** on: the first and last 200 m are cut
      from the map; stats unchanged. Off: the full route.
- [ ] The post shows the route map; opening it shows splits per mile/km
      and elevation gain.
- [ ] A very short recording (under 200 m) and a long one (30+ min).

### 2.13 Likes, reposts and social notifications

- [ ] A likes B's post → heart fills, count goes up; tap again to unlike.
- [ ] Like from the feed, the post page and a profile.
- [ ] A reposts B's post with and without a note → the repost shows A's
      note over B's live post, on A's profile and A's followers' feeds.
- [ ] You can't repost your own post (button disabled).
- [ ] Repost the same post twice → still one. Tap **Reposted** → "Undo
      your repost?" → removed and the count drops.
- [ ] Liking or reposting a repost acts on the original.
- [ ] B edits the original → the repost shows the edit. B deletes it →
      "This post is no longer available."
- [ ] B gets a notification: "A liked your post" (several likes fold into
      "N new likes"), "A reposted your post".
- [ ] A follows B → B gets "A started following you" with **Follow back**;
      tapping it turns into **Following** and marks it read.
- [ ] Settings → turn off **Likes, reposts and followers** → none of
      those arrive.
- [ ] Unliking and re-liking doesn't spam notifications.
- [ ] **Comment** under a post opens its page with the cursor in the box;
      post a comment → it shows with your name and the count goes up on
      the feed.
- [ ] Comment on a repost → it lands on the original.
- [ ] Delete your own comment; as the post's author, delete someone
      else's; you can't delete others' comments on someone else's post.
- [ ] The post's author gets "X commented on your post"; several fold
      into "N new comments".
- [ ] Deleting a post removes its comments.
- [ ] **Send** under a post: recent people listed first; search finds
      anyone; **Send** → **Sent**; the other person gets a DM whose link
      opens the post.
- [ ] **Copy link** and **Share to other apps**; the link opened on a
      phone with the app goes straight to the post; without the app it
      shows the Open in Stall 10 page.

### 2.14 Notifications

- [ ] Push arrives on iOS and Android for each category: team posts,
      events, plays, chat / DMs, meetings, invites and join requests,
      posts you follow, likes / reposts / followers.
- [ ] Each push opens the right page (app open, backgrounded, killed).
- [ ] In-app list: unread badge, open marks read, **Mark all read**,
      **Clear all**.
- [ ] Notification settings: each category on/off is respected.
- [ ] First sign-in offers notifications once; **Not now** doesn't ask
      again. Joining a team and following someone each offer theirs.
- [ ] Opening several notifications in a row doesn't break navigation.

### 2.15 Home, navigation and layout

- [ ] Home on phones: This week, your team (or the join / create card),
      Coming up, then the feed.
- [ ] Every bottom tab opens and keeps its scroll and state when you
      come back.
- [ ] From a post's own page, tapping the author or team switches to
      their tab (no red screen).
- [ ] Back gesture / button everywhere returns where you came from; no
      dead ends.
- [ ] Deep links: `/join/…`, `/g/…`, `/posts/…`, `/people/…` from
      outside the app.
- [ ] Pull to refresh where offered.
- [ ] Phones stay portrait when rotated; tablets still rotate.
- [ ] Home search (phones) / top-bar search: a player, @username, team,
      and group are all found; chips filter them.
- [ ] Computer: **Ctrl K** opens the command menu from any page (also
      after using it, and inside a text box); **Ctrl 1–5** switch tabs,
      also with the menu open.
- [ ] Loading shows grey placeholder rows, not spinners; photos fade in.
- [ ] Roles: an owner opening an older team turns coaches and captains
      into Coach and Captain roles, with the same access.

### 2.16 Security and privacy spot checks

- [ ] B (not on the team) can't see the team's roster status, chat,
      playbook, videos, stats or private events.
- [ ] Private tournament teams are hidden from outsiders.
- [ ] Personal events are visible only to their owner.
- [ ] Meetings are visible only to invitees.
- [ ] A player can't edit events, roles or the roster.

---

## After testing

- [ ] File each issue (one per bug) with device, account and steps.
- [ ] Fix, then re-run the affected sections on both platforms.
- [ ] Feature freeze; bump to **0.1.0**; merge `development` → `main`;
      external TestFlight beta.
