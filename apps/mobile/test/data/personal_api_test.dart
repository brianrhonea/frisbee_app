import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/personal/personal_repository_api.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../testing/fakes.dart';

void main() {
  late List<Map<String, Object?>> sent;
  late Map<String, http.Response Function()> routes;

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  PersonalDetailsRepositoryApi repo() => PersonalDetailsRepositoryApi(
    api: ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1')),
      client: MockClient((req) async {
        sent.add({
          'method': req.method,
          'path': req.url.path,
          if (req.body.isNotEmpty) 'body': jsonDecode(req.body),
        });
        return (routes['${req.method} ${req.url.path}'] ?? () => json({}))();
      }),
    ),
    auth: FakeAuthRepository(user: const AppUser(uid: 'u1')),
  );

  setUp(() {
    sent = [];
    routes = {
      'GET /v1/me/personal/status': () =>
          json({'complete': false, 'required': true}),
    };
  });

  group('the sign-up birthday through the API', () {
    test('saves just the date, leaving the details incomplete', () async {
      final r = repo();
      await r.refreshStatus();
      final result = await r.saveSignUpBirthDate(DateTime(1995, 4, 2));
      expect(result, isA<Ok<void>>());
      expect(sent.last, {
        'method': 'PUT',
        'path': '/v1/me/personal/birth-date',
        'body': {'birthDate': '1995-04-02'},
      });
      expect(r.mustComplete, isTrue);
    });

    test('under 13 by the API is a TooYoungException', () async {
      routes['PUT /v1/me/personal/birth-date'] = () => json({
        'error': {
          'code': 'failed_precondition',
          'message': tooYoungMessage,
          'fields': {'birthDate': tooYoungMessage},
        },
      }, 412);
      final result = await repo().saveSignUpBirthDate(DateTime(2020, 1, 1));
      expect(result, isA<Error<void>>());
      expect((result as Error<void>).error, isA<TooYoungException>());
    });

    test('load reads it back for About you', () async {
      routes['GET /v1/me/personal'] = () => json({
        'details': null,
        'email': 'pat@x.test',
        'signUpBirthDate': '1995-04-02',
      });
      final result = await repo().load();
      final value = (result as Ok).value;
      expect(value.details, isNull);
      expect(value.signUpBirthDate, DateTime.utc(1995, 4, 2));
    });

    test('without an API it fails softly', () async {
      final r = PersonalDetailsRepositoryApi(
        api: null,
        auth: FakeAuthRepository(user: const AppUser(uid: 'u1')),
      );
      expect(
        await r.saveSignUpBirthDate(DateTime(1995, 4, 2)),
        isA<Error<void>>(),
      );
    });
  });
}
