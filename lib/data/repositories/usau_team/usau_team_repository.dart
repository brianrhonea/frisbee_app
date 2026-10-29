import '../../../domain/models/usau_team.dart';
import '../../../utils/result.dart';

abstract class UsauTeamRepository {
  /// The USA Ultimate team page at [url] (a ranking entry's `teamUrl`).
  Future<Result<UsauTeam>> getTeam(String url);
}
