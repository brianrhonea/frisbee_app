import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/meeting.dart';

/// Thrown when the `meetings-joinToken` function turns the request down,
/// e.g. the meeting hasn't started or the user hasn't been let in.
class MeetingAccessException implements Exception {
  const MeetingAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the `meetings-joinToken` callable Cloud Function over HTTPS.
///
/// The callable protocol is plain JSON with the user's ID token, so this
/// works on every platform, including Windows where the cloud_functions
/// plugin isn't available.
class MeetingTokenService {
  MeetingTokenService({
    required String projectId,
    FirebaseAuth? auth,
    http.Client? client,
    String region = 'us-central1',
  }) : _auth = auth,
       _client = client ?? http.Client(),
       _endpoint = _useEmulators
           ? Uri.parse(
               'http://localhost:5001/$projectId/$region/meetings-joinToken',
             )
           : Uri.parse(
               'https://$region-$projectId.cloudfunctions.net/meetings-joinToken',
             );

  static const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

  final FirebaseAuth? _auth;
  final http.Client _client;
  final Uri _endpoint;

  Future<MeetingAccess> joinToken(String teamId, String meetingId) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) throw const MeetingAccessException('Not signed in.');
    final idToken = await user.getIdToken();
    final response = await _client.post(
      _endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'data': {'teamId': teamId, 'meetingId': meetingId},
      }),
    );
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw MeetingAccessException(
        "Couldn't reach the meeting server (${response.statusCode}).",
      );
    }
    if (body is Map && body['result'] is Map) {
      final result = body['result'] as Map;
      return MeetingAccess(
        url: '${result['url']}',
        token: '${result['token']}',
      );
    }
    final error = body is Map ? body['error'] : null;
    throw MeetingAccessException(
      error is Map && error['message'] is String
          ? error['message'] as String
          : "Couldn't join the meeting (${response.statusCode}).",
    );
  }
}
