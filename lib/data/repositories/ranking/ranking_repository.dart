import '../../../domain/models/ranking.dart';

abstract class RankingRepository {
  /// All cached USA Ultimate ranking lists, sorted by label.
  Stream<List<RankingDivision>> watchDivisions();
}
