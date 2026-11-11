import '../domain/models/schedule_entry.dart';
import '../domain/models/team_event.dart';

abstract final class Routes {
  // The website's own pages (web_router.dart). The rest of its paths are
  // the app's, so links work in both.

  /// Everyone's newest public posts; where signed-out visitors land.
  static const community = '/community';

  /// Public team events and group tournaments still to come.
  static const upcomingEvents = '/events';

  /// Download links for the apps.
  static const getTheApp = '/get-the-app';

  static const signIn = '/sign-in';
  static const signUp = '/sign-up';

  /// Picking a username, before anything else (see
  /// AuthRepository.needsUsername).
  static const chooseUsername = '/welcome/username';
  static const home = '/home';
  static const teams = '/teams';
  static const createTeam = '/teams/new';
  static const createGroup = '/teams/new?kind=community';
  static const createCommunity = '/teams/new?kind=organization';
  static const searchTeams = '/teams/search';
  static const schedule = '/schedule';
  static const profile = '/profile';

  /// Settings, sliding over the page; its sections open from it.
  static const settings = '/settings';
  static const settingsGeneral = '/settings/general';
  static const settingsPrivacy = '/settings/privacy';
  static const followRequests = '/settings/follow-requests';

  /// What the user follows, from Settings (sliding over it, so back
  /// returns there). [following] is the same list from the profile.
  static const settingsFollowing = '/settings/following';
  static const settingsAccount = '/settings/account';

  /// Another player's profile.
  static String player(String uid) => '/players/$uid';

  /// Another player's profile over a page outside the tabs (a chat), with
  /// `context.push`, so back returns to it.
  static String personOver(String uid) => '/people/$uid';

  /// Explore, the app-wide search: players, teams and groups. [query] fills the search; [only] picks a filter.
  static String explore({String? query, ExploreFilter? only}) {
    final q = query?.trim() ?? '';
    final params = {'q': ?(q.isEmpty ? null : q), 'only': ?only?.name};
    return Uri(
      path: explorePath,
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  static const explorePath = '/explore';

  /// Stall 10's team rankings; [key] ("club-mixed") picks the division.
  static const rankingsPath = '/rankings';
  static String rankings([String? key]) => Uri(
    path: rankingsPath,
    queryParameters: key == null ? null : {'d': key},
  ).toString();

  /// Everything the user follows, with each bell.
  static const following = '/profile/following';

  // People's posts open over the shell; use `context.push`. The composer
  // is an overlay: see `showPostComposer`.
  static const postsPath = '/posts';

  /// Records a run or ride with GPS, over the shell; use `context.push`.
  static const recordWorkout = '/record';

  /// A post's page; [comment] puts the cursor in the comment box.
  static String post(String id, {bool comment = false}) =>
      '$postsPath/$id${comment ? '?comment=1' : ''}';

  // The inbox is a shell tab; a conversation opened on its own (e.g. from a
  // notification or on a phone) opens over the shell, with `context.push`.
  static const messages = '/messages';
  static const newMessage = '/messages/new';
  static const newGroup = '/messages/new-group';

  /// Adds people to group [id].
  static String addToGroup(String id) => '/messages/new-group?to=$id';
  static String conversation(String id) => '/messages/$id';

  // The notification feed and its settings, over the shell.
  static const notifications = '/notifications';
  static const notificationSettings = '/notifications/settings';

  /// The team's home page: a summary for members, the public page for
  /// everyone else.
  static String team(String teamId) => '/teams/$teamId';

  // Team sections (TeamSection) are tabs of the team page, shown in place.
  // The old `/teams/{id}/events`-style paths redirect here.
  /// A team or group's page over a full-screen page outside the tabs (a
  /// tournament), with `context.push`, so it slides in and back returns
  /// there; `/teams/:id` would switch to the Teams tab instead.
  static const teamsOverPath = '/over/teams';
  static String teamOver(String teamId) => '$teamsOverPath/$teamId';

  /// [location] (a `/teams/...` page) as its [teamOver] equivalent.
  static String asTeamOver(String location) => location.startsWith('$teams/')
      ? '$teamsOverPath${location.substring(teams.length)}'
      : location;

  static String teamSection(String teamId, String section) =>
      '/teams/$teamId?section=$section';
  static String teamEvents(String teamId) => teamSection(teamId, 'events');
  static String teamChat(String teamId) => teamSection(teamId, 'chat');
  static String teamRoster(String teamId) => teamSection(teamId, 'roster');
  static String teamPlaybook(String teamId) => teamSection(teamId, 'playbook');
  static String teamStats(String teamId) => teamSection(teamId, 'stats');
  static String teamMembers(String teamId) => teamSection(teamId, 'members');
  static String teamVideos(String teamId) => teamSection(teamId, 'videos');
  static String newPlay(String teamId) => '/teams/$teamId/plays/new';

  /// The owner's custom roles.
  static String teamRoles(String teamId) => '/teams/$teamId/roles';

  /// Imports roles and channels from a Discord server template.
  static String discordImport(String teamId) => '/teams/$teamId/discord';
  // Chat pages open over the team; use `context.push` so back returns to
  // the chat room list.
  static String chatRoom(String teamId, String roomId) =>
      '/teams/$teamId/chats/$roomId';
  static String newChatRoom(String teamId, {String? folderId}) =>
      '/teams/$teamId/chats/new${folderId == null ? '' : '?folder=$folderId'}';
  static String chatRoomSettings(String teamId, String roomId) =>
      '/teams/$teamId/chats/$roomId/settings';
  static String play(String teamId, String playId) =>
      '/teams/$teamId/plays/$playId';
  // Event pages sit outside the tab shell so they open over whatever tab
  // they're pushed from, and back returns there. Open them with
  // `context.push`, not `go`.
  static const teamEventsPath = '/team-events';
  static String newEvent(String teamId, {DateTime? day}) => Uri(
    path: '$teamEventsPath/$teamId/new',
    queryParameters: day == null
        ? null
        : {'date': day.toIso8601String().substring(0, 10)},
  ).toString();
  static String event(String teamId, String eventId) =>
      '$teamEventsPath/$teamId/$eventId';
  static String editEvent(String teamId, String eventId) =>
      '$teamEventsPath/$teamId/$eventId/edit';

  static String teamTournaments(String teamId) =>
      teamSection(teamId, 'tournaments');

  // Hosted tournaments (any team, group or school/club hosts them) open
  // full screen over the tabs. The list finds upcoming ones.
  static const tournaments = '/tournaments';

  /// [host] (a group id) opens that group's hat tournament [id] instead
  /// if there's no hosted tournament [id].
  static String tournament(String id, {String? host}) =>
      '$tournaments/$id${host == null ? '' : '?host=${Uri.encodeQueryComponent(host)}'}';

  /// Pick which group or club hosts a new tournament, hat tournament or
  /// league.
  static const hostEvent = '/tournaments/host';
  static String newTournament(String hostId) =>
      '$tournaments/new?host=${Uri.encodeQueryComponent(hostId)}';
  static String editTournament(String id) => '$tournaments/$id/edit';

  /// The host turns a division's signed-up players into teams.
  static String tournamentDraft(String id, String divisionId) =>
      '$tournaments/$id/draft/$divisionId';

  /// The captains' live draft for a division.
  static String tournamentLiveDraft(String id, String divisionId) =>
      '$tournaments/$id/live-draft/$divisionId';

  // Community group tournament pages open over the tabs, like video pages;
  // use `context.push`.
  static const groupTournamentsPath = '/group-tournaments';

  /// [eventId] links the new tournament to that Tournament event.
  static String newGroupTournament(String groupId, {String? eventId}) =>
      '$groupTournamentsPath/$groupId/new'
      '${eventId == null ? '' : '?event=${Uri.encodeQueryComponent(eventId)}'}';
  static String groupTournament(String groupId, String tournamentId) =>
      '$groupTournamentsPath/$groupId/$tournamentId';
  static String editGroupTournament(String groupId, String tournamentId) =>
      '$groupTournamentsPath/$groupId/$tournamentId/edit';

  // Video pages open over the tabs, like event pages; use `context.push`.
  static const teamVideosPath = '/team-videos';

  /// [folderId] starts the new video in that folder.
  static String newVideo(String teamId, {String? folderId}) =>
      '$teamVideosPath/$teamId/new'
      '${folderId == null ? '' : '?folder=${Uri.encodeQueryComponent(folderId)}'}';
  static String video(String teamId, String videoId) =>
      '$teamVideosPath/$teamId/$videoId';
  static String editVideo(String teamId, String videoId) =>
      '$teamVideosPath/$teamId/$videoId/edit';

  // Team meetings, over the shell like events; use `context.push`.
  static const teamMeetingsPath = '/team-meetings';
  static String newMeeting(String teamId, {DateTime? day}) => Uri(
    path: '$teamMeetingsPath/$teamId/new',
    queryParameters: day == null
        ? null
        : {'date': day.toIso8601String().substring(0, 10)},
  ).toString();
  static String meeting(String teamId, String meetingId) =>
      '$teamMeetingsPath/$teamId/$meetingId';
  static String editMeeting(String teamId, String meetingId) =>
      '$teamMeetingsPath/$teamId/$meetingId/edit';

  /// The lobby and, once joined, the call.
  static String meetingRoom(String teamId, String meetingId) =>
      '$teamMeetingsPath/$teamId/$meetingId/room';

  /// Detail page for a team schedule entry: an event or a meeting.
  static String teamEvent(String teamId, TeamEvent e) =>
      e.type == EventType.meeting ? meeting(teamId, e.id) : event(teamId, e.id);

  // Personal schedule.
  static const myEventsPath = '/my-events';
  static String newMyEvent({DateTime? day}) => Uri(
    path: '$myEventsPath/new',
    queryParameters: day == null
        ? null
        : {'date': day.toIso8601String().substring(0, 10)},
  ).toString();
  static String myEvent(String eventId) => '$myEventsPath/$eventId';
  static String editMyEvent(String eventId) => '$myEventsPath/$eventId/edit';

  /// Detail page for a team or personal event.
  static String scheduleEvent(ScheduleEntry e) => switch (e.team) {
    final team? => teamEvent(team.id, e.event),
    null => myEvent(e.event.id),
  };
  static String statsTournament(String teamId, String tournamentId) =>
      '/teams/$teamId/stats/tournaments/$tournamentId';
  static String statsGame(String teamId, String gameId) =>
      '/teams/$teamId/stats/games/$gameId';
  static String seasonStats(String teamId) => '/teams/$teamId/stats/season';
}

/// Explore's result filters.
enum ExploreFilter { teams, groups, players, tournaments }
