import '../../../utils/result.dart';
import '../../services/api_client.dart';

/// A hosted tournament's chats with its organizers (tournament_chats.ts in
/// packages/shared): its Captains' channel and each team's private thread.
/// Both are conversations in Messages that the server runs; opening one
/// brings who is in it up to date and returns the conversation id.
abstract class TournamentChatRepository {
  /// Whether this build can open them (they need the API).
  bool get available;

  /// The Captains' channel: the organizers and entered teams' captains.
  Future<Result<String>> openCaptains(String tournamentId);

  /// [teamId]'s private thread with the organizers.
  Future<Result<String>> openTeam(String tournamentId, String teamId);
}

/// [TournamentChatRepository] through the API
/// (`POST /v1/tournaments/:id/chats/captains` and `…/chats/teams/:teamId`).
class TournamentChatRepositoryApi implements TournamentChatRepository {
  TournamentChatRepositoryApi({required ApiClient? api}) : _api = api;

  final ApiClient? _api;

  static String _id(String id) => Uri.encodeComponent(id);

  ApiClient get _client =>
      _api ??
      (throw const ApiException(
        'failed_precondition',
        "Tournament chats aren't available in this build.",
      ));

  @override
  bool get available => _api != null;

  Future<Result<String>> _open(String path) => guard(() async {
    final r = await _client.send('POST', path, const {});
    final id = r['id'];
    if (id is! String || id.isEmpty) {
      throw const ApiException('internal', 'No conversation came back.');
    }
    return id;
  });

  @override
  Future<Result<String>> openCaptains(String tournamentId) =>
      _open('/v1/tournaments/${_id(tournamentId)}/chats/captains');

  @override
  Future<Result<String>> openTeam(String tournamentId, String teamId) =>
      _open('/v1/tournaments/${_id(tournamentId)}/chats/teams/${_id(teamId)}');
}
