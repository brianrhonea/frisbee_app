import '../../../domain/models/play.dart';
import '../../../utils/result.dart';

abstract class PlayRepository {
  /// Plays for a team, sorted by name.
  Stream<List<Play>> watchPlays(String teamId);

  Future<Result<Play>> getPlay(String teamId, String playId);

  /// Creates the play when [Play.isNew], otherwise updates it.
  /// Returns the saved play id.
  Future<Result<String>> savePlay(String teamId, Play play, String uid);

  Future<Result<void>> deletePlay(String teamId, String playId);
}
