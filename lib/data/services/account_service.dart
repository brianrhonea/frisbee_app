import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Thrown when the `account-deleteAccount` function turns the request
/// down or fails; [message] is fit to show the user.
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the `account-deleteAccount` callable Cloud Function over HTTPS,
/// which deletes the signed-in user's data and login. Plain HTTPS like
/// `MeetingTokenService`, so it works on Windows too.
class AccountService {
  AccountService({
    required String projectId,
    FirebaseAuth? auth,
    http.Client? client,
    String region = 'us-central1',
  }) : _auth = auth,
       _client = client ?? http.Client(),
       _endpoint = _useEmulators
           ? Uri.parse(
               'http://localhost:5001/$projectId/$region/account-deleteAccount',
             )
           : Uri.parse(
               'https://$region-$projectId.cloudfunctions.net/account-deleteAccount',
             );

  static const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

  final FirebaseAuth? _auth;
  final http.Client _client;
  final Uri _endpoint;

  Future<void> deleteAccount() async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) throw const AccountDeletionException('Not signed in.');
    // Fresh token, so the function sees the sign-in the user just repeated.
    final idToken = await user.getIdToken(true);
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'data': <String, Object?>{}}),
          )
          .timeout(const Duration(minutes: 9));
    } on Exception {
      throw const AccountDeletionException(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (response.statusCode == 200 && body is Map && body['result'] != null) {
      return;
    }
    final error = body is Map ? body['error'] : null;
    throw AccountDeletionException(
      error is Map && error['message'] is String
          ? error['message'] as String
          : "Couldn't delete your account (${response.statusCode}). "
                'Try again.',
    );
  }
}
