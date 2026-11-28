import '../../../domain/models/team_history.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';

/// A player's roster history across teams, read through the API. The server
/// decides what the viewer may see (their own always; others' only when the
/// profile is public and shows Stats and Teams).
abstract class TeamHistoryRepository {
  /// Every team [uid] was linked to, current teams first, then the latest
  /// season, then name (`GET /v1/players/:uid/team-history`).
  Future<Result<List<TeamHistoryEntry>>> teamHistory(String uid);
}

/// Reads it through the API. Builds without `API_BASE_URL` have no history:
/// an empty list.
class TeamHistoryRepositoryApi implements TeamHistoryRepository {
  TeamHistoryRepositoryApi({required ApiClient? api}) : _api = api;

  final ApiClient? _api;

  @override
  Future<Result<List<TeamHistoryEntry>>> teamHistory(String uid) {
    final api = _api;
    if (api == null) return Future.value(const Result.ok([]));
    return guard(() async {
      final json = await api.send(
        'GET',
        '/v1/players/${Uri.encodeComponent(uid)}/team-history',
      );
      return [
        for (final e in (json['teams'] as List?) ?? const [])
          ?TeamHistoryEntry.fromJson(e),
      ];
    });
  }
}
