import '../../../domain/models/team_share.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';

/// Splitting a team fee (`/v1/teams/:id/share`; team_share.ts).
abstract class TeamShareRepository {
  Future<Result<TeamShareView>> view(String teamId);

  /// Starts or changes the split; whoever sets it up collects it.
  Future<Result<TeamShareView>> set(
    String teamId, {
    required int amountCents,
    required String note,
  });

  /// Stops splitting the fee.
  Future<Result<void>> clear(String teamId);

  /// Marks [uid] paid or not (the collector, or Manage team).
  Future<Result<TeamShareView>> markPaid(
    String teamId,
    String uid, {
    required bool paid,
  });
}

/// [TeamShareRepository] through the API. Without one (an old build),
/// there's no split to show.
class TeamShareRepositoryApi implements TeamShareRepository {
  TeamShareRepositoryApi({required ApiClient? api}) : _api = api;

  final ApiClient? _api;

  String _path(String teamId) =>
      '/v1/teams/${Uri.encodeComponent(teamId)}/share';

  ApiClient get _client =>
      _api ??
      (throw const ApiException(
        'unavailable',
        "This version of the app can't do that. Update the app.",
      ));

  @override
  Future<Result<TeamShareView>> view(String teamId) => guard(() async {
    final api = _api;
    if (api == null) return TeamShareView.none;
    return TeamShareView.fromJson(await api.send('GET', _path(teamId)));
  });

  @override
  Future<Result<TeamShareView>> set(
    String teamId, {
    required int amountCents,
    required String note,
  }) => guard(() async {
    final json = await _client.put(_path(teamId), {
      'amountCents': amountCents,
      'note': note.trim(),
    });
    return TeamShareView.fromJson(json);
  });

  @override
  Future<Result<void>> clear(String teamId) => guard(() async {
    await _client.delete(_path(teamId));
  });

  @override
  Future<Result<TeamShareView>> markPaid(
    String teamId,
    String uid, {
    required bool paid,
  }) => guard(() async {
    final json = await _client.put(
      '${_path(teamId)}/members/${Uri.encodeComponent(uid)}',
      {'paid': paid},
    );
    return TeamShareView.fromJson(json);
  });
}
