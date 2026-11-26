import 'api_client.dart';

/// The per-field messages of a callable error body when it is the gate's
/// refusal (`permission-denied` with `details.code == account_incomplete`,
/// firebase/functions/src/account/gate.ts), else null.
Map<String, String>? accountIncompleteFields(Object? error) {
  if (error is! Map) return null;
  final details = error['details'];
  if (details is! Map || details['code'] != accountIncompleteCode) return null;
  if (error['status'] != 'PERMISSION_DENIED') return null;
  final fields = details['fields'];
  return fields is Map
      ? {for (final e in fields.entries) '${e.key}': '${e.value}'}
      : const {};
}

/// Runs a callable under the account gate contract
/// (docs/specifications/contracts/account-gate.md sections 2 and 9), the
/// way [ApiClient.send] does for the API's 403: on `account_incomplete`,
/// ask the status route once; when it says to refresh (the token is then
/// refreshed), retry once; still refused, or nothing to refresh, report
/// the fields through [ApiClient.onAccountIncomplete] (the app routes to the
/// first missing step) and rethrow. No loop. Other errors pass through.
///
/// Without an [ApiClient] (a build with no API_BASE_URL) there is no status
/// route to ask, so the refusal is thrown as is.
class AccountGateRetry {
  const AccountGateRetry(this._api);

  final ApiClient? _api;

  /// Runs [attempt]; [fieldsOf] returns the missing fields when the thrown
  /// error is an `account_incomplete` refusal, else null.
  Future<T> run<T>(
    Future<T> Function() attempt,
    Map<String, String>? Function(Object error) fieldsOf,
  ) async {
    try {
      return await attempt();
    } on Exception catch (e) {
      final fields = fieldsOf(e);
      final api = _api;
      if (fields == null || api == null) rethrow;
      if (!await api.refreshFromAccountStatus()) {
        api.onAccountIncomplete?.call(fields);
        rethrow;
      }
      try {
        return await attempt();
      } on Exception catch (again) {
        final more = fieldsOf(again);
        if (more != null) api.onAccountIncomplete?.call(more);
        rethrow;
      }
    }
  }
}
