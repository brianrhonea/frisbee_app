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
  static String tournament(String id) => '/tournaments/$id';
}
