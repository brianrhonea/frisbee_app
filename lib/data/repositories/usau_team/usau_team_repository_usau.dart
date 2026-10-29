import '../../../domain/models/usau_team.dart';
import '../../../utils/result.dart';
import '../../services/usau/usau_client.dart';
import '../../services/usau/usau_parser.dart';
import 'usau_team_repository.dart';

/// Scrapes a team page from USA Ultimate the first time it is opened and
/// keeps it in memory for the rest of the session.
class UsauTeamRepositoryUsau implements UsauTeamRepository {
  UsauTeamRepositoryUsau({required UsauClient client}) : _client = client;

  final UsauClient _client;
  final _cache = <String, Future<UsauTeam>>{};

  @override
  Future<Result<UsauTeam>> getTeam(String url) => guard(() async {
    // The url arrives via a route query parameter; only fetch USAU pages.
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != Uri.parse(usauBase).host) {
      throw Exception('Not a USA Ultimate team page: $url');
    }
    final pending = _cache[url] ??= _client.fetchTeam(url);
    try {
      return await pending;
    } catch (_) {
      // Allow a retry to fetch again.
      if (identical(_cache[url], pending)) _cache.remove(url);
      rethrow;
    }
  });
}
