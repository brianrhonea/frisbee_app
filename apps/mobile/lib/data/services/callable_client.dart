import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'account_gate_retry.dart';
import 'api_client.dart';
import 'app_check.dart';

/// Thrown when a callable Cloud Function turns a request down; [message] is
/// the function's own, ready to show.
class CallableException implements Exception {
  const CallableException(this.message, {this.fields});

  final String message;

  /// Set when the function refused with `account_incomplete`: what is
  /// missing (docs/specifications/contracts/account-gate.md).
  final Map<String, String>? fields;

  @override
  String toString() => message;
}

/// Calls callable Cloud Functions (`group-name`) over HTTPS with the
/// user's ID token. Like MeetingTokenService, it speaks the callable
/// protocol directly rather than through the cloud_functions plugin.
class CallableClient {
  CallableClient({
    required String projectId,
    FirebaseAuth? auth,
    http.Client? client,
    String region = 'us-central1',
    ApiClient? api,
  }) : _projectId = projectId,
       _region = region,
       _gate = AccountGateRetry(api),
       _auth = auth,
       _client = client ?? http.Client();

  static const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

  final String _projectId;
  final String _region;
  final FirebaseAuth? _auth;
  final http.Client _client;
  final AccountGateRetry _gate;

  Uri _endpoint(String name) => _useEmulators
      ? Uri.parse('http://localhost:5001/$_projectId/$_region/$name')
      : Uri.parse('https://$_region-$_projectId.cloudfunctions.net/$name');

  /// Calls function [name] with [data] and returns its result.
  ///
  /// A gated function's `account_incomplete` refusal follows the account
  /// gate contract once (see [AccountGateRetry]): status check, token
  /// refresh, one retry, then routing by the first missing step.
  Future<Object?> call(String name, Map<String, Object?> data) => _gate.run(
    () => _callOnce(name, data),
    (e) => e is CallableException ? e.fields : null,
  );

  Future<Object?> _callOnce(String name, Map<String, Object?> data) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) throw const CallableException('Not signed in.');
    final idToken = await user.getIdToken();
    final response = await _client.post(
      _endpoint(name),
      headers: {
        'Content-Type': 'application/json',
        ...await AppCheck.headers(),
        'Authorization': ?(idToken == null ? null : 'Bearer $idToken'),
      },
      body: jsonEncode({'data': data}),
    );
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw CallableException(
        "Couldn't reach the server (${response.statusCode}).",
      );
    }
    if (body is Map && body.containsKey('result')) return body['result'];
    final error = body is Map ? body['error'] : null;
    throw CallableException(
      error is Map && error['message'] is String
          ? error['message'] as String
          : 'Something went wrong (${response.statusCode}).',
      fields: accountIncompleteFields(error),
    );
  }
}

/// Undoes the functions' JSON encoding of Firestore values: `{__ts: millis}`
/// becomes a DateTime, as `plainData` gives them.
Object? fromCallableJson(Object? value) => switch (value) {
  {'__ts': final int ms} when value.length == 1 =>
    DateTime.fromMillisecondsSinceEpoch(ms),
  Map m => <String, dynamic>{
    for (final MapEntry(:key, :value) in m.entries)
      '$key': fromCallableJson(value),
  },
  List l => l.map(fromCallableJson).toList(),
  _ => value,
};
