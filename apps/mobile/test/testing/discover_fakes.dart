import 'package:frisbee_app/data/repositories/discover/discover_repository.dart';
import 'package:frisbee_app/domain/models/discover.dart';
import 'package:frisbee_app/utils/result.dart';

/// Discover's public lists, set by the test.
class FakeDiscoverRepository implements DiscoverRepository {
  List<PublicTeamEvent> events = [];
  Map<String, TournamentSpots> spots = {};

  /// Fails the events read (spots still come back).
  bool eventsFail = false;
  int eventReads = 0;

  @override
  Future<Result<List<PublicTeamEvent>>> upcomingEvents() async {
    eventReads++;
    if (eventsFail) return Result.error(Exception('offline'));
    return Result.ok(events);
  }

  @override
  Future<Result<Map<String, TournamentSpots>>> tournamentSpots() async =>
      Result.ok(spots);
}
