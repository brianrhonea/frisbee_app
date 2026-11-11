import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'app_check.dart';

/// The API turned a request down; [message] is the API's own, ready to
/// show. [code] is one of ApiErrorCode in packages/shared/src/api.ts.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.fields = const {}});

  final String code;
  final String message;

  /// Per-field messages, for `invalid_argument`.
  final Map<String, String> fields;

  @override
  String toString() => message;
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
      _client = client ?? http.Client();

  static const _baseUrl = String.fromEnvironment('API_BASE_URL');

  /// The client for this build's `API_BASE_URL`, or null without one.
  static ApiClient? fromEnvironment() =>
      _baseUrl.isEmpty ? null : ApiClient(baseUrl: Uri.parse(_baseUrl));

  final Uri _base;
  final FirebaseAuth? _auth;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  /// POSTs [body] as JSON to [path] (like `/v1/teams`) and returns the
  /// decoded JSON answer.
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw const ApiException('unauthenticated', 'Not signed in.');
    }
    final idToken = await user.getIdToken();
    final http.Response response;
    try {
      response = await _client
          .post(
            _base.resolve(path),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
              ...await AppCheck.headers(),
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on Exception {
      throw const ApiException(
        'unavailable',
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
    return _decode(response);
  }

  static Map<String, Object?> _decode(http.Response response) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        'internal',
        "Couldn't reach the server (${response.statusCode}).",
      );
    }
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (ok && json is Map<String, Object?>) return json;
    final error = json is Map ? json['error'] : null;
    if (error is Map && error['message'] is String) {
      final fields = error['fields'];
      throw ApiException(
        error['code'] as String? ?? 'internal',
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
