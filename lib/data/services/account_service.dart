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

/// Thrown when signing in with a username fails; [message] is fit to show
/// the user ("Incorrect username or password.").
class UsernameSignInException implements Exception {
  const UsernameSignInException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the `account-*` callable Cloud Functions over HTTPS:
/// `account-deleteAccount`, which deletes the signed-in user's data and
/// login, and `account-signInEmail`, which finds the email to sign in with
/// for a username. Plain HTTPS like `MeetingTokenService`, so it works on
/// Windows too.
class AccountService {
  AccountService({
    required String projectId,
    FirebaseAuth? auth,
    http.Client? client,
    String region = 'us-central1',
  }) : _auth = auth,
       _client = client ?? http.Client(),
       _base = _useEmulators
           ? 'http://localhost:5001/$projectId/$region/'
           : 'https://$region-$projectId.cloudfunctions.net/';

  static const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

  final FirebaseAuth? _auth;
  final http.Client _client;
  final String _base;

  Uri _endpoint(String name) => Uri.parse('$_base$name');

  static String? _errorText(Object? body) {
    final error = body is Map ? body['error'] : null;
    return error is Map && error['message'] is String
        ? error['message'] as String
        : null;
  }

  static Object? _json(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// The email of the account [username] belongs to, once the server has
  /// checked [password] for it. Throws [UsernameSignInException].
  Future<String> emailForUsername(String username, String password) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint('account-signInEmail'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'data': {'username': username, 'password': password},
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw const UsernameSignInException(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
    final body = _json(response.body);
    final result = body is Map ? body['result'] : null;
    if (response.statusCode == 200 &&
        result is Map &&
        result['email'] is String) {
      return result['email'] as String;
    }
    throw UsernameSignInException(
      _errorText(body) ?? "Couldn't sign in right now. Try again.",
    );
  }

  Future<void> deleteAccount() async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) throw const AccountDeletionException('Not signed in.');
    // Fresh token, so the function sees the sign-in the user just repeated.
    final idToken = await user.getIdToken(true);
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint('account-deleteAccount'),
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
    final body = _json(response.body);
    if (response.statusCode == 200 && body is Map && body['result'] != null) {
      return;
    }
    throw AccountDeletionException(
      _errorText(body) ??
          "Couldn't delete your account (${response.statusCode}). "
              'Try again.',
    );
  }
}
