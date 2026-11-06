import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'app_check.dart';

/// Thrown when a callable Cloud Function turns a request down; [message] is
/// the function's own, ready to show.
class CallableException implements Exception {
  const CallableException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls callable Cloud Functions (`group-name`) over HTTPS with the
/// user's ID token. Like MeetingTokenService, it speaks the callable
/// protocol directly so it works on Windows too, where the cloud_functions
/// plugin isn't available.
class CallableClient {
  CallableClient({
    required String projectId,
    FirebaseAuth? auth,
    http.Client? client,
    String region = 'us-central1',
  }) : _projectId = projectId,
       _region = region,
       _auth = auth,
       _client = client ?? http.Client();

  static const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

  final String _projectId;
  final String _region;
  final FirebaseAuth? _auth;
  final http.Client _client;

  Uri _endpoint(String name) => _useEmulators
      ? Uri.parse('http://localhost:5001/$_projectId/$_region/$name')
      : Uri.parse('https://$_region-$_projectId.cloudfunctions.net/$name');

  /// Calls function [name] with [data] and returns its result. With
  /// [signedOut], calls without an account too (the website's `browse`
  /// functions), still sending the user's token when there is one.
  Future<Object?> call(
    String name,
    Map<String, Object?> data, {
    bool signedOut = false,
  }) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null && !signedOut) {
      throw const CallableException('Not signed in.');
    }
    final idToken = await user?.getIdToken();
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
