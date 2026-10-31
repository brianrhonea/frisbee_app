abstract final class Routes {
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const home = '/home';
  static const teams = '/teams';
  static const createTeam = '/teams/new';
  static const tournaments = '/tournaments';
  static const rankings = '/rankings';
  static const profile = '/profile';

  static String team(String teamId) => '/teams/$teamId';
  static String newPlay(String teamId) => '/teams/$teamId/plays/new';
  static String play(String teamId, String playId) =>
      '/teams/$teamId/plays/$playId';
  static String newEvent(String teamId, {DateTime? day}) => Uri(
    path: '/teams/$teamId/events/new',
    queryParameters: day == null
        ? null
        : {'date': day.toIso8601String().substring(0, 10)},
  ).toString();
  static String event(String teamId, String eventId) =>
      '/teams/$teamId/events/$eventId';
  static String editEvent(String teamId, String eventId) =>
      '/teams/$teamId/events/$eventId/edit';
  static String tournament(String id) => '/tournaments/$id';
  static const usauTeamPath = '/rankings/team';
  static String usauTeam(String url, {String name = ''}) => Uri(
    path: usauTeamPath,
    queryParameters: {'url': url, if (name.isNotEmpty) 'name': name},
  ).toString();
}
