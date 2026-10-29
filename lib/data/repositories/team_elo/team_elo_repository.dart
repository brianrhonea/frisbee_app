import '../../../domain/models/team_elo.dart';

abstract class TeamEloRepository {
  /// Team Elo ratings per ranking list, keyed like the USAU rankings.
  Stream<List<TeamEloDivision>> watchDivisions();
}
