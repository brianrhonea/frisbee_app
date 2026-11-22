import '../../../domain/models/payments.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import 'payment_repository.dart';

/// [PaymentRepository] through the API (`/v1/teams/:id/payouts*`,
/// `/v1/tournaments/:id/pay` and `/checkout`). Without an API client,
/// online payments are simply off.
class PaymentRepositoryApi implements PaymentRepository {
  PaymentRepositoryApi({required ApiClient? api}) : _api = api;

  final ApiClient? _api;

  static String _id(String id) => Uri.encodeComponent(id);

  ApiClient get _client =>
      _api ??
      (throw const ApiException(
        'failed_precondition',
        "Online payments aren't set up here yet.",
      ));

  static Uri _url(Map<String, Object?> json) {
    final url = Uri.tryParse(json['url'] as String? ?? '');
    if (url == null || url.scheme != 'https') {
      throw const ApiException('internal', 'Stripe sent back no page.');
    }
    return url;
  }

  @override
  Future<Result<PaymentFees>> fees() async {
    if (_api == null) return const Result.ok(PaymentFees.unavailable);
    return guard(
      () async =>
          PaymentFees.fromMap(await _client.send('GET', '/v1/payments/fees')),
    );
  }

  @override
  Future<Result<PayoutAccount>> payouts(String teamId) async {
    if (_api == null) return const Result.ok(PayoutAccount.unavailable);
    return guard(
      () async => PayoutAccount.fromMap(
        await _client.send('GET', '/v1/teams/${_id(teamId)}/payouts'),
      ),
    );
  }

  @override
  Future<Result<Uri>> payoutLink(String teamId) => guard(
    () async =>
        _url(await _client.post('/v1/teams/${_id(teamId)}/payouts/link', {})),
  );

  @override
  Future<Result<PayOptions>> payOptions(
    String tournamentId, {
    String? teamId,
  }) => guard(
    () async => PayOptions.fromMap(
      await _client.send(
        'GET',
        '/v1/tournaments/${_id(tournamentId)}/pay'
            '${teamId == null ? '' : '?team=${_id(teamId)}'}',
      ),
    ),
  );

  @override
  Future<Result<Uri>> checkout(String tournamentId, {String? teamId}) => guard(
    () async => _url(
      await _client.post('/v1/tournaments/${_id(tournamentId)}/checkout', {
        'payer': teamId == null ? 'player' : 'team',
        'teamId': ?teamId,
      }),
    ),
  );
}
