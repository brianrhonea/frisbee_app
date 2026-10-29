import '../../../domain/models/tournament.dart';
import '../../services/usau/usau_client.dart';
import 'tournament_repository.dart';

/// Scrapes tournaments from USA Ultimate on first use and keeps them in
/// memory for the rest of the session.
class TournamentRepositoryUsau implements TournamentRepository {
  TournamentRepositoryUsau({required UsauClient client}) : _client = client;

  final UsauClient _client;
  Future<List<Tournament>>? _cache;

  @override
  Stream<List<Tournament>> watchTournaments() async* {
    final pending = _cache ??= _load();
    try {
      yield await pending;
    } catch (_) {
      // Allow a retry to fetch again.
      if (identical(_cache, pending)) _cache = null;
      rethrow;
    }
  }

  Future<List<Tournament>> _load() async {
    final far = DateTime.utc(9999);
    return (await _client.fetchTournaments())
      ..sort((a, b) => (a.startDate ?? far).compareTo(b.startDate ?? far));
  }
}
