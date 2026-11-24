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
  bool get available => _api != null;

  @override
  Future<Result<void>> payOffline(
    String tournamentId, {
    String? teamId,
    required bool offline,
  }) => guard(() async {
    await _client.send(
      'PUT',
      '/v1/tournaments/${_id(tournamentId)}/pay/offline',
      {
        'payer': teamId == null ? 'player' : 'team',
        'teamId': ?teamId,
        'offline': offline,
      },
    );
  });

  @override
  Future<Result<void>> mark(
    String tournamentId,
    String payerId, {
    required bool paid,
    required String note,
  }) => guard(() async {
    await _client.send(
      'PUT',
      '/v1/tournaments/${_id(tournamentId)}/payments/${_id(payerId)}',
      {'paid': paid, 'note': note},
    );
  });

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
  Future<Result<String>> payoutSession(String teamId) => guard(() async {
    final json = await _client.post(
      '/v1/teams/${_id(teamId)}/payouts/session',
      {},
    );
    final secret = json['clientSecret'];
    if (secret is! String || secret.isEmpty) {
      throw const ApiException(
        'unavailable',
        "Stripe's setup didn't open. Try again.",
      );
    }
    return secret;
  });

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
  Future<Result<PaymentSheetRequest>> paymentSheet(
    String tournamentId, {
    String? teamId,
  }) => guard(() async {
    final r = PaymentSheetRequest.fromMap(
      await _client.post('/v1/tournaments/${_id(tournamentId)}/pay/intent', {
        'payer': teamId == null ? 'player' : 'team',
        'teamId': ?teamId,
      }),
    );
    if (r.clientSecret.isEmpty) {
      throw const ApiException('internal', 'Stripe sent back no payment.');
    }
    return r;
  });

  @override
  Future<Result<void>> refund(String tournamentId, String payerId) => guard(
    () async {
      await _client.post(
        '/v1/tournaments/${_id(tournamentId)}/payments/${_id(payerId)}/refund',
        const {},
      );
    },
  );

  @override
  Future<Result<Earnings>> earnings(String teamId) => guard(
    () async => Earnings.fromMap(
      await _client.send('GET', '/v1/teams/${_id(teamId)}/earnings'),
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
