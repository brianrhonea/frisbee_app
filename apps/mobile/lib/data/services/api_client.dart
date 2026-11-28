import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'app_check.dart';

const accountIncompleteCode = 'account_incomplete';
const _statusPath = '/v1/me/personal/status';

/// The API turned a request down; [message] is the API's own, ready to
/// show. [code] is one of ApiErrorCode in packages/shared/src/api.ts.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.fields = const {}});

  final String code;
  final String message;

  /// Per-field messages, for `invalid_argument`.
  final Map<String, String> fields;

  /// 403 `account_incomplete`: the account can read but not write yet
  /// (docs/specifications/contracts/account-gate.md). [fields] names what
  /// is missing.
  bool get accountIncomplete => code == accountIncompleteCode;

  @override
  String toString() => message;
}

/// Writes that go through the API have no direct-to-Firestore fallback
/// (contracts/phase1-writes.md D10): a build without an `API_BASE_URL` can't
/// make them, and says so.
extension RequiredApi on ApiClient? {
  /// This client, or an [ApiException] when the build has no API.
  ApiClient get required =>
      this ??
      (throw const ApiException(
        'failed_precondition',
        "This version of the app can't do that. Update the app.",
      ));
}

/// Calls the Stall 10 API (apps/api) with the user's Firebase ID token and
/// App Check token. The API validates every request and reads and writes
/// Firebase for the app; see ARCHITECTURE.md.
///
/// The base URL comes from `API_BASE_URL` in the secrets file. Builds
/// without one get no client ([fromEnvironment] returns null), and
/// repositories fall back to talking to Firestore directly.
class ApiClient {
  ApiClient({required Uri baseUrl, FirebaseAuth? auth, http.Client? client})
    : _base = baseUrl,
      _auth = auth,
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  static const _baseUrl = String.fromEnvironment('API_BASE_URL');

  /// The client for this build's `API_BASE_URL`, or null without one.
  static ApiClient? fromEnvironment() =>
      _baseUrl.isEmpty ? null : ApiClient(baseUrl: Uri.parse(_baseUrl));

  /// Told when a write is still refused as `account_incomplete` after the
  /// one retry (the app then routes by the first field). Set by
  /// dependencies.dart.
  void Function(Map<String, String> fields)? onAccountIncomplete;

  final Uri _base;
  final FirebaseAuth? _auth;
  http.Client _client;
  final bool _ownsClient;

  static const _timeout = Duration(seconds: 20);

  static const _offline = ApiException(
    'unavailable',
    "Couldn't reach the server. Check your connection and try again.",
  );

  /// Drops the connections kept alive from before (after the app returns
  /// from the background they may be dead); the next request opens new
  /// ones. A client given to the constructor is left alone.
  void resetConnections() {
    if (!_ownsClient) return;
    final old = _client;
    _client = http.Client();
    // Requests still going on the old connections finish first.
    Timer(const Duration(seconds: 30), old.close);
  }

  /// The API's address, for the connection check (`GET /health`).
  Uri get baseUrl => _base;

  /// POSTs [body] as JSON to [path] (like `/v1/teams`) and returns the
  /// decoded JSON answer.
  Future<Map<String, Object?>> post(String path, Map<String, Object?> body) =>
      send('POST', path, body);

  /// PUTs [body] as JSON to [path]; returns the decoded answer.
  Future<Map<String, Object?>> put(String path, Map<String, Object?> body) =>
      send('PUT', path, body);

  /// PATCHes [path] with [body] as JSON; returns the decoded answer.
  Future<Map<String, Object?>> patch(String path, Map<String, Object?> body) =>
      send('PATCH', path, body);

  /// DELETEs [path], with [body] as JSON when given (most have none);
  /// returns the decoded answer. [timeout] is for deletes that cascade.
  Future<Map<String, Object?>> delete(
    String path, [
    Map<String, Object?>? body,
    Duration timeout = _timeout,
  ]) => send('DELETE', path, body, timeout);

  /// Sends [method] to [path], with [body] as JSON when given, and returns
  /// the decoded JSON answer or throws [ApiException].
  ///
  /// A 403 `account_incomplete` is handled here, once: ask for the account
  /// status (which sets any claims it already earns), and when that says to
  /// refresh the token, do and send the request again. Still refused (or
  /// nothing to refresh): [onAccountIncomplete] hears which steps are
  /// missing and the [ApiException] is thrown. No loop: one retry only.
  /// Any answer with `refreshToken: true` refreshes the ID token.
  Future<Map<String, Object?>> send(
    String method,
    String path, [
    Map<String, Object?>? body,
    Duration timeout = _timeout,
  ]) async {
    try {
      return await _sendOnce(method, path, body, timeout);
    } on ApiException catch (e) {
      if (!e.accountIncomplete || path == _statusPath) rethrow;
      final refreshed = await refreshFromAccountStatus();
      if (!refreshed) {
        onAccountIncomplete?.call(e.fields);
        rethrow;
      }
      try {
        return await _sendOnce(method, path, body, timeout);
      } on ApiException catch (again) {
        if (again.accountIncomplete) onAccountIncomplete?.call(again.fields);
        rethrow;
      }
    }
  }

  /// Asks the account status route (never gated), which sets any claims the
  /// account already earns. True when it said `refreshToken: true`, in which
  /// case the ID token is already refreshed (see [_sendOnce]) and a refused
  /// write is worth one retry. A failing status call is false: the original
  /// refusal stands. Shared with callables (account_gate_retry.dart).
  Future<bool> refreshFromAccountStatus() async {
    try {
      final status = await _sendOnce('GET', _statusPath, null, _timeout);
      return status['refreshToken'] == true;
    } on Exception {
      return false;
    }
  }

  Future<Map<String, Object?>> _sendOnce(
    String method,
    String path,
    Map<String, Object?>? body,
    Duration timeout,
  ) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw const ApiException('unauthenticated', 'Not signed in.');
    }
    final String? idToken;
    final Map<String, String> appCheck;
    try {
      idToken = await user.getIdToken();
      appCheck = await AppCheck.headers();
    } on FirebaseAuthException catch (e) {
      // Offline, an expired token can't be refreshed: that's the
      // connection, not the account (the offline queue waits for it).
      if (e.code == 'network-request-failed') throw _offline;
      rethrow;
    }
    http.Request build() {
      final request = http.Request(method, _base.resolve(path))
        ..headers.addAll({'Authorization': 'Bearer $idToken', ...appCheck});
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body);
      }
      return request;
    }

    Future<http.Response> sendIt() async => http.Response.fromStream(
      await _client.send(build()).timeout(timeout),
    ).timeout(timeout);

    http.Response response;
    var resent = false;
    try {
      response = await sendIt();
    } on Exception catch (e) {
      if (!_staleConnection(e)) throw _offline;
      // A kept-alive connection that died (after the app was in the
      // background): open a new one. Only for requests that are safe to
      // send twice; the offline queue retries the others itself, with its
      // own duplicate checks.
      resetConnections();
      if (!_safeToRepeat(method, path)) throw _offline;
      try {
        resent = true;
        response = await sendIt();
      } on Exception {
        throw _offline;
      }
    }
    // The first DELETE may have reached the server before the connection
    // dropped: "not found" on the resent one means it is already gone.
    if (resent && method == 'DELETE' && response.statusCode == 404) {
      return const {};
    }
    final answer = _decode(response);
    if (answer['refreshToken'] == true) {
      // The API changed this account's claims; they reach us only in a new
      // ID token, which the next write needs.
      try {
        await user.getIdToken(true);
      } on Exception {
        // Offline: a later refusal runs the steps above again.
      }
    }
    return answer;
  }

  static bool _staleConnection(Exception e) =>
      e is SocketException || e is http.ClientException;

  /// Never for payment routes (fees, payments, refunds, payouts): a repeat
  /// there is the server's idempotency to decide, not the client's.
  static bool _safeToRepeat(String method, String path) =>
      (method == 'GET' || method == 'PUT' || method == 'DELETE') &&
      !_isPaymentPath(path);

  static bool _isPaymentPath(String path) => Uri.parse(path).pathSegments.any(
    (s) => const {'pay', 'payments', 'payouts', 'refund'}.contains(s),
  );

  static Map<String, Object?> _decode(http.Response response) {
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    // 204 No Content (deletes, invites and the like).
    if (ok && response.bodyBytes.isEmpty) return const {};
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        'internal',
        "Couldn't reach the server (${response.statusCode}).",
      );
    }
    if (ok && json is Map<String, Object?>) return json;
    final error = json is Map ? json['error'] : null;
    if (error is Map && error['message'] is String) {
      final fields = error['fields'];
      throw ApiException(
        // A non-string code is the server's mistake, not ours to throw on.
        error['code'] is String ? error['code'] as String : 'internal',
        error['message'] as String,
        fields: fields is Map
            ? {for (final e in fields.entries) '${e.key}': '${e.value}'}
            : const {},
      );
    }
    throw ApiException(
      'internal',
      'Something went wrong (${response.statusCode}).',
    );
  }
}
