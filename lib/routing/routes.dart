import '../domain/models/schedule_entry.dart';
import '../domain/models/team_event.dart';

abstract final class Routes {
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const home = '/home';
  static const teams = '/teams';
  static const createTeam = '/teams/new';
  static const createGroup = '/teams/new?kind=community';
  static const searchTeams = '/teams/search';
  static const searchUsauTeams = '/teams/search/usau';
  static const schedule = '/schedule';
  static const tournaments = '/tournaments';
  static const rankings = '/rankings';
  static const profile = '/profile';

  /// Another player's profile.
  static String player(String uid) => '/players/$uid';

  /// Explore: find teams and groups, events and rankings; [query] fills
  /// the search.
  static String explore({String? query}) {
    final q = query?.trim() ?? '';
    return Uri(
      path: explorePath,
      queryParameters: q.isEmpty ? null : {'q': q},
    ).toString();
  }

  static const explorePath = '/explore';

  // The inbox is a shell tab; a conversation opened on its own (e.g. from a
  // notification or on a phone) opens over the shell, with `context.push`.
  static const messages = '/messages';
  static const newMessage = '/messages/new';
  static String conversation(String id) => '/messages/$id';

  // The notification feed and its settings, over the shell.
  static const notifications = '/notifications';
  static const notificationSettings = '/notifications/settings';

  /// The team's home page: a summary for members, the public page for
  /// everyone else.
  static String team(String teamId) => '/teams/$teamId';

  // Team sections (TeamSection) are tabs of the team page, shown in place.
  // The old `/teams/{id}/events`-style paths redirect here.
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
  // Chat pages open over the team; use `context.push` so back returns to
  // the chat room list.
  static String chatRoom(String teamId, String roomId) =>
      '/teams/$teamId/chats/$roomId';
  static String newChatRoom(String teamId) => '/teams/$teamId/chats/new';
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
  static String usauRoster(String teamId) => '/teams/$teamId/usau-roster';
  static String tournament(String id) => '/tournaments/$id';
  static const usauTeamPath = '/rankings/team';
  static String usauTeam(String url, {String name = ''}) =>
      _usauTeam(usauTeamPath, url, name);

  /// A USA Ultimate team page opened from Teams search, staying in the
  /// Teams tab so back returns to the results.
  static String searchedUsauTeam(String url, {String name = ''}) =>
      _usauTeam('$searchUsauTeams/team', url, name);

  static String _usauTeam(String path, String url, String name) => Uri(
    path: path,
    queryParameters: {'url': url, if (name.isNotEmpty) 'name': name},
  ).toString();
}
