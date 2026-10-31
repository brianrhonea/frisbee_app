import '../domain/models/schedule_entry.dart';

abstract final class Routes {
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const home = '/home';
  static const teams = '/teams';
  static const createTeam = '/teams/new';
  static const searchUsauTeams = '/teams/search';
  static const schedule = '/schedule';
  static const tournaments = '/tournaments';
  static const rankings = '/rankings';
  static const profile = '/profile';

  // Direct messages open over the shell; use `context.push`.
  static const messages = '/messages';
  static const newMessage = '/messages/new';
  static String conversation(String id) => '/messages/$id';

  /// [tab] opens a team tab by name, e.g. 'playbook' ([TeamTab]).
  static String team(String teamId, {String? tab}) => Uri(
    path: '/teams/$teamId',
    queryParameters: tab == null ? null : {'tab': tab},
  ).toString();
  static String newPlay(String teamId) => '/teams/$teamId/plays/new';
  // Chat pages open over the team; use `context.push` so back returns to
  // the Chat tab.
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
    final team? => event(team.id, e.event.id),
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
