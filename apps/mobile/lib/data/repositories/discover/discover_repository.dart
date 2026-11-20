import '../../../domain/models/discover.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';

/// What Discover reads from the API's public lists, as the website does:
/// public team events (pickup games) and team spots left on tournaments.
abstract class DiscoverRepository {
  /// Upcoming public team events across teams and communities, soonest
  /// first (`GET /v1/public/events`).
  Future<Result<List<PublicTeamEvent>>> upcomingEvents();

  /// Team spots left by tournament id, for events open for registration
  /// (`GET /v1/public/tournaments`' `spots`). Events without any are left
  /// out.
  Future<Result<Map<String, TournamentSpots>>> tournamentSpots();
}

/// Reads them through the API. Builds without `API_BASE_URL` get no
/// public lists: no events and no spots (nothing to fall back to).
class DiscoverRepositoryApi implements DiscoverRepository {
  DiscoverRepositoryApi({required ApiClient? api}) : _api = api;

  final ApiClient? _api;

  /// One read of each list is reused this long (the API caches them for
  /// 30 to 60 seconds anyway).
  static const fresh = Duration(minutes: 1);

  // Reads in flight are shared too, so two view models asking at once
  // (Discover has two) cost one request. A failure isn't kept.
  (DateTime, Future<Result<List<PublicTeamEvent>>>)? _events;
  (DateTime, Future<Result<Map<String, TournamentSpots>>>)? _spots;

  static bool _isFresh(DateTime at) => DateTime.now().difference(at) < fresh;

  @override
  Future<Result<List<PublicTeamEvent>>> upcomingEvents() {
    final api = _api;
    if (api == null) return Future.value(const Result.ok([]));
    if (_events case (final at, final read) when _isFresh(at)) return read;
    final read = guard(() async {
      final json = await api.send('GET', '/v1/public/events');
      return [
        for (final e in (json['events'] as List?) ?? const [])
          ?PublicTeamEvent.fromJson(e),
      ];
    });
    final entry = (DateTime.now(), read);
    _events = entry;
    read.then((r) {
      if (r is Error && identical(_events, entry)) _events = null;
    });
    return read;
  }

  @override
  Future<Result<Map<String, TournamentSpots>>> tournamentSpots() {
    final api = _api;
    if (api == null) return Future.value(const Result.ok({}));
    if (_spots case (final at, final read) when _isFresh(at)) return read;
    final read = guard(() async {
      final json = await api.send('GET', '/v1/public/tournaments');
      return <String, TournamentSpots>{
        for (final t in (json['tournaments'] as List?) ?? const [])
          if (t is Map && t['id'] is String)
            t['id'] as String: ?TournamentSpots.fromJson(t['spots']),
      };
    });
    final entry = (DateTime.now(), read);
    _spots = entry;
    read.then((r) {
      if (r is Error && identical(_spots, entry)) _spots = null;
    });
    return read;
  }
}
