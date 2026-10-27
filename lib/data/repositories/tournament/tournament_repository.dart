import '../../../domain/models/tournament.dart';

abstract class TournamentRepository {
  /// All cached USA Ultimate tournaments, sorted by start date.
  Stream<List<Tournament>> watchTournaments();
}
